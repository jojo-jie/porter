import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Theme

extension Color {
    /// 暖色奶油画布：浅色取近似 #F8F7F2，深色用沉静的炭灰，避免标准白带来的冷感。
    static let porterCanvas = Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil
        return isDark
            ? NSColor(red: 0.118, green: 0.118, blue: 0.118, alpha: 1)
            : NSColor(red: 0.972, green: 0.969, blue: 0.949, alpha: 1)
    })

    /// 卡片/输入框表面：仅比画布高半档，靠对比关系而非阴影区分层次。
    static let porterSurface = Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil
        return isDark
            ? NSColor(red: 0.157, green: 0.157, blue: 0.157, alpha: 1)
            : NSColor(red: 1.0, green: 0.996, blue: 0.984, alpha: 1)
    })

    /// 1pt 发丝线，永远不喧宾夺主。
    static let porterBorder = Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil
        return isDark
            ? NSColor(white: 1.0, alpha: 0.10)
            : NSColor(white: 0.0, alpha: 0.09)
    })

    /// 单一暖橙强调色，对齐 Claude 标识色。
    static let porterAccent = Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil
        return isDark
            ? NSColor(red: 0.831, green: 0.490, blue: 0.376, alpha: 1)
            : NSColor(red: 0.800, green: 0.471, blue: 0.361, alpha: 1)
    })
}

struct SSHHost: Identifiable, Hashable {
    let name: String
    var hostName: String?
    var user: String?
    var port: String?

    var id: String { name }

    var subtitle: String {
        var connection = ""
        if let user, !user.isEmpty {
            connection += "\(user)@"
        }
        if let hostName, !hostName.isEmpty {
            connection += hostName
        }
        if let port, !port.isEmpty {
            connection += ":\(port)"
        }
        return connection.isEmpty ? "使用 ssh 配置中的默认连接参数" : connection
    }
}

