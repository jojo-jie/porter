import AppKit
import ApplicationServices
import Carbon.HIToolbox
import CoreGraphics
import Foundation

/// Opens SSH in Warp via Tab Config (`type = "terminal"`).
///
/// `warp://action/new_tab` does not honor `default_session_mode = tab_config` (unlike ⌘T).
/// After updating config we simulate ⌘T so behavior matches the Warp UI.
enum WarpLaunchConfiguration {
    private static let tabConfigFileName = "porter_connect.toml"

    enum Outcome {
        case success(statusMessage: String)
        case failed(String)
    }

    @MainActor
    static func openSSHSession(command: String, hostLabel: String) async -> Outcome {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let tabConfigURL = home
            .appendingPathComponent(".warp/tab_configs", isDirectory: true)
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

        let settingsURL = home.appendingPathComponent(".warp/settings.toml")
        let snapshot: WarpSettingsSnapshot
        do {
            snapshot = try WarpSettingsPatcher.applyTabConfigLaunch(
                settingsURL: settingsURL,
                tabConfigPath: tabConfigURL.path
            )
        } catch {
            return .failed("无法更新 Warp 设置：\(error.localizedDescription)")
        }

        try? await Task.sleep(for: .milliseconds(500))
        activateWarp()
        try? await Task.sleep(for: .milliseconds(200))

        let sentShortcut = sendCommandTToFrontmostApp()
        scheduleSettingsRestore(snapshot: snapshot, settingsURL: settingsURL, delaySeconds: 45)

        if sentShortcut {
            return .success(statusMessage: "已在 Warp 打开 SSH 会话。")
        }

        promptForInputMonitoringPermission()
        return .success(
            statusMessage: """
            已更新 Warp「Porter Connect」。请允许 Porter 的辅助功能/输入监控后重试，或手动按 ⌘T。
            （系统设置 → 隐私与安全性 → 辅助功能 / 输入监控）
            """
        )
    }

    /// Posts ⌘T to the active app (Warp should be frontmost). Requires Input Monitoring or Accessibility trust.
    private static func sendCommandTToFrontmostApp() -> Bool {
        guard AXIsProcessTrusted() else { return false }

        let source = CGEventSource(stateID: .combinedSessionState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_T), keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_T), keyDown: false)
        guard let keyDown, let keyUp else { return false }

        keyDown.flags = CGEventFlags.maskCommand
        keyUp.flags = CGEventFlags.maskCommand
        keyDown.post(tap: CGEventTapLocation.cgAnnotatedSessionEventTap)
        keyUp.post(tap: CGEventTapLocation.cgAnnotatedSessionEventTap)
        return true
    }

    private static func promptForInputMonitoringPermission() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private static let warpBundleIdentifiers = [
        "dev.warp.Warp-Stable",
        "dev.warp.Warp-Preview",
        "dev.warp.Warp",
    ]

    private static func activateWarp() {
        for bundleID in warpBundleIdentifiers {
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
                app.activate(options: [.activateAllWindows])
                return
            }
        }
        if let warpURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "dev.warp.Warp-Stable") {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: warpURL, configuration: config) { _, _ in }
            return
        }
        var errorInfo: NSDictionary?
        NSAppleScript(source: "tell application \"Warp\" to activate")?.executeAndReturnError(&errorInfo)
    }

    private static func scheduleSettingsRestore(
        snapshot: WarpSettingsSnapshot,
        settingsURL: URL,
        delaySeconds: TimeInterval
    ) {
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delaySeconds) {
            snapshot.restore(settingsURL: settingsURL)
        }
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
}

// MARK: - settings.toml patch

private struct WarpSettingsSnapshot {
    let originalContents: String

    func restore(settingsURL: URL) {
        try? originalContents.write(to: settingsURL, atomically: true, encoding: .utf8)
    }
}

private enum WarpSettingsPatcher {
    static func applyTabConfigLaunch(settingsURL: URL, tabConfigPath: String) throws -> WarpSettingsSnapshot {
        let original: String
        if FileManager.default.fileExists(atPath: settingsURL.path) {
            original = try String(contentsOf: settingsURL, encoding: .utf8)
        } else {
            original = """
            [general]
            default_session_mode = "agent"

            """
        }

        var lines = original.components(separatedBy: .newlines)
        if !lines.contains(where: { $0.trimmingCharacters(in: .whitespaces) == "[general]" }) {
            if let last = lines.last, !last.isEmpty {
                lines.append("")
            }
            lines.append("[general]")
        }
        upsertTomlAssignment(
            in: &lines,
            sectionRange: generalSectionRange(in: lines),
            key: "default_session_mode",
            value: #""tab_config""#
        )
        upsertTomlAssignment(
            in: &lines,
            sectionRange: generalSectionRange(in: lines),
            key: "default_tab_config_path",
            value: tomlQuotedPath(tabConfigPath)
        )

        let updated = lines.joined(separator: "\n")
        try updated.write(to: settingsURL, atomically: true, encoding: String.Encoding.utf8)
        return WarpSettingsSnapshot(originalContents: original)
    }

    private static func generalSectionRange(in lines: [String]) -> Range<Int> {
        guard let generalIndex = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "[general]" }) else {
            return 0..<0
        }
        let start = generalIndex + 1
        let end = lines[(generalIndex + 1)...].firstIndex(where: {
            let t = $0.trimmingCharacters(in: .whitespaces)
            return t.hasPrefix("[") && t.hasSuffix("]")
        }) ?? lines.count
        return start..<end
    }

    private static func upsertTomlAssignment(
        in lines: inout [String],
        sectionRange: Range<Int>,
        key: String,
        value: String
    ) {
        let assignment = "\(key) = \(value)"
        if let index = lines[sectionRange].firstIndex(where: { line in
            line.trimmingCharacters(in: .whitespaces).hasPrefix("\(key) =")
        }) {
            lines[index] = assignment
        } else {
            lines.insert(assignment, at: sectionRange.lowerBound)
        }
    }

    private static func tomlQuotedPath(_ path: String) -> String {
        let escaped = path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
