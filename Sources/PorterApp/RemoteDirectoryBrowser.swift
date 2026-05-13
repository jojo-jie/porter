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

    /// Full remote path for an item listed in the current directory (`pwd` / logical path).
    func remotePathInCurrentDirectory(named name: String) -> String {
        let base = resolvedPWD.isEmpty ? currentLogicalPath : resolvedPWD
        if base == "/" {
            return "/\(name)"
        }
        return base.hasSuffix("/") ? "\(base)\(name)" : "\(base)/\(name)"
    }

    func remotePath(for entry: RemoteListingEntry) -> String {
        remotePathInCurrentDirectory(named: entry.name)
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

    private struct RenameConfirmation: Identifiable {
        let id = UUID()
        let entry: RemoteListingEntry
        let newName: String
    }

    private struct RenamePrompt: Identifiable {
        let id = UUID()
        let entry: RemoteListingEntry
    }

    private struct DeleteConfirmation: Identifiable {
        let id = UUID()
        let entry: RemoteListingEntry
    }

    @State private var selectedName: String?
    @State private var filterText = ""
    @State private var listRefreshSpin = 0
    @State private var hoveredName: String?
    @State private var downloadingNames: Set<String> = []
    @State private var renamingNames: Set<String> = []
    @State private var deletingNames: Set<String> = []
    @State private var footerStatusMessage: String?
    @State private var pendingRenamePrompt: RenamePrompt?
    @State private var pendingRenameConfirmation: RenameConfirmation?
    @State private var pendingDeleteConfirmation: DeleteConfirmation?
    @State private var renameDraftName = ""
    @FocusState private var isRenamePromptFocused: Bool

    var body: some View {
        ZStack {
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

            if let pendingRenamePrompt {
                renamePromptOverlay(pendingRenamePrompt)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }

            if let pendingRenameConfirmation {
                renameConfirmationOverlay(pendingRenameConfirmation)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }

            if let pendingDeleteConfirmation {
                deleteConfirmationOverlay(pendingDeleteConfirmation)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .frame(width: 680, height: 520)
        .background(Color.porterCanvas)
        .animation(.easeOut(duration: 0.16), value: pendingRenamePrompt?.id)
        .animation(.easeOut(duration: 0.16), value: pendingRenameConfirmation?.id)
        .animation(.easeOut(duration: 0.16), value: pendingDeleteConfirmation?.id)
        .task {
            await browser.refreshList()
        }
        .onChange(of: browser.segments) { _, _ in
            filterText = ""
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
            .porterPointingHandCursor()
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
                .porterPointingHandCursor(browser.canGoBack && !browser.isLoading)

                Button {
                    browser.goForward()
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.borderless)
                .disabled(!browser.canGoForward || browser.isLoading)
                .help("前进")
                .porterPointingHandCursor(browser.canGoForward && !browser.isLoading)
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
                        .porterPointingHandCursor(!browser.isLoading)
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
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.tertiary)
                    .imageScale(.small)

                TextField("筛选当前目录中的文件或文件夹", text: $filterText)
                    .textFieldStyle(.plain)
                    .frame(maxWidth: .infinity)

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
                    .porterPointingHandCursor()
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.porterSurface.opacity(0.85))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.porterBorder, lineWidth: 1)
            )

            Button {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                    listRefreshSpin += 1
                }
                Task { await browser.refreshList() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .imageScale(.medium)
                    .rotationEffect(.degrees(Double(listRefreshSpin) * 360))
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(Color.porterSurface.opacity(0.9))
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(Color.porterBorder, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.porterAccent)
            .help("重新加载当前远端目录列表")
            .accessibilityLabel("刷新目录列表")
            .disabled(browser.isLoading)
            .porterPointingHandCursor(!browser.isLoading)
        }
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
                .frame(width: 118, alignment: .center)
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
            .porterPointingHandCursor(!browser.isLoading)

            HStack(spacing: 6) {
                downloadCell(for: entry)
                renameCell(for: entry)
                deleteCell(for: entry)
            }
            .frame(width: 118, alignment: .center)
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
        if entry.name != "..", hoveredName == entry.name || downloadingNames.contains(entry.name) || renamingNames.contains(entry.name) || deletingNames.contains(entry.name) {
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
            .disabled(downloadingNames.contains(entry.name) || renamingNames.contains(entry.name) || deletingNames.contains(entry.name))
            .porterPointingHandCursor(!downloadingNames.contains(entry.name) && !renamingNames.contains(entry.name) && !deletingNames.contains(entry.name))
        }
    }

    @ViewBuilder
    private func renameCell(for entry: RemoteListingEntry) -> some View {
        if entry.name != "..", hoveredName == entry.name || renamingNames.contains(entry.name) || downloadingNames.contains(entry.name) || deletingNames.contains(entry.name) {
            Button {
                beginRename(entry)
            } label: {
                if renamingNames.contains(entry.name) {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.65)
                } else {
                    Image(systemName: "pencil.line")
                        .imageScale(.medium)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.porterAccent)
            .help("重命名远端文件或文件夹")
            .accessibilityLabel("重命名 \(entry.name)")
            .disabled(renamingNames.contains(entry.name) || downloadingNames.contains(entry.name) || deletingNames.contains(entry.name))
            .porterPointingHandCursor(!renamingNames.contains(entry.name) && !downloadingNames.contains(entry.name) && !deletingNames.contains(entry.name))
        }
    }

    @ViewBuilder
    private func deleteCell(for entry: RemoteListingEntry) -> some View {
        if entry.name != "..", hoveredName == entry.name || deletingNames.contains(entry.name) || downloadingNames.contains(entry.name) || renamingNames.contains(entry.name) {
            Button {
                beginDelete(entry)
            } label: {
                if deletingNames.contains(entry.name) {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.65)
                } else {
                    Image(systemName: "trash")
                        .imageScale(.medium)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.red.opacity(0.88))
            .help("删除远端文件或文件夹")
            .accessibilityLabel("删除 \(entry.name)")
            .disabled(deletingNames.contains(entry.name) || downloadingNames.contains(entry.name) || renamingNames.contains(entry.name))
            .porterPointingHandCursor(!deletingNames.contains(entry.name) && !downloadingNames.contains(entry.name) && !renamingNames.contains(entry.name))
        }
    }

    private func chooseDestinationAndDownload(_ entry: RemoteListingEntry) {
        guard !downloadingNames.contains(entry.name), !deletingNames.contains(entry.name) else { return }

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
        footerStatusMessage = "正在下载：\(entry.name)"

        Task {
            let result = await RemoteDownloader.download(
                host: browser.hostAlias,
                remotePath: remotePath,
                destinationDirectory: destination,
                remoteIsDirectory: entry.isDirectory
            )
            downloadingNames.remove(entry.name)
            footerStatusMessage = result
        }
    }

    private func beginRename(_ entry: RemoteListingEntry) {
        guard !renamingNames.contains(entry.name), !downloadingNames.contains(entry.name), !deletingNames.contains(entry.name) else { return }

        renameDraftName = entry.name
        pendingRenamePrompt = RenamePrompt(entry: entry)
    }

    private func continueRenamePrompt(_ prompt: RenamePrompt) {
        let newName = renameDraftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty else {
            footerStatusMessage = "重命名已取消：名称不能为空。"
            return
        }
        guard newName != prompt.entry.name else {
            footerStatusMessage = "名称未改变。"
            pendingRenamePrompt = nil
            return
        }
        guard !newName.contains("/") else {
            footerStatusMessage = "名称不能包含「/」。"
            return
        }

        pendingRenamePrompt = nil
        pendingRenameConfirmation = RenameConfirmation(entry: prompt.entry, newName: newName)
    }

    private func cancelRenamePrompt() {
        pendingRenamePrompt = nil
        renameDraftName = ""
    }

    private func confirmRename(_ confirmation: RenameConfirmation) {
        pendingRenameConfirmation = nil
        performRename(confirmation.entry, to: confirmation.newName)
    }

    private func cancelRenameConfirmation() {
        pendingRenameConfirmation = nil
    }

    private func performRename(_ entry: RemoteListingEntry, to newName: String) {
        let oldPath = browser.remotePath(for: entry)
        let newPath = browser.remotePathInCurrentDirectory(named: newName)
        let bash = """
        set -e
        \(RemoteShellPath.moveItemShellCommand(from: oldPath, to: newPath))
        """
        let host = browser.hostAlias

        renamingNames.insert(entry.name)
        footerStatusMessage = "正在重命名：\(entry.name)…"

        Task {
            let (exitCode, output) = await Task.detached(priority: .userInitiated) {
                RemoteSSH.run(host: host, bash: bash)
            }.value
            renamingNames.remove(entry.name)
            if exitCode == 0 {
                footerStatusMessage = "重命名完成：\(entry.name) → \(newName)"
                if selectedName == entry.name {
                    selectedName = newName
                }
                await browser.refreshList()
            } else {
                let tail = output
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "\r\n", with: "\n")
                let snippet =
                    tail.split(separator: "\n", omittingEmptySubsequences: false)
                        .prefix(4)
                        .joined(separator: "\n")
                footerStatusMessage = snippet.isEmpty
                    ? "重命名失败（退出码 \(exitCode)）。"
                    : "重命名失败（退出码 \(exitCode)）：\n\(snippet)"
            }
        }
    }

    private func beginDelete(_ entry: RemoteListingEntry) {
        guard !deletingNames.contains(entry.name), !downloadingNames.contains(entry.name), !renamingNames.contains(entry.name) else { return }
        pendingDeleteConfirmation = DeleteConfirmation(entry: entry)
    }

    private func confirmDelete(_ confirmation: DeleteConfirmation) {
        pendingDeleteConfirmation = nil
        performDelete(confirmation.entry)
    }

    private func cancelDeleteConfirmation() {
        pendingDeleteConfirmation = nil
    }

    private func performDelete(_ entry: RemoteListingEntry) {
        let path = browser.remotePath(for: entry)
        let bash = """
        set -e
        \(RemoteShellPath.removeItemShellCommand(path: path, recursive: entry.isDirectory))
        """
        let host = browser.hostAlias
        let name = entry.name

        deletingNames.insert(name)
        footerStatusMessage = "正在删除：\(name)…"

        Task {
            let (exitCode, output) = await Task.detached(priority: .userInitiated) {
                RemoteSSH.run(host: host, bash: bash)
            }.value
            deletingNames.remove(name)
            if exitCode == 0 {
                footerStatusMessage = "删除完成：\(name)"
                if selectedName == name {
                    selectedName = nil
                }
                await browser.refreshList()
            } else {
                let tail = output
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "\r\n", with: "\n")
                let snippet =
                    tail.split(separator: "\n", omittingEmptySubsequences: false)
                        .prefix(4)
                        .joined(separator: "\n")
                footerStatusMessage = snippet.isEmpty
                    ? "删除失败（退出码 \(exitCode)）。"
                    : "删除失败（退出码 \(exitCode)）：\n\(snippet)"
            }
        }
    }

    private func renamePromptOverlay(_ prompt: RenamePrompt) -> some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    cancelRenamePrompt()
                }

            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    VStack(alignment: .leading, spacing: 16) {
                        renamePromptField

                        Text("请输入新的文件或文件夹名称。远端路径会在下一步确认后生效。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 34)
                    .padding(.bottom, 24)

                    Button {
                        cancelRenamePrompt()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 12)
                    .padding(.trailing, 12)
                    .accessibilityLabel("关闭重命名")
                    .porterPointingHandCursor()
                }

                HStack(spacing: 10) {
                    Spacer()
                    Button("取消", role: .cancel) {
                        cancelRenamePrompt()
                    }
                    .keyboardShortcut(.cancelAction)
                    .porterPointingHandCursor()

                    Button("继续") {
                        continueRenamePrompt(prompt)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.porterAccent)
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
                    .porterPointingHandCursor()
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .frame(width: 560)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.porterSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.porterBorder, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.20), radius: 22, x: 0, y: 12)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .onTapGesture {}
            .onAppear {
                isRenamePromptFocused = true
            }
        }
    }

    private var renamePromptField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("新名称 *")
                .font(.system(.caption).weight(.medium))
                .foregroundStyle(Color.porterAccent)
                .padding(.horizontal, 6)
                .background(Color.porterSurface)
                .offset(x: 12, y: 8)
                .zIndex(1)

            TextField("", text: $renameDraftName)
                .textFieldStyle(.plain)
                .font(.system(size: 16, design: .monospaced))
                .focused($isRenamePromptFocused)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.porterSurface.opacity(0.85))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.porterAccent.opacity(0.55), lineWidth: 1.5)
                )
        }
    }

    private func renameConfirmationOverlay(_ confirmation: RenameConfirmation) -> some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    cancelRenameConfirmation()
                }

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 16) {
                    Text("重命名")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.primary)

                    Spacer()

                    Button {
                        cancelRenameConfirmation()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 32)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("关闭重命名确认")
                    .porterPointingHandCursor()
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)

                Rectangle()
                    .fill(Color.porterBorder)
                    .frame(height: 1)

                VStack(alignment: .leading, spacing: 16) {
                    Text("请确认新的远端文件或文件夹名称。确认后会立即在远端生效。")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    renameConfirmationField(value: confirmation.newName)

                    HStack(spacing: 6) {
                        Text("原名称")
                            .font(.system(.caption2).weight(.semibold))
                            .tracking(0.6)
                            .foregroundStyle(.tertiary)
                        Text(confirmation.entry.name)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 34)
                .padding(.bottom, 24)

                HStack(spacing: 10) {
                    Spacer()
                    Button("取消", role: .cancel) {
                        cancelRenameConfirmation()
                    }
                    .keyboardShortcut(.cancelAction)
                    .porterPointingHandCursor()

                    Button("确认") {
                        confirmRename(confirmation)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.porterAccent)
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
                    .porterPointingHandCursor()
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .frame(width: 560)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.porterSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.porterBorder, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.20), radius: 22, x: 0, y: 12)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .onTapGesture {}
        }
    }

    private func renameConfirmationField(value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("新名称 *")
                .font(.system(.caption).weight(.medium))
                .foregroundStyle(Color.porterAccent)
                .padding(.horizontal, 6)
                .background(Color.porterSurface)
                .offset(x: 12, y: 8)
                .zIndex(1)

            Text(value)
                .font(.system(size: 16, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.porterSurface.opacity(0.85))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.porterAccent.opacity(0.55), lineWidth: 1.5)
                )
        }
    }

    private func deleteConfirmationOverlay(_ confirmation: DeleteConfirmation) -> some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    cancelDeleteConfirmation()
                }

            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    VStack(alignment: .leading, spacing: 16) {
                        deleteTargetField(confirmation.entry)

                        Text(
                            confirmation.entry.isDirectory
                                ? "将删除整个文件夹及其中的全部内容。此操作无法在 Porter 内撤销。"
                                : "远端文件将立即被删除。此操作无法在 Porter 内撤销。"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 34)
                    .padding(.bottom, 24)

                    Button {
                        cancelDeleteConfirmation()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 12)
                    .padding(.trailing, 12)
                    .accessibilityLabel("关闭删除确认")
                    .porterPointingHandCursor()
                }

                HStack(spacing: 10) {
                    Spacer()
                    Button("取消", role: .cancel) {
                        cancelDeleteConfirmation()
                    }
                    .keyboardShortcut(.cancelAction)
                    .porterPointingHandCursor()

                    Button("删除", role: .destructive) {
                        confirmDelete(confirmation)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .porterPointingHandCursor()
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .frame(width: 560)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.porterSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.porterBorder, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.20), radius: 22, x: 0, y: 12)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .onTapGesture {}
        }
    }

    private func deleteTargetField(_ entry: RemoteListingEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("将删除 *")
                .font(.system(.caption).weight(.medium))
                .foregroundStyle(Color.red.opacity(0.88))
                .padding(.horizontal, 6)
                .background(Color.porterSurface)
                .offset(x: 12, y: 8)
                .zIndex(1)

            Text(entry.name)
                .font(.system(size: 16, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.porterSurface.opacity(0.85))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.red.opacity(0.45), lineWidth: 1.5)
                )
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

                if let footerStatusMessage {
                    Text(footerStatusMessage)
                        .font(.caption)
                        .foregroundStyle(footerStatusMessage.contains("失败") ? Color.red.opacity(0.9) : Color.secondary)
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
            .porterPointingHandCursor()

            Button("使用此目录") {
                let choice = browser.resolvedPWD.isEmpty ? browser.currentLogicalPath : browser.resolvedPWD
                boundPath = choice
                onDismiss()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .tint(Color.porterAccent)
            .disabled(browser.isLoading || browser.errorMessage != nil)
            .porterPointingHandCursor(!browser.isLoading && browser.errorMessage == nil)
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