enum SSHConfigParser {
    static func loadHosts() -> [SSHHost] {
        let configURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ssh/config")
        var visited = Set<URL>()
        let lines = readLines(from: configURL, visited: &visited)
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
        if path == "~" {
            return FileManager.default.homeDirectoryForCurrentUser.path
        }
        if path.hasPrefix("~/") {
            return FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(String(path.dropFirst(2))).path
        }
        return path
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

@MainActor
final class AppModel: ObservableObject {
    @Published var hosts: [SSHHost] = []
    @Published var selectedHostID: SSHHost.ID?
    @Published var defaultPaths: [String: String] = [:]
    @Published var isUploading = false
    @Published var log = "请选择一个主机，设置默认目录后即可上传文件。"

    private let defaultsKey = "hostDefaultPaths"

    var selectedHost: SSHHost? {
        hosts.first { $0.id == selectedHostID }
    }

    init() {
        loadDefaultPaths()
        refreshHosts()
    }

    func refreshHosts() {
        hosts = SSHConfigParser.loadHosts()
        if selectedHostID == nil || !hosts.contains(where: { $0.id == selectedHostID }) {
            selectedHostID = hosts.first?.id
        }
        if hosts.isEmpty {
            log = "未在 ~/.ssh/config 中找到可展示的 Host alias。"
        }
    }

    func pathBinding(for host: SSHHost) -> Binding<String> {
        Binding(
            get: { self.defaultPaths[host.id, default: ""] },
            set: { newValue in
                self.defaultPaths[host.id] = newValue
                self.saveDefaultPaths()
            }
        )
    }

    func upload(urls: [URL]) {
        guard let host = selectedHost else {
            log = "请先选择主机。"
            return
        }
        let remotePath = defaultPaths[host.id, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !remotePath.isEmpty else {
            log = "请先为 \(host.name) 设置默认远程目录。"
            return
        }
        let fileURLs = urls.filter(\.isFileURL)
        guard !fileURLs.isEmpty else {
            log = "没有可上传的本地文件。"
            return
        }

        isUploading = true
        log = "开始上传 \(fileURLs.count) 个项目到 \(host.name):\(remotePath)"

        Task.detached {
            let result = await Uploader.upload(fileURLs: fileURLs, host: host.name, remotePath: remotePath)
            await MainActor.run {
                self.isUploading = false
                self.log = result
            }
        }
    }

    private func loadDefaultPaths() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data)
        else {
            return
        }
        defaultPaths = decoded
    }

    private func saveDefaultPaths() {
        guard let data = try? JSONEncoder().encode(defaultPaths) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}

enum Uploader {
    static func upload(fileURLs: [URL], host: String, remotePath: String) async -> String {
        var output: [String] = []
        var failures: [String] = []

        for fileURL in fileURLs {
            let result = runSCP(fileURL: fileURL, host: host, remotePath: remotePath)
            output.append(result.output)
            if result.exitCode != 0 {
                failures.append(fileURL.lastPathComponent)
            }
        }

        if failures.isEmpty {
            return "上传完成：\(fileURLs.map(\.lastPathComponent).joined(separator: ", "))"
        }

        let detail = output.filter { !$0.isEmpty }.joined(separator: "\n")
        return "上传失败：\(failures.joined(separator: ", "))\n\(detail)"
    }

    private static func runSCP(fileURL: URL, host: String, remotePath: String) -> (exitCode: Int32, output: String) {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/scp")
        process.arguments = ["-r", fileURL.path, "\(host):\(remoteShellEscaped(remotePath))"]
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
        } catch {
            return (1, error.localizedDescription)
        }
    }

    private static func remoteShellEscaped(_ value: String) -> String {
        var escaped = ""
        for (index, character) in value.enumerated() {
            if index == 0, character == "~" {
                escaped.append(character)
            } else if "\\'\"$` !()[]{};&|<>*?".contains(character) {
                escaped.append("\\")
                escaped.append(character)
            } else {
                escaped.append(character)
            }
        }
        return escaped
    }
}

// MARK: - Remote directory browser (SSH + ls)

private enum RemoteSSH {
    /// Runs a non-interactive remote shell snippet; output is stdout+stderr merged.
    static func run(host: String, bash: String) -> (exitCode: Int32, output: String) {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = [
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=20",
            host,
            bash,
        ]
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8) ?? ""
            return (process.terminationStatus, text)
        } catch {
            return (127, error.localizedDescription)
        }
    }

    /// Shell single-quote for POSIX `sh` -c style snippets inside our ssh argument.
    static func remoteSingleQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }
}

private struct RemoteListingEntry: Identifiable, Hashable {
    var id: String { name }

    /// Synthetic `..` row for hierarchy navigation.
    static let parentDirectory = RemoteListingEntry(
        name: "..",
        permissions: "",
        modifiedDisplay: "—",
        sizeDisplay: "—",
        kindLabel: "",
        fileTypeMarker: "",
        isDirectory: true,
        navigable: true,
        sortKey: ""
    )

    let name: String
    let permissions: String
    let modifiedDisplay: String
    let sizeDisplay: String
    let kindLabel: String
    let fileTypeMarker: String
    let isDirectory: Bool
    var navigable: Bool
    /// ISO date `yyyy-MM-dd HH:mm` or raw tail for fallback sorting.
    let sortKey: String

    static func lsParse(lines: String) -> [RemoteListingEntry] {
        lines.split(separator: "\n", omittingEmptySubsequences: false).compactMap { rawLine -> RemoteListingEntry? in
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { return nil }
            if line.hasPrefix("total ") { return nil }

            guard let gnu = gnuLongIsoLine(from: line) else {
                return legacyWhitespaceLine(from: line)
            }
            return gnu
        }
    }

