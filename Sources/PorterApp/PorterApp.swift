import AppKit
import SwiftUI

@main
struct PorterApp: App {
    init() {
        // 从 swift run / 终端直接启动裸可执行文件时，默认可能不注册为“普通应用”，
        // 导致 Dock 与 ⌘+Tab 中不可见；显式设为 regular 并随后台激活到前台。
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1120, height: 720)
    }
}
