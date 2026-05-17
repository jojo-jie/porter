import AppKit
import CryptoKit
import Foundation
import PorterCore

/// Downloads a remote file to a cache staging copy, opens it in the default app, and uploads on save.
@MainActor
final class RemoteFileEditCoordinator: ObservableObject {
    @Published private(set) var busySessionKeys: Set<String> = []

    private struct Session {
        let host: String
        let remotePath: String
        let fileName: String
        let localURL: URL
        let remoteParentDirectory: String
        var lastSyncedModificationDate: Date?
        var acceptsUploads: Bool
        var watcher: DirectoryChangeWatcher?
        var debouncedUploadTask: Task<Void, Never>?
        var isUploading: Bool
    }

    private var sessions: [String: Session] = [:]

    func sessionKey(host: String, remotePath: String) -> String {
        "\(host)\u{1F}|" + remotePath
    }

    func isBusy(host: String, remotePath: String) -> Bool {
        busySessionKeys.contains(sessionKey(host: host, remotePath: remotePath))
    }

    /// Prepares staging copy (if needed), opens the default app, and watches for saves.
    func beginEdit(host: String, remotePath: String, fileName: String) async -> String {
        let key = sessionKey(host: host, remotePath: remotePath)
        if let existing = sessions[key] {
            if !FileManager.default.fileExists(atPath: existing.localURL.path) {
                sessions.removeValue(forKey: key)
                busySessionKeys.remove(key)
            } else {
                NSWorkspace.shared.open(existing.localURL)
                return "已用默认应用打开：\(fileName)（保存后将自动上传）"
            }
        }

        busySessionKeys.insert(key)

        let stagingDirectory: URL
        let localURL: URL
        do {
            (stagingDirectory, localURL) = try Self.stagingLocations(host: host, remotePath: remotePath, fileName: fileName)
        } catch {
            busySessionKeys.remove(key)
            return "无法创建编辑暂存目录：\(error.localizedDescription)"
        }

        if FileManager.default.fileExists(atPath: localURL.path) {
            try? FileManager.default.removeItem(at: localURL)
        }

        let downloadMessage = await RemoteDownloader.download(
            host: host,
            remotePath: remotePath,
            destinationDirectory: stagingDirectory,
            remoteIsDirectory: false
        )
        guard downloadMessage.contains("下载完成") else {
            busySessionKeys.remove(key)
            return downloadMessage.replacingOccurrences(of: "下载完成", with: "无法开始编辑")
        }

        guard FileManager.default.fileExists(atPath: localURL.path) else {
            busySessionKeys.remove(key)
            return "下载后未找到本地文件，无法打开：\(fileName)"
        }

        let parentDirectory = Self.remoteParentDirectory(of: remotePath)
        var session = Session(
            host: host,
            remotePath: remotePath,
            fileName: fileName,
            localURL: localURL,
            remoteParentDirectory: parentDirectory,
            lastSyncedModificationDate: Self.fileModificationDate(at: localURL),
            acceptsUploads: false,
            watcher: nil,
            debouncedUploadTask: nil,
            isUploading: false
        )

        session.watcher = DirectoryChangeWatcher(directoryURL: stagingDirectory) { [weak self] in
            Task { @MainActor in
                self?.handleLocalFileChange(sessionKey: key)
            }
        }

        sessions[key] = session
        NSWorkspace.shared.open(localURL)

        sessions[key]?.acceptsUploads = true
        busySessionKeys.remove(key)

        return "已用默认应用打开：\(fileName)（保存后将自动上传到远端）"
    }

