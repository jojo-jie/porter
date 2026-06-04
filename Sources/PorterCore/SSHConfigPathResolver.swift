import Foundation

public enum SSHConfigPathResolver {
    public static let defaultConfigPath = "~/.ssh/config"

    public static func expandTilde(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return expandTilde(defaultConfigPath) }
        if trimmed == "~" {
            return FileManager.default.homeDirectoryForCurrentUser.path
        }
        if trimmed.hasPrefix("~/") {
            return FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(String(trimmed.dropFirst(2))).path
        }
        return trimmed
    }

    public static func resolvedFileURL(forConfigPath path: String) -> URL {
        URL(fileURLWithPath: expandTilde(path), isDirectory: false)
    }

    /// Rejects paths that could break parsing or mislead the file picker.
    public static func validationIssue(forConfigPath path: String) -> String? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "路径不能为空。" }
        if trimmed.contains("\n") || trimmed.contains("\r") { return "路径不能包含换行。" }
        return nil
    }
}
