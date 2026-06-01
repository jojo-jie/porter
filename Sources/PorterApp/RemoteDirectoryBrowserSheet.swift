import AppKit
import Foundation
import PorterCore
import SwiftUI

struct RemoteDirectoryBrowserSheet: View {
    @EnvironmentObject var downloadPreferences: DownloadPreferencesStore
    @EnvironmentObject var remoteFileEditCoordinator: RemoteFileEditCoordinator
    @ObservedObject var browser: RemoteDirectoryBrowserModel
    @Binding var boundPath: String
    let onDismiss: () -> Void

    struct RenamePrompt: Identifiable {
        let id = UUID()
        let entry: RemoteListingEntry
    }

    struct DeleteConfirmation: Identifiable {
        let id = UUID()
        let entry: RemoteListingEntry
    }

    enum NewItemKind {
        case folder
        case file
    }

    struct NewItemPrompt: Identifiable {
        let id = UUID()
        let kind: NewItemKind
    }

    @State var selectedName: String?
    @State var filterText = ""
    @State var listRefreshSpin = 0
    @State var hoveredName: String?
    @State var rowClickTracker = RemoteListingClickTracker()
    @State var downloadingNames: Set<String> = []
    @State var renamingNames: Set<String> = []
    @State var deletingNames: Set<String> = []
    @State var footerStatusMessage: String?
    @State var pendingRenamePrompt: RenamePrompt?
    @State var pendingDeleteConfirmation: DeleteConfirmation?
    @State var pendingNewItemPrompt: NewItemPrompt?
    @State var renameDraftName = ""
    @State var newItemDraftName = ""
    /// Inline validation under the rename field (non-nil → red caption).
    @State var renamePromptErrorText: String?
    @State var newItemPromptErrorText: String?
    @State var renameCardShakePhase: CGFloat = 0
    @State var newItemCardShakePhase: CGFloat = 0
    @State var isCreatingNewItem = false
    @FocusState var isRenamePromptFocused: Bool
    @FocusState var isNewItemPromptFocused: Bool

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

            if let pendingDeleteConfirmation {
                deleteConfirmationOverlay(pendingDeleteConfirmation)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }

