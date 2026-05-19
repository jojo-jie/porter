import AppKit
import PorterCore
import SwiftUI
import UniformTypeIdentifiers

struct RemoteEditCacheSettingsCard: View {
    @EnvironmentObject private var remoteFileEditCoordinator: RemoteFileEditCoordinator

    @State private var cacheSizeBytes: Int64 = 0
    @State private var isMeasuring = false
    @State private var isClearing = false
    @State private var statusMessage: String?
    @State private var statusIsError = false

    private var formattedCacheSize: String {
        RemoteEditCache.formattedMegabytes(forBytes: cacheSizeBytes)
    }

    private var cacheLocationHint: String {
        if let root = RemoteEditCache.cacheRootURL() {
            return root.path
        }
        return "无法解析缓存目录路径"
    }

    private var statusColor: Color {
        statusIsError ? Color.red.opacity(0.9) : Color.secondary
    }

    private var editingBlockReason: String? {
        if remoteFileEditCoordinator.isBusyForAnySession {
            return "有文件正在同步，请稍后再清除缓存。"
        }
        if remoteFileEditCoordinator.hasActiveEditSessions {
            return "仍有远程文件在编辑中，请先关闭对应应用后再清除。"
        }
        return nil
    }

    private var canClearCache: Bool {
        cacheSizeBytes > 0 && !isMeasuring && !isClearing && editingBlockReason == nil
    }

    var body: some View {
        SettingCard {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("远程编辑缓存")
                        .font(.system(.headline).weight(.semibold))
                    Text("通过默认应用编辑远端文件时，会暂存到本机 Caches；保存后自动上传。清除后不影响远端文件。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("当前占用")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    Text(formattedCacheSize)
                        .font(.system(.title3, design: .monospaced).weight(.semibold))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)

                    if isMeasuring {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.leading, 4)
                    }

                    Spacer(minLength: 8)

                    Button("清除缓存") {
                        confirmAndClearCache()
                    }
                    .buttonStyle(.bordered)
                    .tint(Color.porterAccent)
                    .disabled(!canClearCache)
                    .porterPointingHandCursor()
                }

                Text(cacheLocationHint)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .truncationMode(.middle)

                if let statusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(statusColor)
                        .textSelection(.enabled)
                } else if let editingBlockReason {
                    Text(editingBlockReason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task {
            await refreshCacheSize()
        }
        .onReceive(NotificationCenter.default.publisher(for: .porterRemoteEditSyncSucceeded)) { _ in
            Task { await refreshCacheSize() }
        }
    }

    private func refreshCacheSize() async {
        guard !isMeasuring else { return }
        isMeasuring = true
        defer { isMeasuring = false }

        let measured = await Task.detached(priority: .utility) {
            RemoteEditCache.measuredSizeInBytes()
        }.value

        cacheSizeBytes = measured
    }

    private func confirmAndClearCache() {
        guard cacheSizeBytes > 0 else { return }

        let alert = NSAlert()
        alert.messageText = "清除远程编辑缓存？"
        alert.informativeText = "将删除约 \(formattedCacheSize) 的本地暂存文件。正在编辑且未保存的更改可能丢失；远端文件不受影响。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "清除")
        alert.addButton(withTitle: "取消")

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        Task {
            await clearCache()
        }
    }

    private func clearCache() async {
        isClearing = true
        statusMessage = nil
        statusIsError = false
        defer { isClearing = false }

        if remoteFileEditCoordinator.hasActiveEditSessions {
            remoteFileEditCoordinator.discardAllSessions()
        }

        do {
            _ = try await Task.detached(priority: .userInitiated) {
                try RemoteEditCache.clear()
            }.value
            cacheSizeBytes = 0
            statusMessage = "缓存已清除。"
            statusIsError = false
        } catch {
            statusMessage = "清除失败：\(error.localizedDescription)"
            statusIsError = true
            await refreshCacheSize()
        }
    }
}

struct DefaultDownloadDirectorySettingsCard: View {
    @EnvironmentObject private var downloadPreferences: DownloadPreferencesStore

    private var validationIssue: String? {
        downloadPreferences.validationIssue
    }

    private var statusText: String {
        if let validationIssue {
            return validationIssue
        }
        if downloadPreferences.hasConfiguredPath {
            return "已设置；远端浏览下载时将直接保存到此目录，不再弹出选择对话框。"
        }
        return "未设置；下载时每次选择保存目录。"
    }

