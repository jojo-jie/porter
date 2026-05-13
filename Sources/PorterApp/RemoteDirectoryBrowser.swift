import AppKit
import Foundation
import PorterCore
import SwiftUI

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
        guard !isLoading, newSegments != segments else { return }
        isLoading = true
        pastSegments.append(segments)
        futureSegments.removeAll()
        segments = newSegments
        syncHistoryFlags()
        Task { await refreshList() }
    }

    func goBack() {
        guard !isLoading, let prev = pastSegments.popLast() else { return }
        isLoading = true
        futureSegments.insert(segments, at: 0)
        segments = prev
        Task { await refreshList() }
        syncHistoryFlags()
    }

    func goForward() {
        guard !isLoading, !futureSegments.isEmpty else { return }
        isLoading = true
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
        guard !isLoading else { return }
        if entry.name == ".." {
            goToParent()
            return
        }
        guard entry.navigable, entry.isDirectory else { return }
        replacePathAndReload(RemotePathCodec.appendComponent(segments, entry.name))
    }

    func goToBreadcrumb(index: Int) {
        guard !isLoading else { return }
        guard index >= 0, index < segments.count else { return }
        let prefix = Array(segments.prefix(index + 1))
        guard prefix != segments else { return }
        replacePathAndReload(prefix)
    }

    func remotePath(for entry: RemoteListingEntry) -> String {
        let base = resolvedPWD.isEmpty ? currentLogicalPath : resolvedPWD
        if base == "/" {
            return "/\(entry.name)"
        }
        return base.hasSuffix("/") ? "\(base)\(entry.name)" : "\(base)/\(entry.name)"
    }

    func refreshList() async {
        isLoading = true
        errorMessage = nil

        let host = hostAlias
        let path = RemotePathCodec.join(segments)
        let script = """
        set -e
        \(RemoteShellPath.changeDirectoryCommand(for: path))
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
    @ObservedObject var browser: RemoteDirectoryBrowserModel
    @Binding var boundPath: String
    let onDismiss: () -> Void

    @State private var selectedName: String?
    @State private var filterText = ""
    @State private var hoveredName: String?
    @State private var downloadingNames: Set<String> = []
    @State private var downloadMessage: String?

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

            filterBar
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.porterCanvas)

            listingsTable
                .frame(minHeight: 220)

            Rectangle()
                .fill(Color.porterBorder)
                .frame(height: 1)

            footerBar
        }
        .frame(width: 680, height: 520)
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
                onDismiss()
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

    private var filterBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.tertiary)
                .imageScale(.small)

            TextField("筛选当前目录中的文件或文件夹", text: $filterText)
                .textFieldStyle(.plain)

            if !filterText.isEmpty {
                Button {
                    filterText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清空筛选")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.porterSurface.opacity(0.85))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.porterBorder, lineWidth: 1)
        )
    }

    private var displayedEntries: [RemoteListingEntry] {
        let query = filterText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return browser.entries }
        return browser.entries.filter { entry in
            entry.name == ".." || entry.name.localizedCaseInsensitiveContains(query)
        }
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
                        ForEach(displayedEntries) { entry in
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

            if !browser.isLoading, browser.errorMessage == nil, displayedEntries.isEmpty {
                ContentUnavailableView(
                    "未找到匹配项目",
                    systemImage: "magnifyingglass",
                    description: Text("请尝试其他筛选关键词。")
                )
                .foregroundStyle(.secondary)
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
            Text("操作")
                .frame(width: 52, alignment: .center)
        }
        .font(.system(.caption2).weight(.semibold))
        .foregroundStyle(.tertiary)
        .textCase(nil)
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(Color.porterSurface.opacity(0.9))
    }

    private func listingRow(_ entry: RemoteListingEntry) -> some View {
        HStack(spacing: 0) {
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
            .contentShape(Rectangle())
            .frame(maxWidth: .infinity, alignment: .leading)
            .onTapGesture {
                openListingEntry(entry)
            }

            downloadCell(for: entry)
                .frame(width: 52, alignment: .center)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .onHover { isHovering in
            hoveredName = isHovering ? entry.name : (hoveredName == entry.name ? nil : hoveredName)
        }
    }

    private func openListingEntry(_ entry: RemoteListingEntry) {
        guard !browser.isLoading else { return }
        selectedName = entry.name
        if entry.name == ".." {
            browser.goToParent()
        } else if entry.navigable, entry.isDirectory {
            browser.openEntry(entry)
        }
    }

    @ViewBuilder
    private func downloadCell(for entry: RemoteListingEntry) -> some View {
        if entry.name != "..", hoveredName == entry.name || downloadingNames.contains(entry.name) {
            Button {
                chooseDestinationAndDownload(entry)
            } label: {
                if downloadingNames.contains(entry.name) {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.65)
                } else {
                    Image(systemName: "arrow.down.circle")
                        .imageScale(.medium)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.porterAccent)
            .help("下载到本地目录")
            .accessibilityLabel("下载 \(entry.name)")
            .disabled(downloadingNames.contains(entry.name))
        }
    }

    private func chooseDestinationAndDownload(_ entry: RemoteListingEntry) {
        guard !downloadingNames.contains(entry.name) else { return }

        let panel = NSOpenPanel()
        panel.title = "选择下载保存目录"
        panel.prompt = "下载到此目录"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let destination = panel.url else { return }

        let remotePath = browser.remotePath(for: entry)
        downloadingNames.insert(entry.name)
        downloadMessage = "正在下载：\(entry.name)"

        Task {
            let result = await RemoteDownloader.download(
                host: browser.hostAlias,
                remotePath: remotePath,
                destinationDirectory: destination,
                remoteIsDirectory: entry.isDirectory
            )
            downloadingNames.remove(entry.name)
            downloadMessage = result
        }
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

                if let downloadMessage {
                    Text(downloadMessage)
                        .font(.caption)
                        .foregroundStyle(downloadMessage.contains("失败") ? Color.red.opacity(0.9) : Color.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button("取消", role: .cancel) {
                onDismiss()
            }
            .keyboardShortcut(.cancelAction)

            Button("使用此目录") {
                let choice = browser.resolvedPWD.isEmpty ? browser.currentLogicalPath : browser.resolvedPWD
                boundPath = choice
                onDismiss()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .tint(Color.porterAccent)
            .disabled(browser.isLoading || browser.errorMessage != nil)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

struct RemoteDirectoryBrowserContainer: View {
    @Binding var path: String
    @StateObject private var browser: RemoteDirectoryBrowserModel
    let onDismiss: () -> Void

    init(hostAlias: String, path: Binding<String>, onDismiss: @escaping () -> Void) {
        _path = path
        _browser = StateObject(wrappedValue: RemoteDirectoryBrowserModel(hostAlias: hostAlias, initialPath: path.wrappedValue))
        self.onDismiss = onDismiss
    }

    var body: some View {
        RemoteDirectoryBrowserSheet(browser: browser, boundPath: $path, onDismiss: onDismiss)
    }
}
