import Foundation
import PorterCore

@MainActor
final class RemoteDirectoryBrowserModel: ObservableObject {
    private struct CachedListing {
        let pwd: String
        let entries: [RemoteListingEntry]
        let fetchedAt: Date
    }

    private enum ListingParseResult: Sendable {
        case success(pwd: String, entries: [RemoteListingEntry])
        case invalidFormat
    }

    private static var listingCache: [String: CachedListing] = [:]
    private static let listingCacheTTL: TimeInterval = 30
    private static let listingCacheLimit = 100

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
        pastSegments.append(segments)
        futureSegments.removeAll()
        segments = newSegments
        syncHistoryFlags()
        Task { await loadListing(for: newSegments, force: false) }
    }

    func goBack() {
        guard let prev = pastSegments.popLast() else { return }
        futureSegments.insert(segments, at: 0)
        segments = prev
        syncHistoryFlags()
        Task { await loadListing(for: prev, force: false) }
    }

    func goForward() {
        guard !futureSegments.isEmpty else { return }
        let next = futureSegments.removeFirst()
        pastSegments.append(segments)
        segments = next
        syncHistoryFlags()
        Task { await loadListing(for: next, force: false) }
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

    func openPathFromCurrentDirectory(_ rawPath: String) {
        replacePathAndReload(RemotePathCodec.resolve(rawPath, against: segments))
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

    func refreshList(force: Bool = false) async {
        await loadListing(for: segments, force: force)
    }

    func invalidateCurrentListingCache() {
        Self.listingCache.removeValue(forKey: cacheKey(for: segments))
    }

    private func loadListing(for segmentsSnapshot: [String], force: Bool) async {
        if !force, applyCachedListingIfFresh(for: segmentsSnapshot) {
            return
        }
        let requestID = beginListLoad()
        await performListFetch(requestID: requestID, segmentsSnapshot: segmentsSnapshot)
    }

    private func cacheKey(for segments: [String]) -> String {
        "\(hostAlias)\u{1F}|\(RemotePathCodec.join(segments))"
    }

    private func applyCachedListingIfFresh(for segmentsSnapshot: [String]) -> Bool {
        guard let cached = Self.listingCache[cacheKey(for: segmentsSnapshot)] else { return false }
        guard Date().timeIntervalSince(cached.fetchedAt) < Self.listingCacheTTL else { return false }
        isLoading = false
        errorMessage = nil
        resolvedPWD = cached.pwd
        entries = cached.entries
        syncHistoryFlags()
        return true
    }

    private func storeListingCache(segmentsSnapshot: [String], pwd: String, entries: [RemoteListingEntry]) {
        Self.listingCache[cacheKey(for: segmentsSnapshot)] = CachedListing(
            pwd: pwd,
            entries: entries,
            fetchedAt: Date()
        )
        Self.pruneListingCacheIfNeeded()
    }

    private static func pruneListingCacheIfNeeded() {
        guard listingCache.count > listingCacheLimit else { return }
        let overflow = listingCache.count - listingCacheLimit
        let staleKeys = listingCache
            .sorted { $0.value.fetchedAt < $1.value.fetchedAt }
            .prefix(overflow)
            .map(\.key)
        for key in staleKeys {
            listingCache.removeValue(forKey: key)
        }
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

        let parseResult = await Task.detached(priority: .userInitiated) {
            Self.parseListingOutput(output, segmentsSnapshot: segmentsSnapshot)
        }.value

        guard requestID == activeListRequestID else { return }

        switch parseResult {
        case .invalidFormat:
            errorMessage = "无法解析远端目录列表，请改用路径输入。"
            entries = []
            resolvedPWD = ""
        case .success(let pwd, let parsed):
            resolvedPWD = pwd
            entries = parsed
            storeListingCache(segmentsSnapshot: segmentsSnapshot, pwd: pwd, entries: parsed)
        }
    }

    private func syncHistoryFlags() {
        canGoBack = !pastSegments.isEmpty
        canGoForward = !futureSegments.isEmpty
    }

    nonisolated private static func parseListingOutput(
        _ output: String,
        segmentsSnapshot: [String]
    ) -> ListingParseResult {
        let sections = output.components(separatedBy: "\n___PORTER_LS_BEGIN___\n")
        guard sections.count == 2 else {
            return .invalidFormat
        }

        let pwd = sections[0].trimmingCharacters(in: .whitespacesAndNewlines)
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

        return .success(pwd: pwd, entries: parsed)
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
