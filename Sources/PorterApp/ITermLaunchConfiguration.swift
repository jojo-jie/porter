import AppKit
import Foundation

/// Opens SSH in iTerm2 via AppleScript (`com.googlecode.iterm2`).
enum ITermLaunchConfiguration {
    private static let bundleIdentifier = "com.googlecode.iterm2"

    enum Outcome {
        case success
        case failed(String)
    }

    @MainActor
    static func openSSHSession(command: String) -> Outcome {
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil else {
            return .failed("未检测到 iTerm2。请安装后重试。")
        }

        let quotedCommand = appleScriptQuoted(command)
        let script = """
        tell application id "\(bundleIdentifier)"
            activate
            if (count of windows) = 0 then
                create window with default profile command \(quotedCommand)
            else
                tell current window
                    create tab with default profile command \(quotedCommand)
                end tell
            end if
        end tell
        """

        var errorInfo: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let message = errorInfo[NSAppleScript.errorMessage] as? String
                ?? "请检查是否已安装 iTerm2，并在「系统设置 → 隐私与安全性 → 自动化」中允许 Porter 控制 iTerm2。"
            return .failed(message)
        }
        return .success
    }

    private static func appleScriptQuoted(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
    }
}