    private static func gnuLongIsoLine(from line: String) -> RemoteListingEntry? {
        let pattern = #"^([dl\-])([rwxsSt\-]{9}[+@\.]?)\s+\S+\s+\S+\s+\S+\s+(\d+)\s+(\d{4}-\d{2}-\d{2})\s+(\d{2}:\d{2})\s+(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let modeR = Range(match.range(at: 1), in: line),
              let permR = Range(match.range(at: 2), in: line),
              let sizeR = Range(match.range(at: 3), in: line),
              let dateR = Range(match.range(at: 4), in: line),
              let timeR = Range(match.range(at: 5), in: line),
              let nameR = Range(match.range(at: 6), in: line)
        else {
            return nil
        }

        let typeChar = String(line[modeR])
        let perm = "\(typeChar)\(String(line[permR]))"
        let size = String(line[sizeR])
        let datePart = String(line[dateR])
        let timePart = String(line[timeR])
        let nameField = String(line[nameR]).trimmingCharacters(in: .whitespaces)

        guard !nameField.isEmpty, nameField != ".", nameField != ".." else { return nil }

        let (displayName, isDir, navigable): (String, Bool, Bool) =
            switch typeChar {
            case "d":
                (nameField, true, true)
            case "l":
                navigableSymlink(displayName: nameField)
            default:
                (nameField, false, false)
            }

        let kind: String =
            switch typeChar {
            case "d": "文件夹"
            case "-": "文件"
            case "l": "符号链接"
            default: "其他"
            }

        return RemoteListingEntry(
            name: displayName,
            permissions: perm,
            modifiedDisplay: "\(datePart) \(timePart)",
            sizeDisplay: isDir ? "—" : RemoteByteCountFormatting.string(forBytes: UInt64(size) ?? 0),
            kindLabel: kind,
            fileTypeMarker: typeChar,
            isDirectory: isDir,
            navigable: navigable,
            sortKey: "\(datePart) \(timePart)"
        )
    }

    private static func navigableSymlink(displayName: String) -> (String, Bool, Bool) {
        let arrow = " -> "
        guard let splitRange = displayName.range(of: arrow) else {
            return (displayName, false, false)
        }
        let linkName = String(displayName[..<splitRange.lowerBound]).trimmingCharacters(in: .whitespaces)
        guard !linkName.isEmpty else { return (displayName, false, false) }
        return (linkName, false, false)
    }

    private static func legacyWhitespaceLine(from line: String) -> RemoteListingEntry? {
        let pieces = line.split(whereSeparator: \.isWhitespace).map(String.init)
        guard pieces.count >= 9 else { return nil }
        let mode = pieces[0]
        guard let typeChar = mode.first, "dl-".contains(typeChar) else { return nil }

        let name = pieces.dropFirst(8).joined(separator: " ")
        guard !name.isEmpty, name != ".", name != ".." else { return nil }

        let isDir = typeChar == "d"
        let month = pieces[5]
        let day = pieces[6]
        let timeOrYear = pieces[7]
        let modified = "\(month) \(day) \(timeOrYear)"
        let size = pieces[4]

        return RemoteListingEntry(
            name: name,
            permissions: mode,
            modifiedDisplay: modified,
            sizeDisplay: isDir ? "—" : RemoteByteCountFormatting.string(forBytes: UInt64(size) ?? 0),
            kindLabel: isDir ? "文件夹" : (typeChar == "l" ? "符号链接" : "文件"),
            fileTypeMarker: String(typeChar),
            isDirectory: isDir,
            navigable: isDir,
            sortKey: modified
        )
    }
}

