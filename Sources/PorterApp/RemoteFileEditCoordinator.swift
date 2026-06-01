import AppKit
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
        /// Set when the local file changes while an upload is in flight.
        var pendingUploadAfterCurrent: Bool
    }

    private var sessions: [String: Session] = [:]

    func sessionKey(host: String, remotePath: String) -> String {
        "\(host)\u{1F}|" + Self.canonicalRemotePath(remotePath)
    }

    func isBusy(host: String, remotePath: String) -> Bool {
        busySessionKeys.contains(sessionKey(host: host, remotePath: remotePath))
    }

    func hasEditSession(host: String, remotePath: String) -> Bool {
        sessions[sessionKey(host: host, remotePath: remotePath)] != nil
    }

    /// Clears a finished local edit session before a remote mutation such as rename/delete.
    ///
    /// Closing the default app does not reliably emit a filesystem event, so clean sessions can otherwise
    /// remain in memory and block remote operations indefinitely.
    func remoteMutationBlockMessage(host: String, remotePath: String, fileName: String) -> String? {
        pruneSessionsWithMissingLocalFiles()
        let key = sessionKey(host: host, remotePath: remotePath)
        guard let session = sessions[key] else { return nil }

        if session.isUploading || busySessionKeys.contains(key) {
            return "无法操作：\(fileName) 正在同步本地编辑，请稍后重试。"
        }

        if Self.localFileNeedsUpload(session: session) {
            handleLocalFileChange(sessionKey: key)
            return "无法操作：\(fileName) 还有本地编辑未同步，请等待同步完成后重试。"
        }

        endSession(sessionKey: key)
        return nil
    }

    var hasActiveEditSessions: Bool {
        !sessions.isEmpty
    }

    var isBusyForAnySession: Bool {
        !busySessionKeys.isEmpty
    }

    /// Drops in-memory edit sessions after local staging files were removed (e.g. cache clear).
    func discardAllSessions() {
        for key in sessions.keys {
            sessions[key]?.debouncedUploadTask?.cancel()
        }
        sessions.removeAll()
        busySessionKeys.removeAll()
    }

    /// Ends sessions whose local staging file no longer exists.
    func pruneSessionsWithMissingLocalFiles() {
        for key in sessions.keys where sessions[key] != nil {
            guard let session = sessions[key] else { continue }
            if !FileManager.default.fileExists(atPath: session.localURL.path) {
                endSession(sessionKey: key)
            }
        }
    }

    /// Prepares staging copy (if needed), opens the default app, and watches for saves.
    func beginEdit(host: String, remotePath: String, fileName: String) async -> String {
        pruneSessionsWithMissingLocalFiles()
        let normalizedRemotePath = Self.canonicalRemotePath(remotePath)
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
            (stagingDirectory, localURL) = try Self.stagingLocations(
                host: host,
                remotePath: normalizedRemotePath,
                fileName: fileName
            )
        } catch {
            busySessionKeys.remove(key)
            return "无法创建编辑暂存目录：\(error.localizedDescription)"
        }

        if FileManager.default.fileExists(atPath: localURL.path) {
            busySessionKeys.remove(key)
            return activateEditSession(
                key: key,
                host: host,
                remotePath: normalizedRemotePath,
                fileName: fileName,
                stagingDirectory: stagingDirectory,
                localURL: localURL,
                openedFromCache: true
            )
        }

        let downloadMessage = await RemoteDownloader.download(
            host: host,
            remotePath: normalizedRemotePath,
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

        busySessionKeys.remove(key)
        return activateEditSession(
            key: key,
            host: host,
            remotePath: normalizedRemotePath,
            fileName: fileName,
            stagingDirectory: stagingDirectory,
            localURL: localURL,
            openedFromCache: false
        )
    }

    private func activateEditSession(
        key: String,
        host: String,
        remotePath: String,
        fileName: String,
        stagingDirectory: URL,
        localURL: URL,
        openedFromCache: Bool
    ) -> String {
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
            isUploading: false,
            pendingUploadAfterCurrent: false
        )

        session.watcher = DirectoryChangeWatcher(directoryURL: stagingDirectory) { [weak self] in
            Task { @MainActor in
                self?.handleLocalFileChange(sessionKey: key)
            }
        }
        guard session.watcher != nil else {
            return "无法监视编辑暂存目录，保存后将无法自动上传。请检查磁盘权限或稍后重试。"
        }

        sessions[key] = session
        NSWorkspace.shared.open(localURL)
        sessions[key]?.acceptsUploads = true

        if openedFromCache {
            return "已用默认应用打开：\(fileName)（使用本地缓存，保存后将自动上传）"
        }
        return "已用默认应用打开：\(fileName)（保存后将自动上传到远端）"
    }

    private func handleLocalFileChange(sessionKey: String) {
        guard var session = sessions[sessionKey] else { return }
        guard session.acceptsUploads else { return }
        guard FileManager.default.fileExists(atPath: session.localURL.path) else {
            endSession(sessionKey: sessionKey)
            return
        }

        if session.isUploading {
            session.pendingUploadAfterCurrent = true
            sessions[sessionKey] = session
            return
        }

        guard Self.localFileNeedsUpload(session: session) else { return }

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
        guard FileManager.default.fileExists(atPath: session.localURL.path) else {
            endSession(sessionKey: sessionKey)
            return
        }
        guard Self.localFileNeedsUpload(session: session) else { return }

        let mtimeBeforeUpload = Self.fileModificationDate(at: session.localURL)
        session.isUploading = true
        session.pendingUploadAfterCurrent = false
        sessions[sessionKey] = session
        busySessionKeys.insert(sessionKey)

        let result = await Self.uploadFile(
            host: session.host,
            localURL: session.localURL,
            remoteDirectory: session.remoteParentDirectory
        )

        guard var session = sessions[sessionKey] else {
            busySessionKeys.remove(sessionKey)
            return
        }

        session.isUploading = false
        busySessionKeys.remove(sessionKey)

        if result.success {
            session.lastSyncedModificationDate = Self.fileModificationDate(at: session.localURL) ?? mtimeBeforeUpload
        }
        sessions[sessionKey] = session

        postSyncNotification(for: session, success: result.success, message: result.message)

        guard result.success else { return }

        let mtimeAfterUpload = Self.fileModificationDate(at: session.localURL)
        let changedDuringUpload = Self.fileModificationAdvanced(from: mtimeBeforeUpload, to: mtimeAfterUpload)
        let needsFollowUpUpload = session.pendingUploadAfterCurrent
            || changedDuringUpload
            || Self.localFileNeedsUpload(session: session)

        guard needsFollowUpUpload else { return }

        session.pendingUploadAfterCurrent = false
        sessions[sessionKey] = session
        await uploadIfNeeded(sessionKey: sessionKey)
    }

    private func postSyncNotification(for session: Session, success: Bool, message: String) {
        let notificationName: Notification.Name = success
            ? .porterRemoteEditSyncSucceeded
            : .porterRemoteEditSyncFailed
        NotificationCenter.default.post(
            name: notificationName,
            object: nil,
            userInfo: [
                "fileName": session.fileName,
                "message": message,
            ]
        )
    }

    private static func localFileNeedsUpload(session: Session) -> Bool {
        guard FileManager.default.fileExists(atPath: session.localURL.path) else { return false }
        let currentDate = fileModificationDate(at: session.localURL)
        if let last = session.lastSyncedModificationDate, let current = currentDate {
            return current > last
        }
        return currentDate != nil
    }

    private static func fileModificationAdvanced(from before: Date?, to after: Date?) -> Bool {
        guard let before, let after else {
            return before != after
        }
        return after > before
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

    private func endSession(sessionKey: String) {
        sessions[sessionKey]?.debouncedUploadTask?.cancel()
        sessions.removeValue(forKey: sessionKey)
        busySessionKeys.remove(sessionKey)
    }

    private static func canonicalRemotePath(_ remotePath: String) -> String {
        RemoteEditCache.canonicalCachePath(remotePath)
    }

    private static func remoteParentDirectory(of remoteFilePath: String) -> String {
        let segments = RemotePathCodec.split(remoteFilePath)
        guard segments.count > 1 else {
            return segments.first == "/" ? "/" : "~"
        }
        return RemotePathCodec.join(Array(segments.dropLast()))
    }

    private static func stagingLocations(host: String, remotePath: String, fileName: String) throws -> (directory: URL, file: URL) {
        let directory = try RemoteEditCache.stagingDirectoryURL(host: host, remotePath: remotePath)
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
