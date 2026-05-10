import AppKit
import SwiftUI
import UniformTypeIdentifiers

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
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
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

struct ContentView: View {
    @StateObject private var model = AppModel()
    @State private var isFileImporterPresented = false
    @State private var isDropTargeted = false

    var body: some View {
        NavigationSplitView {
            List(model.hosts, selection: $model.selectedHostID) { host in
                VStack(alignment: .leading, spacing: 4) {
                    Text(host.name)
                        .font(.headline)
                    Text(host.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.vertical, 4)
                .tag(host.id)
            }
            .navigationTitle("SSH 主机")
            .toolbar {
                Button("刷新") {
                    model.refreshHosts()
                }
            }
        } detail: {
            detailView
        }
        .frame(minWidth: 860, minHeight: 520)
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                model.upload(urls: urls)
            }
        }
    }

    @ViewBuilder
    private var detailView: some View {
        if let host = model.selectedHost {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(host.name)
                        .font(.largeTitle.bold())
                    Text(host.subtitle)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("默认远程目录")
                        .font(.headline)
                    TextField("/var/www/app 或 ~/uploads", text: model.pathBinding(for: host))
                        .textFieldStyle(.roundedBorder)
                }

                DropZone(isTargeted: isDropTargeted, isUploading: model.isUploading)
                    .onTapGesture {
                        isFileImporterPresented = true
                    }
                    .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                        loadDroppedURLs(from: providers)
                        return true
                    }

                HStack {
                    Button("选择文件上传") {
                        isFileImporterPresented = true
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isUploading)

                    Button("在终端测试 SSH") {
                        openSSHTest(host: host.name)
                    }
                    .disabled(model.isUploading)
                }

                Text(model.log)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(model.log.contains("失败") ? .red : .secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer()
            }
            .padding(28)
        } else {
            ContentUnavailableView(
                "没有 SSH 主机",
                systemImage: "externaldrive.badge.wifi",
                description: Text("请在 ~/.ssh/config 中添加 Host alias，然后点击刷新。")
            )
        }
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

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: isUploading ? "arrow.triangle.2.circlepath" : "square.and.arrow.up")
                .font(.system(size: 44, weight: .semibold))
                .symbolEffect(.pulse, options: .repeating, value: isUploading)
            Text(isUploading ? "正在上传…" : "点击选择，或把文件拖到这里上传")
                .font(.headline)
            Text("上传命令使用系统 /usr/bin/scp，并复用本机 ~/.ssh/config。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 190)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(isTargeted ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.secondary.opacity(0.28),
                    style: StrokeStyle(lineWidth: 2, dash: [8, 6])
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 18))
    }
}

@main
struct PorterApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.titleBar)
    }
}
