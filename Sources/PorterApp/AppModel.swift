import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var hosts: [SSHHost] = []
    @Published var selectedHostID: SSHHost.ID?
    @Published var defaultPaths: [String: String] = [:]
    @Published var isUploading = false
    @Published var isTestingConnection = false
    @Published var log = ""
    @Published private(set) var transientNotice: TransientNotice?

    private let defaultsKey = "hostDefaultPaths"
    private var transientNoticeDismissTask: Task<Void, Never>?

    var selectedHost: SSHHost? {
        hosts.first { $0.id == selectedHostID }
    }

    var isBusy: Bool { isUploading || isTestingConnection }

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
        guard !isBusy else { return }

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
        guard !isBusy else { return }
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

        isUploading = true
        log = "开始上传 \(fileURLs.count) 个项目到 \(host.name):\(remotePath)"

        let hostName = host.name
        Task.detached {
            let result = await Uploader.upload(
                fileURLs: fileURLs,
                host: hostName,
                remotePath: remotePath,
                conflictStrategy: conflictStrategy
            )
            await MainActor.run {
                self.isUploading = false
                self.log = result
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
