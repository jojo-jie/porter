import Foundation

public enum RemoteShellPath {
    public static func changeDirectoryCommand(for path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.isEmpty ? "~" : trimmed
        if normalized == "~" || normalized == "~/" {
            return "cd \"$HOME\""
        }
        if normalized.hasPrefix("~/") {
            let tail = String(normalized.dropFirst(2))
            return "cd \"$HOME\"/\(remoteSingleQuoted(tail))"
        }
        if normalized.hasPrefix("-") {
            return "cd ./\(remoteSingleQuoted(normalized))"
        }
        return "cd \(remoteSingleQuoted(normalized))"
    }

    /// POSIX `sh` snippet: rename/move with safely quoted full paths (`mv -- src dst`).
    ///
    /// Paths are single-quoted per ``remoteSingleQuoted(_:)`` (no unescaped user interpolation). For cross-host safety,
    /// validate basename segments with ``RemoteFileNameValidation`` before building paths.
    public static func moveItemShellCommand(from oldPath: String, to newPath: String) -> String {
        "mv -- \(remoteSingleQuoted(oldPath)) \(remoteSingleQuoted(newPath))"
    }

    /// POSIX `sh` snippet: remove a file/symlink (`rm -f`) or directory tree (`rm -rf`), with safely quoted path.
    public static func removeItemShellCommand(path: String, recursive: Bool) -> String {
        if recursive {
            return "rm -rf -- \(remoteSingleQuoted(path))"
        }
        return "rm -f -- \(remoteSingleQuoted(path))"
    }

    static func remoteSingleQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }
}

/// Local shell command to start an interactive remote shell after a safe ``RemoteShellPath`` `cd`.
///
/// The remote side runs `bash -lc "$(printf %s … | base64 -d)"` so the payload can contain single quotes from
/// ``RemoteShellPath/changeDirectoryCommand(for:)`` without nested quoting issues. Using a pipe into `bash` stdin
/// causes `exec bash` to exit immediately when SSH closes the pipe. Requires `base64` and `bash` on the server.
public enum PorterSSHInteractiveCommand {
    public static func localShellInvocation(hostAlias: String, remotePath: String) -> String {
        let trimmed = remotePath.trimmingCharacters(in: .whitespacesAndNewlines)
        let cdLine = RemoteShellPath.changeDirectoryCommand(for: trimmed)
        let innerShell = cdLine + " && exec bash -i"
        guard let data = innerShell.data(using: .utf8) else {
            return "ssh -t -- \(posixSingleQuoted(hostAlias))"
        }
        let encoded = data.base64EncodedString()
        let remoteCommand = "bash -lc \"$(printf %s \(posixSingleQuoted(encoded)) | base64 -d)\""
        return "ssh -t -- \(posixSingleQuoted(hostAlias)) \(posixSingleQuoted(remoteCommand))"
    }

    private static func posixSingleQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

public enum RemotePathCodec {
    public static func split(_ raw: String) -> [String] {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return ["~"] }
        if t == "/" { return ["/"] }
        if t == "~" || t == "~/" { return ["~"] }
        if t.hasPrefix("~/") {
            let tail = String(t.dropFirst(2))
            let body = tail.split(separator: "/").map(String.init).filter { !$0.isEmpty }
            return ["~"] + body
        }
        if t.hasPrefix("/") {
            let tail = String(t.dropFirst())
            let body = tail.split(separator: "/").map(String.init).filter { !$0.isEmpty }
            return ["/"] + body
        }
        let body = t.split(separator: "/").map(String.init).filter { !$0.isEmpty }
        return body.isEmpty ? ["~"] : body
    }

    public static func join(_ segments: [String]) -> String {
        guard let first = segments.first else { return "~" }
        if first == "~" {
            if segments.count == 1 { return "~" }
            return "~/" + segments.dropFirst().joined(separator: "/")
        }
        if first == "/" {
            if segments.count == 1 { return "/" }
            return "/" + segments.dropFirst().joined(separator: "/")
        }
        return segments.joined(separator: "/")
    }

    /// Parent breadcrumb segments, or nil if already at filesystem root-ish stop.
    public static func parent(of segments: [String]) -> [String]? {
        guard segments.count > 1 else { return nil }
        return Array(segments.dropLast())
    }

    /// Append a path component produced by listing (already unescaped plain name).
    public static func appendComponent(_ segments: [String], _ name: String) -> [String] {
        var next = segments
        next.append(name)
        return next
    }

    /// Remote path after uploading `name` into `directory` (e.g. `~/uploads` + `readme.txt`).
    public static func childPath(in directory: String, name: String) -> String {
        join(appendComponent(split(directory), name))
    }
}

extension RemoteShellPath {
    /// POSIX `test -e` for a remote path, with the same `~` / quoting rules as ``changeDirectoryCommand(for:)``.
    public static func itemExistsTestLine(for path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.isEmpty ? "~" : trimmed
        if normalized == "~" || normalized == "~/" {
            return "test -e -- \"$HOME\""
        }
        if normalized.hasPrefix("~/") {
            let tail = String(normalized.dropFirst(2))
            return "test -e -- \"$HOME\"/\(remoteSingleQuoted(tail))"
        }
        if normalized.hasPrefix("-") {
            return "test -e -- ./\(remoteSingleQuoted(normalized))"
        }
        return "test -e -- \(remoteSingleQuoted(normalized))"
    }
}