            if let pendingNewItemPrompt {
                newItemPromptOverlay(pendingNewItemPrompt)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .frame(width: 680, height: 520)
        .background(Color.porterCanvas)
        .animation(.easeOut(duration: 0.16), value: pendingRenamePrompt?.id)
        .animation(.easeOut(duration: 0.16), value: pendingDeleteConfirmation?.id)
        .animation(.easeOut(duration: 0.16), value: pendingNewItemPrompt?.id)
        .onReceive(NotificationCenter.default.publisher(for: .porterRemoteEditSyncFailed)) { notification in
            let name = notification.userInfo?["fileName"] as? String ?? "文件"
            let detail = notification.userInfo?["message"] as? String ?? "上传失败"
            footerStatusMessage = "编辑同步失败：\(name)\n\(detail)"
        }
        .onReceive(NotificationCenter.default.publisher(for: .porterRemoteEditSyncSucceeded)) { notification in
            let detail = notification.userInfo?["message"] as? String
            footerStatusMessage = detail ?? "已同步到远端"
        }
        .task {
            await browser.refreshList()
        }
        .onChange(of: browser.segments) { _, _ in
            filterText = ""
            selectedName = nil
        }
        .onChange(of: pendingRenamePrompt?.id) { _, _ in
            renamePromptErrorText = nil
            renameCardShakePhase = 0
        }
        .onChange(of: pendingNewItemPrompt?.id) { _, _ in
            newItemPromptErrorText = nil
            newItemCardShakePhase = 0
        }
    }
    func withoutAnimation(_ updates: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, updates)
    }

    func beginRemoteEdit(_ entry: RemoteListingEntry) {
        guard showsEditAction(for: entry) else { return }
        let remotePath = browser.remotePath(for: entry)
        guard !downloadingNames.contains(entry.name),
              !renamingNames.contains(entry.name),
              !deletingNames.contains(entry.name),
              !remoteFileEditCoordinator.isBusy(host: browser.hostAlias, remotePath: remotePath)
        else { return }

        footerStatusMessage = "正在准备编辑：\(entry.name)…"

        Task {
            let result = await remoteFileEditCoordinator.beginEdit(
                host: browser.hostAlias,
                remotePath: remotePath,
                fileName: entry.name
            )
            footerStatusMessage = result
        }
    }

    func chooseDestinationAndDownload(_ entry: RemoteListingEntry) {
        guard !downloadingNames.contains(entry.name), !deletingNames.contains(entry.name) else { return }
        let remotePath = browser.remotePath(for: entry)
        guard !remoteFileEditCoordinator.isBusy(host: browser.hostAlias, remotePath: remotePath) else { return }

        let destination: URL
        if let defaultDirectory = downloadPreferences.resolvedDirectoryURL {
            destination = defaultDirectory
        } else {
            let panel = NSOpenPanel()
            panel.title = "选择下载保存目录"
            panel.prompt = "下载到此目录"
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.canCreateDirectories = true
            panel.allowsMultipleSelection = false
            let expanded = (downloadPreferences.downloadDirectoryPath as NSString).expandingTildeInPath
            if !expanded.isEmpty, FileManager.default.fileExists(atPath: expanded) {
                panel.directoryURL = URL(fileURLWithPath: expanded, isDirectory: true)
            }

            guard panel.runModal() == .OK, let chosen = panel.url else { return }
            destination = chosen
        }

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

    func beginNewItem(_ kind: NewItemKind) {
        guard canMutateCurrentDirectory else { return }
        newItemDraftName = ""
        newItemPromptErrorText = nil
        newItemCardShakePhase = 0
        pendingNewItemPrompt = NewItemPrompt(kind: kind)
    }

    func continueNewItemPrompt(_ prompt: NewItemPrompt) {
        if let issue = RemoteFileNameValidation.validatePortableFileName(newItemDraftName) {
            presentNewItemValidationFailure(renameValidationMessage(for: issue))
            return
        }
        let name = newItemDraftName.trimmingCharacters(in: .whitespacesAndNewlines)
        newItemPromptErrorText = nil
        pendingNewItemPrompt = nil
        newItemDraftName = ""
        performCreateNewItem(name: name, kind: prompt.kind)
    }

    func presentNewItemValidationFailure(_ message: String) {
        newItemPromptErrorText = message
        triggerNewItemCardShake()
        footerStatusMessage = nil
    }

    func triggerNewItemCardShake() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            newItemCardShakePhase = 0
        }
        withAnimation(.easeOut(duration: 0.42)) {
            newItemCardShakePhase = 1
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.44))
            var done = Transaction()
            done.disablesAnimations = true
            withTransaction(done) {
                newItemCardShakePhase = 0
            }
        }
    }

    func cancelNewItemPrompt() {
        pendingNewItemPrompt = nil
        newItemDraftName = ""
        newItemPromptErrorText = nil
    }

    func performCreateNewItem(name: String, kind: NewItemKind) {
        let remotePath = browser.remotePathInCurrentDirectory(named: name)
        let commandLine: String =
            switch kind {
            case .folder:
                RemoteShellPath.createDirectoryShellCommand(path: remotePath)
            case .file:
                RemoteShellPath.createEmptyFileShellCommand(path: remotePath)
            }
        let bash = """
        set -e
        \(commandLine)
        """
        let host = browser.hostAlias
        let kindLabel = kind == .folder ? "文件夹" : "空文件"

        isCreatingNewItem = true
        footerStatusMessage = "正在新建\(kindLabel)：\(name)…"

        Task {
            let (exitCode, output) = await Task.detached(priority: .userInitiated) {
                RemoteSSH.run(host: host, bash: bash)
            }.value
            isCreatingNewItem = false
            if exitCode == 0 {
                footerStatusMessage = "已新建\(kindLabel)：\(name)"
                selectedName = name
                browser.invalidateCurrentListingCache()
                await browser.refreshList(force: true)
            } else if exitCode == 2 {
                footerStatusMessage = "无法新建：「\(name)」已存在于当前目录。"
            } else {
                let tail = output
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "\r\n", with: "\n")
                let snippet =
                    tail.split(separator: "\n", omittingEmptySubsequences: false)
                        .prefix(4)
                        .joined(separator: "\n")
                footerStatusMessage = snippet.isEmpty
                    ? "新建失败（退出码 \(exitCode)）。"
                    : "新建失败（退出码 \(exitCode)）：\n\(snippet)"
            }
        }
    }

    func beginRename(_ entry: RemoteListingEntry) {
        let remotePath = browser.remotePath(for: entry)
        guard !renamingNames.contains(entry.name),
              !downloadingNames.contains(entry.name),
              !deletingNames.contains(entry.name),
              !remoteFileEditCoordinator.isBusy(host: browser.hostAlias, remotePath: remotePath),
              !remoteFileEditCoordinator.hasEditSession(host: browser.hostAlias, remotePath: remotePath)
        else {
            if remoteFileEditCoordinator.hasEditSession(host: browser.hostAlias, remotePath: remotePath) {
                footerStatusMessage = "无法重命名：\(entry.name) 正在通过默认应用编辑，请先关闭编辑器。"
            }
            return
        }

        renameDraftName = entry.name
        renamePromptErrorText = nil
        renameCardShakePhase = 0
        pendingRenamePrompt = RenamePrompt(entry: entry)
    }

    func continueRenamePrompt(_ prompt: RenamePrompt) {
        if let issue = RemoteFileNameValidation.validatePortableFileName(renameDraftName) {
            presentRenameValidationFailure(renameValidationMessage(for: issue))
            return
        }
        let newName = renameDraftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard newName != prompt.entry.name else {
            presentRenameValidationFailure("请输入与当前名称不同的名称。")
            return
        }

        renamePromptErrorText = nil
        pendingRenamePrompt = nil
        renameDraftName = ""
        performRename(prompt.entry, to: newName)
    }

    func renameValidationMessage(for issue: RemoteFileNameValidation.Issue) -> String {
        switch issue {
        case .empty:
            return "名称不能为空。"
        case .hasInvisibleEdgeWhitespace:
            return "名称首尾不能含有空白或换行（不可见字符在 Windows / SMB 上易出问题）。"
        case .reservedAlias:
            return "不能使用名称「.」或「..」。"
        case .forbiddenCharacterOrControl:
            return "名称不能含有 / \\ : * ? \" < > | 以及控制字符；亦不可含路径分隔符（跨平台与安全限制）。"
        case .trailingPeriodDisallowedOnWindows:
            return "名称不能以英文句点「.」结尾（Windows / SMB 不兼容）。"
        case .windowsReservedDeviceName:
            return "该名称与 Windows 保留设备名冲突（如 CON、NUL、COM1 等），请改用其他名称。"
        case .utf8TooLong(let limit):
            return "名称过长（单段至多 \(limit) 字节 UTF-8，兼容常见 Linux / macOS / Windows 限制）。"
        }
    }

    func presentRenameValidationFailure(_ message: String) {
        renamePromptErrorText = message
        triggerRenameCardShake()
        footerStatusMessage = nil
    }

    func triggerRenameCardShake() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            renameCardShakePhase = 0
        }
        withAnimation(.easeOut(duration: 0.42)) {
            renameCardShakePhase = 1
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.44))
            var done = Transaction()
            done.disablesAnimations = true
            withTransaction(done) {
                renameCardShakePhase = 0
            }
        }
    }

    func cancelRenamePrompt() {
        pendingRenamePrompt = nil
        renameDraftName = ""
        renamePromptErrorText = nil
    }

    func performRename(_ entry: RemoteListingEntry, to newName: String) {
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
                browser.invalidateCurrentListingCache()
                await browser.refreshList(force: true)
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

    func beginDelete(_ entry: RemoteListingEntry) {
        let remotePath = browser.remotePath(for: entry)
        guard !deletingNames.contains(entry.name),
              !downloadingNames.contains(entry.name),
              !renamingNames.contains(entry.name),
              !remoteFileEditCoordinator.isBusy(host: browser.hostAlias, remotePath: remotePath),
              !remoteFileEditCoordinator.hasEditSession(host: browser.hostAlias, remotePath: remotePath)
        else {
            if remoteFileEditCoordinator.hasEditSession(host: browser.hostAlias, remotePath: remotePath) {
                footerStatusMessage = "无法删除：\(entry.name) 正在通过默认应用编辑，请先关闭编辑器。"
            }
            return
        }
        pendingDeleteConfirmation = DeleteConfirmation(entry: entry)
    }

    func confirmDelete(_ confirmation: DeleteConfirmation) {
        pendingDeleteConfirmation = nil
        performDelete(confirmation.entry)
    }

    func cancelDeleteConfirmation() {
        pendingDeleteConfirmation = nil
    }

    func performDelete(_ entry: RemoteListingEntry) {
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
                browser.invalidateCurrentListingCache()
                await browser.refreshList(force: true)
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
}