    private var statusColor: Color {
        validationIssue != nil ? Color.red.opacity(0.9) : Color.secondary
    }

    var body: some View {
        SettingCard {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("默认下载目录")
                        .font(.system(.headline).weight(.semibold))
                    Text("留空则每次下载前选择目录；支持 ~ 展开。可填 Downloads 等常用路径。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                HStack(alignment: .center, spacing: 10) {
                    TextField("~/Downloads", text: $downloadPreferences.downloadDirectoryPath)
                        .textFieldStyle(.plain)
                        .font(.system(.body, design: .monospaced))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.porterCanvas.opacity(0.55))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color.porterBorder, lineWidth: 1)
                        )

                    Button("选择文件夹…") {
                        chooseDirectory()
                    }
                    .buttonStyle(.bordered)
                    .tint(Color.porterAccent)
                    .porterPointingHandCursor()

                    Button("清除") {
                        downloadPreferences.clear()
                    }
                    .buttonStyle(.bordered)
                    .disabled(!downloadPreferences.hasConfiguredPath)
                    .porterPointingHandCursor()
                }

                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(statusColor)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.title = "选择默认下载目录"
        panel.prompt = "使用此目录"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false

        let expanded = (downloadPreferences.downloadDirectoryPath as NSString).expandingTildeInPath
        if !expanded.isEmpty, FileManager.default.fileExists(atPath: expanded) {
            panel.directoryURL = URL(fileURLWithPath: expanded, isDirectory: true)
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }
        downloadPreferences.setDirectory(from: url)
    }
}

struct SSHConfigPathSettingsCard: View {
    @EnvironmentObject private var sshConfigPreferences: SSHConfigPreferencesStore
    @State private var isConfigFileImporterPresented = false

    private var validationIssue: String? {
        SSHConfigPathResolver.validationIssue(forConfigPath: sshConfigPreferences.configPath)
    }

    private var statusText: String {
        if let validationIssue {
            return validationIssue
        }
        if sshConfigPreferences.configFileExists {
            return "文件存在，修改后将自动刷新主机列表。"
        }
        return "文件不存在；请检查路径或点击「选择文件」。"
    }

    private var statusColor: Color {
        if validationIssue != nil || !sshConfigPreferences.configFileExists {
            return Color.red.opacity(0.9)
        }
        return Color.secondary
    }

    var body: some View {
        SettingCard {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("SSH 配置文件")
                        .font(.system(.headline).weight(.semibold))
                    Text("默认 \(SSHConfigPathResolver.defaultConfigPath)；支持 ~ 展开。Include 将相对于该文件所在目录解析。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                HStack(alignment: .center, spacing: 10) {
                    TextField(SSHConfigPathResolver.defaultConfigPath, text: $sshConfigPreferences.configPath)
                        .textFieldStyle(.plain)
                        .font(.system(.body, design: .monospaced))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.porterCanvas.opacity(0.55))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color.porterBorder, lineWidth: 1)
                        )

                    Button("选择文件…") {
                        isConfigFileImporterPresented = true
                    }
                    .buttonStyle(.bordered)
                    .tint(Color.porterAccent)
                    .porterPointingHandCursor()

                    Button("恢复默认") {
                        sshConfigPreferences.resetToDefault()
                    }
                    .buttonStyle(.bordered)
                    .porterPointingHandCursor()
                }

                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(statusColor)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fileImporter(
            isPresented: $isConfigFileImporterPresented,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                sshConfigPreferences.configPath = url.path
            }
        }
    }
}

struct AppearanceModePicker: View {
    @Binding var selection: AppAppearanceMode

    var body: some View {
        HStack(spacing: 2) {
            ForEach(AppAppearanceMode.allCases) { mode in
                Button {
                    selection = mode
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: mode.symbolName)
                            .font(.system(size: 17, weight: .medium))
                            .symbolRenderingMode(.monochrome)
                        Text(mode.title)
                            .font(.system(.body).weight(selection == mode ? .semibold : .regular))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .foregroundStyle(selection == mode ? Color.primary : Color.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity)
                    .background(
                        Capsule(style: .continuous)
                            .fill(selection == mode ? Color.porterSurface.opacity(0.95) : Color.clear)
                    )
                    .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(mode.title)
                .porterPointingHandCursor()
            }
        }
        .padding(3)
        .background(
            Capsule(style: .continuous)
                .fill(Color.porterSurface.opacity(0.48))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Color.porterBorder.opacity(0.5), lineWidth: 1)
        )
    }
}

