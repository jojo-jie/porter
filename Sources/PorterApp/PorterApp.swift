import AppKit
import SwiftUI

@main
struct PorterApp: App {
    @StateObject private var appearanceSettings = AppearanceSettingsStore()
    @StateObject private var terminalPreferences = TerminalPreferencesStore()
    @StateObject private var uploadPreferences = UploadPreferencesStore()
    @StateObject private var downloadPreferences = DownloadPreferencesStore()
    @StateObject private var sshConfigPreferences = SSHConfigPreferencesStore()
    @StateObject private var remoteFileEditCoordinator = RemoteFileEditCoordinator()

    init() {
        // 从 swift run / 终端直接启动裸可执行文件时，默认可能不注册为“普通应用”，
        // 导致 Dock 与 ⌘+Tab 中不可见；显式设为 regular 并随后台激活到前台。
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appearanceSettings)
                .environmentObject(terminalPreferences)
                .environmentObject(uploadPreferences)
                .environmentObject(downloadPreferences)
                .environmentObject(sshConfigPreferences)
                .environmentObject(remoteFileEditCoordinator)
                .onAppear {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1120, height: 760)
        .commands {
            PorterAppCommands()
        }
    }
}

private struct PorterAppCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("关于 Porter") {
                PorterAboutPanel.show()
            }
        }

        CommandGroup(replacing: .appSettings) {
            Button("设置...") {
                NotificationCenter.default.post(name: .porterShowSettings, object: nil)
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut(",", modifiers: .command)
        }

        CommandMenu("操作") {
            Button("选择文件上传…") {
                post(.porterUploadFiles)
            }
            .keyboardShortcut("u", modifiers: .command)

            Button("刷新主机列表") {
                post(.porterRefreshHosts)
            }
            .keyboardShortcut("r", modifiers: .command)

            Button("远端目录浏览") {
                post(.porterBrowseRemote)
            }
            .keyboardShortcut("b", modifiers: .command)

            Divider()

            Button("上一台主机") {
                post(.porterSelectPreviousHost)
            }
            .keyboardShortcut(.upArrow, modifiers: [])

            Button("下一台主机") {
                post(.porterSelectNextHost)
            }
            .keyboardShortcut(.downArrow, modifiers: [])
        }
    }

    private func post(_ name: Notification.Name) {
        NotificationCenter.default.post(name: name, object: nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

private enum PorterAboutPanel {
    @MainActor
    static func show() {
        let info = Bundle.main.infoDictionary ?? [:]
        let name = info.nonEmptyString(for: "CFBundleDisplayName")
            ?? info.nonEmptyString(for: "CFBundleName")
            ?? "Porter"
        let version = info.nonEmptyString(for: "CFBundleShortVersionString") ?? "1.0.0"
        let build = info.nonEmptyString(for: "CFBundleVersion") ?? "开发版"

        NSApplication.shared.orderFrontStandardAboutPanel(options: [
            .applicationName: name,
            .applicationVersion: version,
            .version: "构建 \(build)"
        ])
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

private extension Dictionary where Key == String, Value == Any {
    func nonEmptyString(for key: String) -> String? {
        guard let value = self[key] as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension Notification.Name {
    static let porterShowSettings = Notification.Name("porter.showSettings")
    static let porterUploadFiles = Notification.Name("porter.uploadFiles")
    static let porterRefreshHosts = Notification.Name("porter.refreshHosts")
    static let porterBrowseRemote = Notification.Name("porter.browseRemote")
    static let porterSelectPreviousHost = Notification.Name("porter.selectPreviousHost")
    static let porterSelectNextHost = Notification.Name("porter.selectNextHost")
    static let porterSSHConfigPathChanged = Notification.Name("porter.sshConfigPathChanged")
}
