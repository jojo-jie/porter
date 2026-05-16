import Darwin
import Foundation

enum SSHConfigParser {
    static func loadHosts(configURL: URL? = nil) -> [SSHHost] {
        let url = configURL ?? SSHConfigPathResolver.resolvedFileURL(forConfigPath: SSHConfigPathResolver.defaultConfigPath)
        var visited = Set<URL>()
        let lines = readLines(from: url, visited: &visited)
        return parse(lines: lines)
    }

    private static func readLines(from url: URL, visited: inout Set<URL>) -> [String] {
        let standardizedURL = url.standardizedFileURL
        guard visited.insert(standardizedURL).inserted,
              let content = try? String(contentsOf: standardizedURL, encoding: .utf8)
        else {
            return []
        }

        let baseDirectory = standardizedURL.deletingLastPathComponent()
        var result: [String] = []

        for rawLine in content.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            let parts = splitDirective(line)
            if parts.keyword.lowercased() == "include", let value = parts.value {
                for includeURL in expandInclude(value, relativeTo: baseDirectory) {
                    result.append(contentsOf: readLines(from: includeURL, visited: &visited))
                }
            } else {
                result.append(rawLine)
            }
        }

        return result
    }

    private static func parse(lines: [String]) -> [SSHHost] {
        var hosts: [SSHHost] = []
        var activeNames: [String] = []
        var activeValues: [String: String] = [:]

        func flush() {
            guard !activeNames.isEmpty else { return }
            for name in activeNames where isConcreteHostAlias(name) {
                hosts.append(
                    SSHHost(
                        name: name,
                        hostName: activeValues["hostname"],
                        user: activeValues["user"],
                        port: activeValues["port"]
                    )
                )
            }
        }

        for rawLine in lines {
            let withoutComment = stripComment(rawLine).trimmingCharacters(in: .whitespaces)
            guard !withoutComment.isEmpty else { continue }

            let directive = splitDirective(withoutComment)
            let keyword = directive.keyword.lowercased()
            guard let value = directive.value else { continue }

            if keyword == "host" {
                flush()
                activeNames = value.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                activeValues = [:]
            } else if !activeNames.isEmpty, ["hostname", "user", "port"].contains(keyword) {
                activeValues[keyword] = value
            }
        }

        flush()
        return Array(Dictionary(grouping: hosts, by: \.name).compactMap { $0.value.first })
            .filter { isScpSuitableRemoteHost($0) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// 排除 Git / 代码托管等「SSH 到其服务」的入口；这类配置不适合作为 scp 上传目标。
    private static func isScpSuitableRemoteHost(_ host: SSHHost) -> Bool {
        let blockedCodeHostingDomains = [
            "github.com", "gist.github.com", "gitlab.com", "gitlab.io",
            "bitbucket.org", "ssh.dev.azure.com", "vs-ssh.visualstudio.com",
            "gitee.com", "codeberg.org", "git.sr.ht", "pagure.io"
        ]
        func norm(_ s: String) -> String {
            s.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        }
        func matchesCodeHostingDomain(_ value: String) -> Bool {
            let normalized = norm(value)
            return blockedCodeHostingDomains.contains { domain in
                normalized == domain || normalized.hasSuffix(".\(domain)")
            }
        }
        if matchesCodeHostingDomain(host.name) { return false }
        if let hn = host.hostName, matchesCodeHostingDomain(hn) { return false }
        return true
    }

    private static func stripComment(_ line: String) -> String {
        var isQuoted = false
        var escaped = false
        var output = ""

        for character in line {
            if escaped {
                output.append(character)
                escaped = false
                continue
            }
            if character == "\\" {
                output.append(character)
                escaped = true
                continue
            }
            if character == "\"" {
                output.append(character)
                isQuoted.toggle()
                continue
            }
            if character == "#", !isQuoted {
                break
            }
            output.append(character)
        }

        return output
    }

    private static func splitDirective(_ line: String) -> (keyword: String, value: String?) {
        let trimmed = stripComment(line).trimmingCharacters(in: .whitespaces)
        guard let separator = trimmed.firstIndex(where: { $0.isWhitespace || $0 == "=" }) else {
            return (trimmed, nil)
        }
        let keyword = String(trimmed[..<separator])
        let valueStart = trimmed.index(after: separator)
        let value = String(trimmed[valueStart...])
            .trimmingCharacters(in: CharacterSet(charactersIn: " =\t"))
        return (keyword, value.isEmpty ? nil : value)
    }

    private static func isConcreteHostAlias(_ name: String) -> Bool {
        !name.contains("*") && !name.contains("?") && !name.hasPrefix("!")
    }

    private static func expandInclude(_ pattern: String, relativeTo baseDirectory: URL) -> [URL] {
        let expandedPattern = expandTilde(pattern)
        let absolutePattern: String
        if expandedPattern.hasPrefix("/") {
            absolutePattern = expandedPattern
        } else {
            absolutePattern = baseDirectory.appendingPathComponent(expandedPattern).path
        }

        let matches = glob(absolutePattern)
        if matches.isEmpty {
            return [URL(fileURLWithPath: absolutePattern)]
        }
        return matches.map { URL(fileURLWithPath: $0) }
    }

    private static func expandTilde(_ path: String) -> String {
        SSHConfigPathResolver.expandTilde(path)
    }

    private static func glob(_ pattern: String) -> [String] {
        var globResult = glob_t()
        defer { globfree(&globResult) }

        guard Darwin.glob(pattern, 0, nil, &globResult) == 0,
              let paths = globResult.gl_pathv
        else {
            return []
        }

        return (0..<Int(globResult.gl_matchc)).compactMap { index in
            guard let path = paths[index] else { return nil }
            return String(cString: path)
        }
    }
}