struct UploadConflictStrategyPicker: View {
    @Binding var selection: UploadConflictStrategy
    @State private var hoveredStrategy: UploadConflictStrategy?

    var body: some View {
        VStack(spacing: 4) {
            ForEach(UploadConflictStrategy.allCases) { strategy in
                UploadConflictStrategyRow(
                    strategy: strategy,
                    isSelected: selection == strategy,
                    isHighlighted: selection == strategy || hoveredStrategy == strategy,
                    onSelect: { selection = strategy },
                    onHoverChange: { hovering in
                        withoutAnimation {
                            hoveredStrategy = hovering ? strategy : nil
                        }
                    }
                )
            }
        }
    }

    private func withoutAnimation(_ updates: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, updates)
    }
}

struct UploadConflictStrategyRow: View {
    let strategy: UploadConflictStrategy
    let isSelected: Bool
    let isHighlighted: Bool
    let onSelect: () -> Void
    let onHoverChange: (Bool) -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: strategy.symbolName)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(isSelected ? Color.porterAccent : Color.secondary)
                    .frame(width: 26, alignment: .center)

                VStack(alignment: .leading, spacing: 3) {
                    Text(strategy.title)
                        .font(.system(.body).weight(isSelected ? .semibold : .regular))
                        .foregroundStyle(Color.primary)

                    Text(strategy.subtitle)
                        .font(.footnote)
                        .foregroundStyle(Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isSelected ? Color.porterAccent : Color.secondary.opacity(0.45))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(isHighlighted ? Color.porterSurface.opacity(0.55) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.porterAccent.opacity(0.35) : Color.porterBorder.opacity(0.45),
                        lineWidth: 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityLabel("\(strategy.title)，\(strategy.subtitle)")
        .porterPointingHandCursor()
        .onHover(perform: onHoverChange)
    }
}

struct ExternalTerminalAppPicker: View {
    @Binding var selection: ExternalTerminalApp
    @State private var hoveredApp: ExternalTerminalApp?

    var body: some View {
        VStack(spacing: 4) {
            ForEach(ExternalTerminalApp.allCases) { app in
                ExternalTerminalAppRow(
                    app: app,
                    isSelected: selection == app,
                    isHighlighted: selection == app || hoveredApp == app,
                    onSelect: { selection = app },
                    onHoverChange: { hovering in
                        withoutAnimation {
                            hoveredApp = hovering ? app : nil
                        }
                    }
                )
            }
        }
    }

    private func withoutAnimation(_ updates: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, updates)
    }
}

struct ExternalTerminalAppRow: View {
    let app: ExternalTerminalApp
    let isSelected: Bool
    let isHighlighted: Bool
    let onSelect: () -> Void
    let onHoverChange: (Bool) -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: app.symbolName)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(isSelected ? Color.porterAccent : Color.secondary)
                    .frame(width: 26, alignment: .center)

                VStack(alignment: .leading, spacing: 3) {
                    Text(app.title)
                        .font(.system(.body).weight(isSelected ? .semibold : .regular))
                        .foregroundStyle(Color.primary)

                    Text(app.subtitle)
                        .font(.footnote)
                        .foregroundStyle(Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(trailingIconStyle)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowBackground)
            .overlay(rowStroke)
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityLabel("\(app.title)，\(app.subtitle)")
        .porterPointingHandCursor()
        .onHover(perform: onHoverChange)
    }

    private var trailingIconStyle: Color {
        isSelected ? Color.porterAccent : Color.secondary.opacity(0.45)
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(isHighlighted ? Color.porterSurface.opacity(0.55) : Color.clear)
    }

    private var rowStroke: some View {
        RoundedRectangle(cornerRadius: 11, style: .continuous)
            .strokeBorder(
                isSelected ? Color.porterAccent.opacity(0.35) : Color.porterBorder.opacity(0.45),
                lineWidth: 1
            )
    }
}

struct SettingCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(.horizontal, 22)
            .padding(.vertical, 20)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.porterSurface.opacity(0.92))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.porterBorder, lineWidth: 1)
            )
    }
}
