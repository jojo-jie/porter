import Foundation
import PorterCore
import SwiftUI

struct UploadProgressSnapshot: Equatable {
    enum Phase: Equatable {
        case preparing
        case uploading
    }

    let phase: Phase
    let completedCount: Int
    let totalCount: Int
    let detail: String?

    var statusText: String {
        switch phase {
        case .preparing:
            if totalCount <= 1 {
                return "正在准备上传…"
            }
            return "正在准备上传（\(completedCount)/\(totalCount)）…"
        case .uploading:
            if totalCount <= 1 {
                return "正在通过 SFTP 上传…"
            }
            if let detail, !detail.isEmpty {
                return "正在上传（\(totalCount) 项）：\(detail)"
            }
            return "正在通过 SFTP 上传 \(totalCount) 项…"
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var hosts: [SSHHost] = []
    @Published var selectedHostID: SSHHost.ID?
    @Published var defaultPaths: [String: String] = [:]
    @Published var isUploading = false
    @Published var isTestingConnection = false
    @Published var uploadProgress: UploadProgressSnapshot?
    @Published var log = ""
    @Published private(set) var transientNotice: TransientNotice?

    private let defaultsKey = "hostDefaultPaths"
    private var transientNoticeDismissTask: Task<Void, Never>?
    private var uploadCancellation: PorterSubprocessCancellation?

    var selectedHost: SSHHost? {
        hosts.first { $0.id == selectedHostID }
    }

    init() {
        loadDefaultPaths()
    }

    func refreshHosts(using config: SSHConfigPreferencesStore) {
        if let issue = SSHConfigPathResolver.validationIssue(forConfigPath: config.configPath) {
            hosts = []
            selectedHostID = nil
            log = issue
            return
        }

        hosts = SSHConfigParser.loadHosts(configURL: config.resolvedConfigURL)
        if selectedHostID == nil || !hosts.contains(where: { $0.id == selectedHostID }) {
            selectedHostID = hosts.first?.id
        }
        if hosts.isEmpty {
            if config.configFileExists {
                log = "未在 \(config.displayPath) 中找到可展示的 Host alias。"
            } else {
                log = "找不到 SSH 配置文件：\(config.displayPath)"
            }
        }
    }

    func testConnection() {
        guard let host = selectedHost else {
            presentTransientNotice("请先选择主机。", kind: .error)
            return
        }
        guard !isTestingConnection else { return }

        isTestingConnection = true

        let hostName = host.name
        Task.detached {
            let result = await ConnectionPreflight.test(hostAlias: hostName)
            await MainActor.run {
                self.isTestingConnection = false
                self.presentTransientNotice(result, kind: TransientNotice.kind(forConnectionTestResult: result))
            }
        }
    }

    func cancelUpload() {
        uploadCancellation?.cancel()
    }

    func presentTransientNotice(_ message: String, kind: TransientNotice.Kind, duration: Duration = .seconds(2)) {
        transientNoticeDismissTask?.cancel()
        let notice = TransientNotice(message: message, kind: kind)
        withAnimation(.easeOut(duration: 0.2)) {
            transientNotice = notice
        }
        transientNoticeDismissTask = Task { @MainActor in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled, transientNotice?.id == notice.id else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                transientNotice = nil
            }
        }
    }

    func pathBinding(for host: SSHHost) -> Binding<String> {
        Binding(
            get: { self.defaultPaths[host.id, default: ""] },
            set: { newValue in
                self.defaultPaths[host.id] = newValue
                self.saveDefaultPaths()
            }
        )
    }

    func upload(urls: [URL], conflictStrategy: UploadConflictStrategy) {
        guard let host = selectedHost else {
            log = "请先选择主机。"
            return
        }
        guard !isUploading else { return }
        let remotePath = defaultPaths[host.id, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !remotePath.isEmpty else {
            log = "请先为 \(host.name) 设置默认远程目录。"
            return
        }
        let fileURLs = urls.filter(\.isFileURL)
        guard !fileURLs.isEmpty else {
            log = "没有可上传的本地文件。"
            return
        }

        let cancellation = PorterSubprocessCancellation()
        uploadCancellation = cancellation
        isUploading = true
        uploadProgress = UploadProgressSnapshot(phase: .preparing, completedCount: 0, totalCount: fileURLs.count, detail: nil)
        log = "开始上传 \(fileURLs.count) 个项目到 \(host.name):\(remotePath)"

        let hostName = host.name
        Task.detached {
            let result = await Uploader.upload(
                fileURLs: fileURLs,
                host: hostName,
                remotePath: remotePath,
                conflictStrategy: conflictStrategy,
                cancellation: cancellation
            ) { update in
                Task { @MainActor in
                    guard self.isUploading else { return }
                    self.uploadProgress = UploadProgressSnapshot(
                        phase: update.phase == .preparing ? .preparing : .uploading,
                        completedCount: update.completedCount,
                        totalCount: update.totalCount,
                        detail: update.detail
                    )
                }
            }

            await MainActor.run {
                self.isUploading = false
                self.uploadProgress = nil
                self.uploadCancellation = nil
                if result.wasCancelled {
                    self.log = "上传已取消。"
                } else {
                    self.log = result.message
                }
            }
        }
    }

    private func loadDefaultPaths() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data)
        else {
            return
        }
        defaultPaths = decoded
    }

    private func saveDefaultPaths() {
        guard let data = try? JSONEncoder().encode(defaultPaths) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}