    private func handleLocalFileChange(sessionKey: String) {
        guard var session = sessions[sessionKey] else { return }
        guard session.acceptsUploads, !session.isUploading else { return }
        guard FileManager.default.fileExists(atPath: session.localURL.path) else { return }

        let currentDate = Self.fileModificationDate(at: session.localURL)
        if let last = session.lastSyncedModificationDate, let current = currentDate, current <= last {
            return
        }

        session.debouncedUploadTask?.cancel()
        session.debouncedUploadTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled else { return }
            await self?.uploadIfNeeded(sessionKey: sessionKey)
        }
        sessions[sessionKey] = session
    }

    private func uploadIfNeeded(sessionKey: String) async {
        guard var session = sessions[sessionKey] else { return }
        guard session.acceptsUploads, !session.isUploading else { return }
        guard FileManager.default.fileExists(atPath: session.localURL.path) else { return }

        let currentDate = Self.fileModificationDate(at: session.localURL)
        if let last = session.lastSyncedModificationDate, let current = currentDate, current <= last {
            return
        }

        session.isUploading = true
        sessions[sessionKey] = session
        busySessionKeys.insert(sessionKey)

        let result = await Self.uploadFile(
            host: session.host,
            localURL: session.localURL,
            remoteDirectory: session.remoteParentDirectory
        )

        session.isUploading = false
        busySessionKeys.remove(sessionKey)

        if result.success {
            session.lastSyncedModificationDate = Self.fileModificationDate(at: session.localURL) ?? currentDate
        }
        sessions[sessionKey] = session

        let notificationName: Notification.Name = result.success
            ? .porterRemoteEditSyncSucceeded
            : .porterRemoteEditSyncFailed
        NotificationCenter.default.post(
            name: notificationName,
            object: nil,
            userInfo: [
                "fileName": session.fileName,
                "message": result.message,
            ]
        )
    }

    private static func uploadFile(host: String, localURL: URL, remoteDirectory: String) async -> (success: Bool, message: String) {
        let script = PorterSFTPBatch.buildUploadScript(
            remoteDirectory: remoteDirectory,
            localAbsolutePath: localURL.path,
            isDirectory: false
        )
        let result = await Task.detached(priority: .userInitiated) {
            PorterSFTPBatch.run(host: host, batchScript: script)
        }.value

        if result.exitCode == 0 {
            return (true, "已同步到远端：\(localURL.lastPathComponent)")
        }
        let detail = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        if detail.isEmpty {
            return (false, "上传失败（退出码 \(result.exitCode)）")
        }
        return (false, "上传失败：\(detail)")
    }

    private static func remoteParentDirectory(of remoteFilePath: String) -> String {
        let segments = RemotePathCodec.split(remoteFilePath)
        guard segments.count > 1 else {
            return segments.first == "/" ? "/" : "~"
        }
        return RemotePathCodec.join(Array(segments.dropLast()))
    }

    private static func stagingLocations(host: String, remotePath: String, fileName: String) throws -> (directory: URL, file: URL) {
        guard let cachesRoot = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            throw CocoaError(.fileNoSuchFile)
        }
        let hostFolder = host
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        let digest = SHA256.hash(data: Data(remotePath.utf8))
        let pathHash = digest.prefix(12).map { String(format: "%02x", $0) }.joined()
        let directory = cachesRoot
            .appendingPathComponent("Porter/remote-edit", isDirectory: true)
            .appendingPathComponent(hostFolder, isDirectory: true)
            .appendingPathComponent(pathHash, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (directory, directory.appendingPathComponent(fileName, isDirectory: false))
    }

    private static func fileModificationDate(at url: URL) -> Date? {
        try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
    }
}

private final class DirectoryChangeWatcher {
    private let source: DispatchSourceFileSystemObject
    private let onChange: () -> Void

    init?(directoryURL: URL, onChange: @escaping () -> Void) {
        let fd = open(directoryURL.path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        self.onChange = onChange
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .attrib, .link, .rename, .revoke],
            queue: DispatchQueue.global(qos: .utility)
        )
        source.setEventHandler(handler: onChange)
        source.setCancelHandler {
            close(fd)
        }
        self.source = source
        source.resume()
    }

    deinit {
        source.cancel()
    }
}

extension Notification.Name {
    static let porterRemoteEditSyncFailed = Notification.Name("porter.remoteEditSyncFailed")
    static let porterRemoteEditSyncSucceeded = Notification.Name("porter.remoteEditSyncSucceeded")
}