private enum RemoteByteCountFormatting {
    static func string(forBytes bytes: UInt64) -> String {
        let formatter = Foundation.ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

private enum RemotePathCodec {
    static func split(_ raw: String) -> [String] {
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

    static func join(_ segments: [String]) -> String {
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
    static func parent(of segments: [String]) -> [String]? {
        guard segments.count > 1 else { return nil }
        return Array(segments.dropLast())
    }

    /// Append a path component produced by listing (already unescaped plain name).
    static func appendComponent(_ segments: [String], _ name: String) -> [String] {
        var next = segments
        next.append(name)
        return next
    }
}

@MainActor
private final class RemoteDirectoryBrowserModel: ObservableObject {
    let hostAlias: String

    @Published private(set) var segments: [String]
    @Published private(set) var entries: [RemoteListingEntry] = []
    @Published private(set) var resolvedPWD: String = ""
    @Published var isLoading = false
    @Published var errorMessage: String?

    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false

    private var pastSegments: [[String]] = []
    private var futureSegments: [[String]] = []

    var currentLogicalPath: String { RemotePathCodec.join(segments) }

    init(hostAlias: String, initialPath: String) {
        self.hostAlias = hostAlias
        self.segments = RemotePathCodec.split(initialPath)
    }

    func replacePathAndReload(_ newSegments: [String]) {
        pastSegments.append(segments)
        futureSegments.removeAll()
        segments = newSegments
        syncHistoryFlags()
        Task { await refreshList() }
    }

    func goBack() {
        guard let prev = pastSegments.popLast() else { return }
        futureSegments.insert(segments, at: 0)
        segments = prev
        Task { await refreshList() }
        syncHistoryFlags()
    }

    func goForward() {
        guard !futureSegments.isEmpty else { return }
        let next = futureSegments.removeFirst()
        pastSegments.append(segments)
        segments = next
        Task { await refreshList() }
        syncHistoryFlags()
    }

    func goToParent() {
        guard let parent = RemotePathCodec.parent(of: segments) else { return }
        replacePathAndReload(parent)
    }

    func openEntry(_ entry: RemoteListingEntry) {
        if entry.name == ".." {
            goToParent()
            return
        }
        guard entry.navigable, entry.isDirectory else { return }
        replacePathAndReload(RemotePathCodec.appendComponent(segments, entry.name))
    }

    func goToBreadcrumb(index: Int) {
        guard index >= 0, index < segments.count else { return }
        let prefix = Array(segments.prefix(index + 1))
        guard prefix != segments else { return }
        replacePathAndReload(prefix)
    }

    func refreshList() async {
        isLoading = true
        errorMessage = nil

        let host = hostAlias
        let path = RemotePathCodec.join(segments)
        let quoted = RemoteSSH.remoteSingleQuoted(path)
        let script = """
        set -e
        cd \(quoted)
        pwd
        printf '%s\\n' '___PORTER_LS_BEGIN___'
        LC_ALL=C ls -la --time-style=long-iso 2>/dev/null || LC_ALL=C ls -la
        """

        let (exitCode, output) = await Task.detached(priority: .userInitiated) {
            RemoteSSH.run(host: host, bash: script)
        }.value

        isLoading = false
        syncHistoryFlags()

        if exitCode != 0 {
            errorMessage = Self.humanReadableSSHFailure(exitCode: exitCode, output: output, attemptedPath: path)
            entries = []
            resolvedPWD = ""
            return
        }

        let sections = output.components(separatedBy: "\n___PORTER_LS_BEGIN___\n")
        guard sections.count == 2 else {
            errorMessage = "无法解析远端目录列表，请改用路径输入。"
            entries = []
            resolvedPWD = ""
            return
        }

        let pwd = sections[0].trimmingCharacters(in: .whitespacesAndNewlines)
        resolvedPWD = pwd

        var parsed = RemoteListingEntry.lsParse(lines: sections[1])
        parsed.sort { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory && !rhs.isDirectory
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }

        if RemotePathCodec.parent(of: segments) != nil {
            parsed.insert(.parentDirectory, at: 0)
        }
        entries = parsed
    }

    private func syncHistoryFlags() {
        canGoBack = !pastSegments.isEmpty
        canGoForward = !futureSegments.isEmpty
    }

    private static func sanitizedRemoteShellOutput(_ output: String) -> String {
        output
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0 != "___PORTER_ERR_CD" }
            .joined(separator: "\n")
    }

    private static func humanReadableSSHFailure(exitCode: Int32, output: String, attemptedPath: String) -> String {
        let tail = sanitizedRemoteShellOutput(output)
        if tail.isEmpty {
            return "SSH 执行失败（退出码 \(exitCode)）。请确认本机能用同一 Host 别名免交互登录远端，并检查路径「\(attemptedPath)」是否正确。"
        }

        let lines = tail.split(separator: "\n").map(String.init)
        if let line = lines.first(where: { $0.contains("No such file or directory") }) {
            return "无法进入「\(attemptedPath)」：远端路径不存在或拼写有误。\n\(line)"
        }
        if let line = lines.first(where: { $0.contains("Not a directory") }) {
            return "「\(attemptedPath)」不是文件夹，无法作为目录打开。\n\(line)"
        }
        if let line = lines.first(where: { $0.contains("Permission denied") }) {
            return "没有权限进入「\(attemptedPath)」。\n\(line)"
        }

        return "SSH 或远程 shell 出错（退出码 \(exitCode)）：\n\(tail)"
    }
}

private struct RemoteDirectoryBrowserSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var browser: RemoteDirectoryBrowserModel
    @Binding var boundPath: String

    @State private var selectedName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sheetHeader

            Rectangle()
                .fill(Color.porterBorder)
                .frame(height: 1)

            navigationBar
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.porterSurface.opacity(0.35))

            listingsTable
                .frame(minWidth: 560, minHeight: 320)

            Rectangle()
                .fill(Color.porterBorder)
                .frame(height: 1)

            footerBar
        }
        .frame(minWidth: 580, minHeight: 420)
        .background(Color.porterCanvas)
        .task {
            await browser.refreshList()
        }
    }

    private var sheetHeader: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("选择远程目录")
                    .font(.system(.headline).weight(.semibold))
                Text(browser.hostAlias)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var navigationBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 2) {
                Button {
                    browser.goBack()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.borderless)
                .disabled(!browser.canGoBack || browser.isLoading)
                .help("后退")

                Button {
                    browser.goForward()
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.borderless)
                .disabled(!browser.canGoForward || browser.isLoading)
                .help("前进")
            }
            .foregroundStyle(.primary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(Color.porterAccent)
                        .imageScale(.small)
                    ForEach(Array(browser.segments.enumerated()), id: \.offset) { index, segment in
                        if index > 0 {
                            Image(systemName: "chevron.compact.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        Button {
                            browser.goToBreadcrumb(index: index)
                        } label: {
                            Text(displaySegment(segment, isFirst: index == 0))
                                .font(.system(.subheadline, design: .monospaced))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(index == browser.segments.count - 1 ? Color.primary : Color.porterAccent)
                        .disabled(browser.isLoading)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func displaySegment(_ segment: String, isFirst: Bool) -> String {
        if isFirst, segment == "/" { return "/" }
        if isFirst, segment == "~" { return "~" }
        return segment
    }

    private var listingsTable: some View {
        ZStack {
            if let err = browser.errorMessage {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.orange.opacity(0.9))
                    Text(err)
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding(24)
            } else {
                List(selection: $selectedName) {
                    Section {
                        ForEach(browser.entries) { entry in
                            listingRow(entry)
                                .tag(entry.name as String?)
                        }
                    } header: {
                        tableHeaderRow
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }

            if browser.isLoading {
                ZStack {
                    Color.porterCanvas.opacity(0.45)
                    ProgressView()
                        .controlSize(.regular)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.porterSurface.opacity(0.45))
    }

    private var tableHeaderRow: some View {
        HStack(spacing: 0) {
            Text("名称")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("修改时间")
                .frame(width: 150, alignment: .leading)
            Text("大小")
                .frame(width: 88, alignment: .trailing)
            Text("类型")
                .frame(width: 72, alignment: .leading)
        }
        .font(.system(.caption2).weight(.semibold))
        .foregroundStyle(.tertiary)
        .textCase(nil)
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(Color.porterSurface.opacity(0.9))
    }

    private func listingRow(_ entry: RemoteListingEntry) -> some View {
        Button {
            selectedName = entry.name
            if entry.name == ".." {
                browser.goToParent()
            } else if entry.navigable, entry.isDirectory {
                browser.openEntry(entry)
            }
        } label: {
            HStack(spacing: 0) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: entry.name == ".." ? "arrow.turn.up.left" : (entry.isDirectory ? "folder.fill" : "doc"))
                        .foregroundStyle(entry.name == ".." ? Color.secondary : (entry.isDirectory ? Color.porterAccent : Color.secondary.opacity(0.85)))
                        .frame(width: 20, alignment: .center)
                        .imageScale(.medium)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.name)
                            .font(.system(.body, design: .default))
                            .foregroundStyle(entry.navigable || entry.name == ".." ? Color.primary : Color.secondary)

                        if !entry.permissions.isEmpty {
                            Text(entry.permissions)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.quaternary)
                        }
                    }
                    .multilineTextAlignment(.leading)

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(entry.modifiedDisplay)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 150, alignment: .leading)
                    .lineLimit(1)

                Text(entry.sizeDisplay)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 88, alignment: .trailing)
                    .lineLimit(1)

                Text(entry.kindLabel)
                    .font(.system(.callout))
                    .foregroundStyle(.tertiary)
                    .frame(width: 72, alignment: .leading)
                    .lineLimit(1)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var footerBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("当前路径")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.tertiary)
                Text(browser.resolvedPWD.isEmpty ? browser.currentLogicalPath : browser.resolvedPWD)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button("取消", role: .cancel) {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            Button("使用此目录") {
                let choice = browser.resolvedPWD.isEmpty ? browser.currentLogicalPath : browser.resolvedPWD
                boundPath = choice
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(browser.isLoading || browser.errorMessage != nil)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

private struct RemoteDirectoryBrowserContainer: View {
    @Binding var path: String
    @StateObject private var browser: RemoteDirectoryBrowserModel

    init(hostAlias: String, path: Binding<String>) {
        _path = path
        _browser = StateObject(wrappedValue: RemoteDirectoryBrowserModel(hostAlias: hostAlias, initialPath: path.wrappedValue))
    }

    var body: some View {
        RemoteDirectoryBrowserSheet(browser: browser, boundPath: $path)
    }
}

private struct HostSidebarRow: View {
    let host: SSHHost

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(host.name)
                .font(.system(.body).weight(.medium))
                .foregroundStyle(.primary)
            Text(host.subtitle)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

private struct HostDetailHeader: View {
    let host: SSHHost

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(host.name)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text("SSH")
                    .font(.system(.caption2).weight(.semibold))
                    .tracking(0.8)
                    .foregroundStyle(Color.porterAccent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.porterAccent.opacity(0.12))
                    )
                    .offset(y: -6)
            }

            HStack(spacing: 0) {
                MetaCell(label: "用户", value: host.user ?? "默认")

                metaDivider

                MetaCell(label: "地址", value: host.hostName ?? host.name)

                metaDivider

                MetaCell(label: "端口", value: host.port ?? "22")

                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var metaDivider: some View {
        Rectangle()
            .fill(Color.porterBorder)
            .frame(width: 1, height: 28)
            .padding(.horizontal, 20)
    }
}

private struct MetaCell: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(.caption2).weight(.medium))
                .tracking(0.6)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

private struct PathField: View {
    @Binding var text: String
    @Binding var isRemoteBrowserPresented: Bool
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("默认远程目录")
                .font(.system(.subheadline).weight(.semibold))
                .foregroundStyle(.primary)

            HStack(alignment: .center, spacing: 10) {
                TextField("/var/www/app 或 ~/uploads", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .monospaced))
                    .focused($isFocused)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.porterSurface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(
                                isFocused ? Color.porterAccent.opacity(0.55) : Color.porterBorder,
                                lineWidth: isFocused ? 1.5 : 1
                            )
                    )
                    .animation(.easeOut(duration: 0.15), value: isFocused)

                Button {
                    isRemoteBrowserPresented = true
                } label: {
                    Image(systemName: "folder.fill")
                        .imageScale(.medium)
                }
                .buttonStyle(.bordered)
                .tint(Color.porterAccent)
                .help("在远端按层级浏览并选择目录（需本机对该 Host 可免交互 ssh）")
                .accessibilityLabel("远端目录层级浏览")
            }

            Text("可直接输入路径，或通过右侧按钮连接远端浏览；上传时路径将交给 scp，连接仍走 ~/.ssh/config。")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}

private struct StatusRow: View {
    let log: String
    let isUploading: Bool

    private enum Kind { case idle, progress, success, error }

    private var kind: Kind {
        if isUploading { return .progress }
        if log.contains("失败") || log.contains("错误") { return .error }
        if log.contains("完成") { return .success }
        return .idle
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            indicator
                .frame(width: 14, height: 14)

            Text(log)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(2)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.porterSurface.opacity(0.7))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.porterBorder, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var indicator: some View {
        switch kind {
        case .progress:
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.7)
        case .success:
            Circle().fill(Color.green.opacity(0.9)).frame(width: 8, height: 8)
        case .error:
            Circle().fill(Color.red.opacity(0.9)).frame(width: 8, height: 8)
        case .idle:
            Circle().fill(Color.secondary.opacity(0.5)).frame(width: 8, height: 8)
        }
    }
}

