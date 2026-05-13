import AppKit
import SwiftUI

@main
struct PorterApp: App {
    @StateObject private var appearanceSettings = AppearanceSettingsStore()

    init() {
        // 从 swift run / 终端直接启动裸可执行文件时，默认可能不注册为“普通应用”，
        // 导致 Dock 与 ⌘+Tab 中不可见；显式设为 regular 并随后台激活到前台。
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appearanceSettings)
                .onAppear {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1120, height: 720)
        .commands {
            PorterSettingsCommands()
        }
    }
}

private struct PorterSettingsCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings...") {
                NotificationCenter.default.post(name: .porterShowSettings, object: nil)
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut(",", modifiers: .command)
        }
    }
}

extension Notification.Name {
    static let porterShowSettings = Notification.Name("porter.showSettings")
}
