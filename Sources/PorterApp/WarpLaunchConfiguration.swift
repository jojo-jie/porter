import AppKit
import Foundation

/// Opens SSH in Warp via a Porter-owned Tab Config.
enum WarpLaunchConfiguration {
    private static let tabConfigFileName = "porter_connect.toml"
    private static let tabConfigName = "porter_connect"

    enum Outcome {
        case success(statusMessage: String)
        case failed(String)
    }

    @MainActor
    static func openSSHSession(command: String, hostLabel: String) async -> Outcome {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let target = preferredWarpTarget()
        let tabConfigURL = target.tabConfigDirectory(home: home)
            .appendingPathComponent(tabConfigFileName)

        do {
            try FileManager.default.createDirectory(
                at: tabConfigURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let toml = tabConfigTOML(command: command, hostLabel: hostLabel, homeDirectory: home.path)
            try toml.write(to: tabConfigURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: NSNumber(value: Int16(0o600))],
                ofItemAtPath: tabConfigURL.path
            )
        } catch {
            return .failed("无法写入 Warp Tab Config：\(error.localizedDescription)")
        }

        do {
            try cleanupLegacyDefaultTabConfigSettings(home: home)
        } catch {
            return .failed("已写入 Warp Tab Config，但无法清理旧的 Warp 默认标签页设置：\(error.localizedDescription)")
        }

        guard let url = URL(string: "\(target.urlScheme)://tab_config/\(tabConfigName)") else {
            return .failed("无法构造 Warp Tab Config URL。")
        }

        guard NSWorkspace.shared.open(url) else {
            return .failed("无法通过 Warp URL 打开 Porter Connect。请确认已安装 Warp，并允许 Warp URI Scheme。")
        }

        return .success(statusMessage: "已在 Warp 打开 SSH 会话，未修改 Warp 的默认新标签页设置。")
    }

    private static func tabConfigTOML(command: String, hostLabel: String, homeDirectory: String) -> String {
        let title = hostLabel.replacingOccurrences(of: "\"", with: "'")
        let directory = tomlBasicString(homeDirectory)
        let shellCommand = command.trimmingCharacters(in: .newlines)
        return """
        name = "Porter Connect"
        title = "\(title)"

        [[panes]]
        id = "main"
        type = "terminal"
        directory = \(directory)
        commands = [
        \(tomlMultilineLiteral(shellCommand)),
        ]
        """
    }

    private static func tomlMultilineLiteral(_ value: String) -> String {
        "'''\n\(value)\n'''"
    }

    private static func tomlBasicString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private static func preferredWarpTarget() -> WarpTarget {
        if WarpTarget.preview.isRunning {
            return .preview
        }
        if WarpTarget.stable.isRunning {
            return .stable
        }
        if WarpTarget.stable.isInstalled {
            return .stable
        }
        if WarpTarget.preview.isInstalled {
            return .preview
        }
        return .stable
    }

    private static func cleanupLegacyDefaultTabConfigSettings(home: URL) throws {
        for target in WarpTarget.allCases {
            try WarpSettingsCleaner.removePorterDefaultTabConfig(
                settingsURL: target.settingsURL(home: home),
                tabConfigFileName: tabConfigFileName
            )
        }
    }
}

private enum WarpTarget: CaseIterable {
    case stable
    case preview

    var urlScheme: String {
        switch self {
        case .stable: return "warp"
        case .preview: return "warppreview"
        }
    }

    private var bundleIdentifiers: [String] {
        switch self {
        case .stable:
            return ["dev.warp.Warp-Stable", "dev.warp.Warp"]
        case .preview:
            return ["dev.warp.Warp-Preview"]
        }
    }

    var isRunning: Bool {
        bundleIdentifiers.contains { bundleID in
            !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
        }
    }

    var isInstalled: Bool {
        bundleIdentifiers.contains { bundleID in
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
        }
    }

    func tabConfigDirectory(home: URL) -> URL {
        switch self {
        case .stable:
            return home.appendingPathComponent(".warp/tab_configs", isDirectory: true)
        case .preview:
            return home.appendingPathComponent(".warp-preview/tab_configs", isDirectory: true)
        }
    }

    func settingsURL(home: URL) -> URL {
        switch self {
        case .stable:
            return home.appendingPathComponent(".warp/settings.toml")
        case .preview:
            return home.appendingPathComponent(".warp-preview/settings.toml")
        }
    }
}

private enum WarpSettingsCleaner {
    static func removePorterDefaultTabConfig(settingsURL: URL, tabConfigFileName: String) throws {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return }

        let original = try String(contentsOf: settingsURL, encoding: .utf8)
        var lines = original.components(separatedBy: .newlines)
        let generalRange = generalSectionRange(in: lines)
        guard let defaultConfigIndex = lines[generalRange].firstIndex(where: { line in
            isAssignment(line, key: "default_tab_config_path") && line.contains(tabConfigFileName)
        }) else {
            return
        }

        lines.remove(at: defaultConfigIndex)
        let updatedGeneralRange = generalSectionRange(in: lines)
        if let modeIndex = lines[updatedGeneralRange].firstIndex(where: { line in
            isAssignment(line, key: "default_session_mode") && line.contains("tab_config")
        }) {
            lines.remove(at: modeIndex)
        }

        let updated = lines.joined(separator: "\n")
        if updated != original {
            try updated.write(to: settingsURL, atomically: true, encoding: .utf8)
        }
    }

    private static func generalSectionRange(in lines: [String]) -> Range<Int> {
        guard let generalIndex = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "[general]" }) else {
            return 0..<0
        }
        let start = generalIndex + 1
        if start >= lines.endIndex {
            return start..<start
        }
        let end = lines[start...].firstIndex(where: {
            let trimmed = $0.trimmingCharacters(in: .whitespaces)
            return trimmed.hasPrefix("[") && trimmed.hasSuffix("]")
        }) ?? lines.count
        return start..<end
    }

    private static func isAssignment(_ line: String, key: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("#") || trimmed.hasPrefix("//") {
            return false
        }
        guard trimmed.hasPrefix(key) else { return false }
        let suffix = trimmed.dropFirst(key.count).trimmingCharacters(in: .whitespaces)
        return suffix.hasPrefix("=")
    }
}
