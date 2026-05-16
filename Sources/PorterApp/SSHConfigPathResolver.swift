import Foundation

enum SSHConfigPathResolver {
    static let defaultConfigPath = "~/.ssh/config"

    static func expandTilde(_ path: String) -> String {
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

    static func resolvedFileURL(forConfigPath path: String) -> URL {
        URL(fileURLWithPath: expandTilde(path), isDirectory: false)
    }

    /// Rejects paths that could break parsing or mislead the file picker.
    static func validationIssue(forConfigPath path: String) -> String? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "路径不能为空。" }
        if trimmed.contains("\n") || trimmed.contains("\r") { return "路径不能包含换行。" }
        return nil
    }
}
