import AppKit
import SwiftUI

enum AppAppearanceMode: String, CaseIterable, Identifiable {
    case light
    case dark
    case system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light: return "浅色"
        case .dark: return "深色"
        case .system: return "系统"
        }
    }

    var symbolName: String {
        switch self {
        case .light: return "sun.max"
        case .dark: return "moon"
        case .system: return "macbook"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        case .system: return nil
        }
    }
}

@MainActor
final class AppearanceSettingsStore: ObservableObject {
    private let defaultsKey = "porter.appearanceMode"

    @Published var mode: AppAppearanceMode {
        didSet {
            UserDefaults.standard.set(mode.rawValue, forKey: defaultsKey)
            apply()
        }
    }

    init() {
        let rawValue = UserDefaults.standard.string(forKey: defaultsKey)
        mode = rawValue.flatMap(AppAppearanceMode.init(rawValue:)) ?? .system
        apply()
    }

    private func apply() {
        let appearance = mode.nsAppearance
        NSApplication.shared.appearance = appearance
        NSApplication.shared.windows.forEach { window in
            window.appearance = appearance
        }
    }
}

/// 主窗口「打开终端」时使用的终端应用。
enum ExternalTerminalApp: String, CaseIterable, Identifiable {
    case appleTerminal
    case warp
    case iterm2

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appleTerminal: return "系统自带终端 (Terminal.app)"
        case .warp: return "Warp"
        case .iterm2: return "iTerm2"
        }
    }

    var subtitle: String {
        switch self {
        case .appleTerminal:
            return "使用 macOS 自带的「终端」新建窗口并执行 SSH，登录后进入该主机在主窗口配置的默认远程目录。"
        case .warp:
            return "更新 Warp「Porter Connect」并模拟 ⌘T 打开（与手动一致）。需在「隐私与安全性 → 辅助功能/输入监控」中允许 Porter。"
        case .iterm2:
            return "在 iTerm2 的新标签页中直接执行 SSH，并进入该主机在主窗口配置的默认远程目录。"
        }
    }

    var symbolName: String {
        switch self {
        case .appleTerminal: return "apple.terminal"
        case .warp: return "command.circle.fill"
        case .iterm2: return "terminal.fill"
        }
    }
}

@MainActor
final class TerminalPreferencesStore: ObservableObject {
    private let defaultsKey = "porter.externalTerminalApp"

    @Published var selectedApp: ExternalTerminalApp {
        didSet {
            UserDefaults.standard.set(selectedApp.rawValue, forKey: defaultsKey)
        }
    }

    init() {
        let raw = UserDefaults.standard.string(forKey: defaultsKey)
        selectedApp = raw.flatMap(ExternalTerminalApp.init(rawValue:)) ?? .appleTerminal
    }
}

enum SettingsSection: String, CaseIterable, Identifiable {
    case appearance
    case transfer
    case terminal
    case configuration

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appearance: return "外观"
        case .transfer: return "传输"
        case .terminal: return "终端"
        case .configuration: return "配置"
        }
    }

    var subtitle: String {
        switch self {
        case .appearance: return "调整 Porter 的主题外观。"
        case .transfer: return "上传时若远端已有同名文件或目录时的处理方式。"
        case .terminal: return "选择在主窗口点击「打开终端」时使用的终端应用。"
        case .configuration: return "OpenSSH 配置、本机默认下载目录与远程编辑缓存；每台主机的远端目录仍在主窗口设置。"
        }
    }

    var symbolName: String {
        switch self {
        case .appearance: return "sun.max"
        case .transfer: return "arrow.up.arrow.down"
        case .terminal: return "terminal"
        case .configuration: return "gearshape"
        }
    }
}
