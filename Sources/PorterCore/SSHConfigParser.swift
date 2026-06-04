import Darwin
import Foundation

public enum SSHConfigParser {
    private struct Directive {
        let keyword: String
        let arguments: [String]
    }

    public static func loadHosts(configURL: URL? = nil) -> [SSHHost] {
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
            let directive = parseDirective(rawLine)
            if directive?.keyword.lowercased() == "include", let patterns = directive?.arguments {
                for pattern in patterns {
                    for includeURL in expandInclude(pattern, relativeTo: baseDirectory) {
                        result.append(contentsOf: readLines(from: includeURL, visited: &visited))
                    }
                }
            } else {
                result.append(rawLine)
            }
        }

        return result
    }

    private static func parseDirective(_ line: String) -> Directive? {
        let tokens = tokenize(line)
        guard let keyword = tokens.first else { return nil }
        let arguments = Array(tokens.dropFirst())
        guard !arguments.isEmpty else { return nil }
        return Directive(keyword: keyword, arguments: arguments)
    }

    private static func tokenize(_ line: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var tokenStarted = false
        var isQuoted = false
        var escaped = false

        func flush() {
            guard tokenStarted else { return }
            tokens.append(current)
            current = ""
            tokenStarted = false
        }

        for character in line {
            if escaped {
                current.append(character)
                tokenStarted = true
                escaped = false
                continue
            }
            if character == "\\" {
                escaped = true
                tokenStarted = true
                continue
            }
            if character == "\"" {
                isQuoted.toggle()
                tokenStarted = true
                continue
            }
            if character == "#", !isQuoted {
                break
            }
            if !isQuoted, character.isWhitespace || character == "=" {
                flush()
                continue
            }

            current.append(character)
            tokenStarted = true
        }

        if escaped {
            current.append("\\")
        }
        flush()
        return tokens
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
            guard let directive = parseDirective(rawLine) else { continue }
            let keyword = directive.keyword.lowercased()

            if keyword == "host" {
                flush()
                activeNames = directive.arguments
                activeValues = [:]
            } else if !activeNames.isEmpty, ["hostname", "user", "port"].contains(keyword) {
                activeValues[keyword] = directive.arguments.joined(separator: " ")
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
