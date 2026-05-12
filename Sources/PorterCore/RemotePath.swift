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

    static func remoteSingleQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
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
}