struct ContentView: View {
    @StateObject private var model = AppModel()
    @State private var isFileImporterPresented = false
    @State private var isDropTargeted = false
    @State private var isRemoteBrowserPresented = false

    var body: some View {
        NavigationSplitView {
            List(model.hosts, selection: $model.selectedHostID) { host in
                HostSidebarRow(host: host)
                    .tag(host.id)
            }
            .listStyle(.sidebar)
            .compositingGroup()
            .navigationSplitViewColumnWidth(min: 240, ideal: 260, max: 320)
            .navigationTitle("Porter")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button {
                        model.refreshHosts()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .imageScale(.medium)
                    }
                    .buttonStyle(.borderless)
                    .help("重新读取 ~/.ssh/config 中的 Host 列表")
                    .accessibilityLabel("重新读取 SSH 配置")
                }
            }
        } detail: {
            ZStack(alignment: .topLeading) {
                Color.porterCanvas.ignoresSafeArea()
                detailView
                    .padding(.horizontal, 40)
                    .padding(.top, 36)
                    .padding(.bottom, 28)
            }
            .frame(minWidth: 600, minHeight: 520)
            .compositingGroup()
        }
        .navigationSplitViewStyle(.balanced)
        .tint(.porterAccent)
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                model.upload(urls: urls)
            }
        }
        .sheet(isPresented: $isRemoteBrowserPresented) {
            if let host = model.selectedHost {
                RemoteDirectoryBrowserContainer(hostAlias: host.name, path: model.pathBinding(for: host))
            } else {
                Text("未选择主机")
                    .padding(24)
            }
        }
    }

    @ViewBuilder
    private var detailView: some View {
        if let host = model.selectedHost {
            VStack(alignment: .leading, spacing: 28) {
                HostDetailHeader(host: host)
                    .padding(.bottom, 4)

                Rectangle()
                    .fill(Color.porterBorder)
                    .frame(height: 1)

                PathField(text: model.pathBinding(for: host), isRemoteBrowserPresented: $isRemoteBrowserPresented)

                DropZone(isTargeted: isDropTargeted, isUploading: model.isUploading)
                    .onTapGesture {
                        isFileImporterPresented = true
                    }
                    .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                        loadDroppedURLs(from: providers)
                        return true
                    }

                HStack(spacing: 10) {
                    Button {
                        isFileImporterPresented = true
                    } label: {
                        Label("选择文件上传", systemImage: "tray.and.arrow.up")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(model.isUploading)

                    Button {
                        openSSHTest(host: host.name)
                    } label: {
                        Label("在终端测试 SSH", systemImage: "terminal")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(model.isUploading)

                    Spacer(minLength: 0)
                }

                Spacer(minLength: 0)

                StatusRow(log: model.log, isUploading: model.isUploading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            emptyState
        }
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: "externaldrive.badge.questionmark")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.tertiary)
            VStack(spacing: 6) {
                Text("没有可用的 SSH 主机")
                    .font(.system(.title3).weight(.semibold))
                Text("请在 ~/.ssh/config 中添加 Host alias，然后点击工具栏中的刷新图标重新加载。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadDroppedURLs(from providers: [NSItemProvider]) {
        let group = DispatchGroup()
        let urlStore = LockedURLStore()

        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                let url: URL?
                if let data = item as? Data,
                   let decoded = String(data: data, encoding: .utf8) {
                    url = URL(string: decoded)
                } else {
                    url = item as? URL
                }

                guard let url else { return }
                urlStore.append(url)
            }
        }

        group.notify(queue: .main) {
            model.upload(urls: urlStore.snapshot())
        }
    }

    private func openSSHTest(host: String) {
        let command = "ssh -- \(localShellQuoted(host))"
        let script = "tell application \"Terminal\" to do script \(appleScriptQuoted(command))"
        NSAppleScript(source: script)?.executeAndReturnError(nil)
    }

    private func localShellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private func appleScriptQuoted(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
    }
}

