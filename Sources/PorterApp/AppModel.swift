import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var hosts: [SSHHost] = []
    @Published var selectedHostID: SSHHost.ID?
    @Published var defaultPaths: [String: String] = [:]
    @Published var isUploading = false
    @Published var log = ""

    private let defaultsKey = "hostDefaultPaths"

    var selectedHost: SSHHost? {
        hosts.first { $0.id == selectedHostID }
    }

    init() {
        loadDefaultPaths()
        refreshHosts()
    }

    func refreshHosts() {
        hosts = SSHConfigParser.loadHosts()
        if selectedHostID == nil || !hosts.contains(where: { $0.id == selectedHostID }) {
            selectedHostID = hosts.first?.id
        }
        if hosts.isEmpty {
            log = "未在 ~/.ssh/config 中找到可展示的 Host alias。"
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

    func upload(urls: [URL]) {
        guard let host = selectedHost else {
            log = "请先选择主机。"
            return
        }
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

        Task.detached {
            let result = await Uploader.upload(fileURLs: fileURLs, host: host.name, remotePath: remotePath)
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
