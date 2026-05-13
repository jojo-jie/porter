import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var appearanceSettings: AppearanceSettingsStore
    @StateObject private var model = AppModel()
    @State private var isFileImporterPresented = false
    @State private var isDropTargeted = false
    @State private var isRemoteBrowserPresented = false
    @State private var isSettingsPresented = false
    @State private var settingsSection: SettingsSection = .appearance
    @State private var sidebarSearchText = ""
    @State private var hoveredHostID: SSHHost.ID?
    @State private var refreshSpin = 0

    var body: some View {
        NavigationSplitView {
            Group {
                if isSettingsPresented {
                    SettingsSidebarColumn(selection: $settingsSection) {
                        isSettingsPresented = false
                    }
                    .navigationSplitViewColumnWidth(min: 220, ideal: 236, max: 360)
                } else {
                    sidebarView
                }
            }
            .navigationTitle("Porter")
        } detail: {
            Group {
                if isSettingsPresented {
                    SettingsDetailColumn(selection: $settingsSection)
                } else {
                    workspaceDetailColumn
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .overlay {
            if isRemoteBrowserPresented {
                remoteBrowserOverlay
                    .transition(.opacity)
            }
        }
        .tint(.porterAccent)
        .toolbarBackground(Color.porterCanvas, for: .windowToolbar)
        .toolbarBackground(.visible, for: .windowToolbar)
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                model.upload(urls: urls)
            }
        }
        .animation(.easeOut(duration: 0.16), value: isRemoteBrowserPresented)
        .onReceive(NotificationCenter.default.publisher(for: .porterShowSettings)) { _ in
            isRemoteBrowserPresented = false
            settingsSection = .appearance
            isSettingsPresented = true
        }
        .onChange(of: sidebarSearchText) { _, _ in
            syncSelectedHostWithFilteredHosts()
        }
        .onChange(of: model.hosts) { _, _ in
            syncSelectedHostWithFilteredHosts()
        }
    }

    private var workspaceDetailColumn: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                Color.porterCanvas.ignoresSafeArea()

                LinearGradient(
                    colors: [
                        Color.black.opacity(0.032),
                        Color.black.opacity(0.010),
                        Color.clear,
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 20)
                .blendMode(.plusDarker)
                .allowsHitTesting(false)
                .ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: true) {
                    detailView
                        .frame(
                            maxWidth: .infinity,
                            minHeight: detailContentMinimumHeight(for: proxy),
                            alignment: .topLeading
                        )
                        .padding(.horizontal, detailHorizontalPadding(for: proxy.size.width))
                        .padding(.top, proxy.safeAreaInsets.top + 20)
                        .padding(.bottom, 28)
                }
                .porterOverlayScrollIndicators()
                .scrollContentBackground(.hidden)
            }
        }
        .frame(minWidth: 760, minHeight: 520)
        .compositingGroup()
    }

    private var sidebarView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.tertiary)
                        .imageScale(.small)

                    TextField("搜索主机名称", text: $sidebarSearchText)
                        .textFieldStyle(.plain)

                    if !sidebarSearchText.isEmpty {
                        Button {
                            sidebarSearchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("清空搜索")
                        .porterPointingHandCursor()
                    }
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.porterSurface.opacity(0.85))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color.porterBorder, lineWidth: 1)
                )

                refreshHostsButton
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 6)

            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(spacing: 4) {
                    ForEach(filteredHosts) { host in
                        hostSidebarButton(for: host)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 4)
                .padding(.bottom, 10)
            }
            .overlay {
                if filteredHosts.isEmpty {
                    ContentUnavailableView(
                        sidebarSearchText.isEmpty ? "没有可用主机" : "未找到匹配主机",
                        systemImage: "magnifyingglass",
                        description: Text(sidebarSearchText.isEmpty ? "请检查 ~/.ssh/config。" : "请尝试其他主机名称。")
                    )
                    .foregroundStyle(.secondary)
                }
            }
            .porterOverlayScrollIndicators()
        }
        .background(Color.porterSidebar)
        .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 360)
    }

    private func hostSidebarButton(for host: SSHHost) -> some View {
        let isHighlighted = model.selectedHostID == host.id || hoveredHostID == host.id

        return Button {
            model.selectedHostID = host.id
        } label: {
            HostSidebarRow(host: host)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isHighlighted ? Color.porterSidebarRowHighlight : Color.clear)
                )
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering in
            hoveredHostID = isHovering ? host.id : nil
        }
        .porterPointingHandCursor()
    }

    private var refreshHostsButton: some View {
        Button {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                refreshSpin += 1
            }
            model.refreshHosts()
        } label: {
            Image(systemName: "arrow.clockwise")
                .imageScale(.medium)
                .rotationEffect(.degrees(Double(refreshSpin) * 360))
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
        .help("重新读取 ~/.ssh/config 中的 Host 列表")
        .accessibilityLabel("重新读取 SSH 配置")
        .porterPointingHandCursor()
    }

    private var filteredHosts: [SSHHost] {
        let query = sidebarSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return model.hosts }
        return model.hosts.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    private var remoteBrowserOverlay: some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture {
                    isRemoteBrowserPresented = false
                }
                .porterPointingHandCursor()

            if let host = model.selectedHost {
                RemoteDirectoryBrowserContainer(
                    hostAlias: host.name,
                    path: model.pathBinding(for: host),
                    onDismiss: {
                        isRemoteBrowserPresented = false
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .onTapGesture {}
                .shadow(color: .black.opacity(0.22), radius: 24, x: 0, y: 14)
            } else {
                Text("未选择主机")
                    .padding(24)
                    .background(Color.porterCanvas, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: .black.opacity(0.16), radius: 18, x: 0, y: 10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func syncSelectedHostWithFilteredHosts() {
        let hosts = filteredHosts
        guard !hosts.contains(where: { $0.id == model.selectedHostID }) else { return }
        model.selectedHostID = hosts.first?.id
    }

    private func detailHorizontalPadding(for width: CGFloat) -> CGFloat {
        if width < 460 { return 18 }
        if width < 700 { return 28 }
        return 40
    }

    private func detailContentMinimumHeight(for proxy: GeometryProxy) -> CGFloat {
        max(0, proxy.size.height - proxy.safeAreaInsets.top - 48)
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

                ViewThatFits(in: .horizontal) {
                    actionButtons(axis: .horizontal, host: host)
                    actionButtons(axis: .vertical, host: host)
                }

                Spacer(minLength: 0)

                if shouldShowStatusRow {
                    StatusRow(log: model.log, isUploading: model.isUploading)
                }
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

    private var shouldShowStatusRow: Bool {
        model.isUploading || !model.log.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func actionButtons(axis: Axis, host: SSHHost) -> some View {
        let stack = axis == .horizontal ? AnyLayout(HStackLayout(spacing: 10)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
        return stack {
            Button {
                isFileImporterPresented = true
            } label: {
                Label("选择文件上传", systemImage: "tray.and.arrow.up")
                    .frame(maxWidth: axis == .vertical ? .infinity : nil, alignment: .center)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.isUploading)
            .porterPointingHandCursor(!model.isUploading)

            Button {
                openSSHTest(host: host.name)
            } label: {
                Label("打开终端", systemImage: "terminal")
                    .frame(maxWidth: axis == .vertical ? .infinity : nil, alignment: .center)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(model.isUploading)
            .porterPointingHandCursor(!model.isUploading)

            if axis == .horizontal {
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        var errorInfo: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&errorInfo)

        if let errorInfo {
            let message = errorInfo[NSAppleScript.errorMessage] as? String
                ?? "请检查“系统设置 > 隐私与安全性 > 自动化”中 Porter 控制 Terminal 的权限。"
            showTerminalOpenError(message)
        }
    }

    private func localShellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private func appleScriptQuoted(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
    }

    private func showTerminalOpenError(_ detail: String) {
        let alert = NSAlert()
        alert.messageText = "无法打开终端"
        alert.informativeText = detail
        alert.alertStyle = .warning
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}

private final class LockedURLStore: @unchecked Sendable {
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