final class LockedURLStore: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [URL] = []

    func append(_ url: URL) {
        lock.lock()
        urls.append(url)
        lock.unlock()
    }

    func snapshot() -> [URL] {
        lock.lock()
        let snapshot = urls
        lock.unlock()
        return snapshot
    }
}

struct DropZone: View {
    let isTargeted: Bool
    let isUploading: Bool

    private var iconName: String {
        if isUploading { return "arrow.triangle.2.circlepath" }
        return isTargeted ? "tray.and.arrow.down.fill" : "tray.and.arrow.down"
    }

    private var primaryText: String {
        if isUploading { return "正在上传…" }
        return isTargeted ? "释放即可上传" : "把文件拖到这里"
    }

    private var supportText: String {
        if isUploading { return "请稍候，文件正在通过 scp 发送" }
        return "或点击下方按钮选择本地文件"
    }

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        isTargeted
                            ? Color.porterAccent.opacity(0.16)
                            : Color.primary.opacity(0.05)
                    )
                    .frame(width: 64, height: 64)
                Image(systemName: iconName)
                    .font(.system(size: 26, weight: .regular))
                    .foregroundStyle(isTargeted ? Color.porterAccent : .secondary)
                    .symbolEffect(.pulse, options: .repeating, value: isUploading)
            }

            VStack(spacing: 4) {
                Text(primaryText)
                    .font(.system(.title3).weight(.medium))
                    .foregroundStyle(.primary)
                Text(supportText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 220)
        .padding(28)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    isTargeted
                        ? Color.porterAccent.opacity(0.06)
                        : Color.porterSurface
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    isTargeted ? Color.porterAccent.opacity(0.65) : Color.porterBorder,
                    lineWidth: isTargeted ? 1.5 : 1
                )
        )
        .animation(.easeOut(duration: 0.18), value: isTargeted)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

@main
struct PorterApp: App {
    init() {
        // 从 swift run / 终端直接启动裸可执行文件时，默认可能不注册为“普通应用”，
        // 导致 Dock 与 ⌘+Tab 中不可见；显式设为 regular 并随后台激活到前台。
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1040, height: 640)
    }
}
