import Foundation
import PorterCore

@MainActor
final class RemoteDirectoryBrowserModel: ObservableObject {
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

    /// Invalidates in-flight list fetches so stale SSH results cannot overwrite a newer directory.
    private var activeListRequestID: UInt64 = 0

    var currentLogicalPath: String { RemotePathCodec.join(segments) }

    init(hostAlias: String, initialPath: String) {
        self.hostAlias = hostAlias
        self.segments = RemotePathCodec.split(initialPath)
    }

    private func beginListLoad() -> UInt64 {
        activeListRequestID &+= 1
        isLoading = true
        errorMessage = nil
        return activeListRequestID
    }

    func replacePathAndReload(_ newSegments: [String]) {
        guard newSegments != segments else { return }
        let requestID = beginListLoad()
        pastSegments.append(segments)
        futureSegments.removeAll()
        segments = newSegments
        syncHistoryFlags()
        Task { await performListFetch(requestID: requestID, segmentsSnapshot: newSegments) }
    }

    func goBack() {
        guard let prev = pastSegments.popLast() else { return }
        let requestID = beginListLoad()
        futureSegments.insert(segments, at: 0)
        segments = prev
        syncHistoryFlags()
        Task { await performListFetch(requestID: requestID, segmentsSnapshot: prev) }
    }

    func goForward() {
        guard !futureSegments.isEmpty else { return }
        let requestID = beginListLoad()
        let next = futureSegments.removeFirst()
        pastSegments.append(segments)
        segments = next
        syncHistoryFlags()
        Task { await performListFetch(requestID: requestID, segmentsSnapshot: next) }
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
        let snapshot = segments
        let requestID = beginListLoad()
        await performListFetch(requestID: requestID, segmentsSnapshot: snapshot)
    }

    private func performListFetch(requestID: UInt64, segmentsSnapshot: [String]) async {
        let host = hostAlias
        let path = RemotePathCodec.join(segmentsSnapshot)
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

        guard requestID == activeListRequestID else { return }

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

        if RemotePathCodec.parent(of: segmentsSnapshot) != nil {
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

final class RemoteListingClickTracker {
    private var lastClickedName: String?
    private var lastClickTime = Date.distantPast

    func registerClick(on name: String, at now: Date = Date()) -> Bool {
        let isDoubleClick = lastClickedName == name
            && now.timeIntervalSince(lastClickTime) <= 0.32
        lastClickedName = name
        lastClickTime = now
        return isDoubleClick
    }
}
