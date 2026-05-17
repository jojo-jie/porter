import AppKit
import SwiftUI

struct HostSidebarRow: View {
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

struct HostDetailHeader: View {
    let host: SSHHost

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 12) {
                    titleText
                    sshBadge
                }

                VStack(alignment: .leading, spacing: 8) {
                    titleText
                    sshBadge
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 0) {
                    MetaCell(label: "用户", value: host.user ?? "默认")
                        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

                    metaDivider

                    MetaCell(label: "地址", value: host.hostName ?? host.name)
                        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

                    metaDivider

                    MetaCell(label: "端口", value: host.port ?? "22")
                        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: 12) {
                    MetaCell(label: "用户", value: host.user ?? "默认")
                    MetaCell(label: "地址", value: host.hostName ?? host.name)
                    MetaCell(label: "端口", value: host.port ?? "22")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var titleText: some View {
        Text(host.name)
            .font(.system(size: 34, weight: .semibold))
            .foregroundStyle(.primary)
            .textSelection(.enabled)
            .lineLimit(2)
            .minimumScaleFactor(0.65)
            .truncationMode(.middle)
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var sshBadge: some View {
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
            .fixedSize(horizontal: true, vertical: false)
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

struct PathField: View {
    @Binding var text: String
    @Binding var isRemoteBrowserPresented: Bool
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("默认远程目录")
                    .font(.system(.subheadline).weight(.semibold))
                    .foregroundStyle(.primary)
                Text("设置后即可上传文件")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

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
                .porterPointingHandCursor()
            }

            Text("可直接输入路径，或通过右侧按钮连接远端浏览；上传走 SFTP，SSH 连接使用设置中指定的配置文件。")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}

struct TransientNotice: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let kind: Kind

    enum Kind: Equatable {
        case success
        case error
    }

    static func kind(forConnectionTestResult result: String) -> Kind {
        if result.contains("失败") || result.contains("错误") { return .error }
        return .success
    }
}

struct PorterTransientToast: View {
    let notice: TransientNotice

    private var symbolName: String {
        switch notice.kind {
        case .success: return "checkmark.circle.fill"
        case .error: return "xmark.circle.fill"
        }
    }

    private var accentColor: Color {
        switch notice.kind {
        case .success: return Color.green.opacity(0.92)
        case .error: return Color.red.opacity(0.92)
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbolName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(accentColor)
                .symbolRenderingMode(.hierarchical)

            Text(notice.message)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: 420, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.porterSurface.opacity(0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.porterBorder, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.14), radius: 12, x: 0, y: 6)
        .accessibilityLabel(notice.message)
    }
}

struct StatusRow: View {
    let log: String
    let isUploading: Bool

    private enum Kind { case idle, progress, success, error }

    private var kind: Kind {
        if isUploading { return .progress }
        if log.contains("失败") || log.contains("错误") { return .error }
        if log.contains("完成") || log.contains("连接正常") { return .success }
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
        .porterPointingHandCursor(!isUploading)
    }
}

extension View {
    /// 按钮型操作悬停时显示手型指针（`NSCursor.pointingHand`）。
    func porterPointingHandCursor(_ enabled: Bool = true) -> some View {
        modifier(PorterPointingHandCursorModifier(enabled: enabled))
    }
}

private struct PorterPointingHandCursorModifier: ViewModifier {
    let enabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content.overlay {
                PorterCursorArea(cursor: .pointingHand)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
            }
        } else {
            content
        }
    }
}

/// Remote directory row actions — grouped capsule toolbar (see DESIGN.md).
enum PorterListingActionKind: CaseIterable {
    case edit
    case download
    case rename
    case delete

    var symbolName: String {
        switch self {
        case .edit: "square.and.pencil"
        case .download: "arrow.down.circle"
        case .rename: "pencil.line"
        case .delete: "trash"
        }
    }

    var help: String {
        switch self {
        case .edit: "在本机默认应用中打开；保存后自动上传"
        case .download: "下载到本地目录"
        case .rename: "重命名远端文件或文件夹"
        case .delete: "删除远端文件或文件夹"
        }
    }

    var accessibilityVerb: String {
        switch self {
        case .edit: "编辑"
        case .download: "下载"
        case .rename: "重命名"
        case .delete: "删除"
        }
    }

    fileprivate var isDestructive: Bool { self == .delete }
}

/// Hover-revealed action strip for a remote listing row.
struct PorterListingActionStrip: View {
    let entryName: String
    let showsEdit: Bool
    let isDownloading: Bool
    let isEditing: Bool
    let isRenaming: Bool
    let isDeleting: Bool
    let isDisabled: Bool
    let onEdit: () -> Void
    let onDownload: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void

    private var visibleKinds: [PorterListingActionKind] {
        var kinds: [PorterListingActionKind] = []
        if showsEdit { kinds.append(.edit) }
        kinds.append(contentsOf: [.download, .rename, .delete])
        return kinds
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(visibleKinds.enumerated()), id: \.offset) { index, kind in
                if index > 0 {
                    PorterListingActionDivider(isEmphasized: kind.isDestructive)
                }
                PorterListingActionCell(
                    kind: kind,
                    entryName: entryName,
                    isBusy: busy(for: kind),
                    isDisabled: isDisabled,
                    action: action(for: kind)
                )
            }
        }
        .padding(.horizontal, 3)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.porterSurface.opacity(0.94))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.porterBorder, lineWidth: 1)
        )
        .fixedSize()
    }

    private func busy(for kind: PorterListingActionKind) -> Bool {
        switch kind {
        case .edit: isEditing
        case .download: isDownloading
        case .rename: isRenaming
        case .delete: isDeleting
        }
    }

    private func action(for kind: PorterListingActionKind) -> () -> Void {
        switch kind {
        case .edit: onEdit
        case .download: onDownload
        case .rename: onRename
        case .delete: onDelete
        }
    }
}

private struct PorterListingActionDivider: View {
    var isEmphasized: Bool = false

    var body: some View {
        Rectangle()
            .fill(isEmphasized ? Color.red.opacity(0.18) : Color.porterBorder)
            .frame(width: 1, height: 18)
            .padding(.horizontal, 1)
    }
}

private struct PorterListingActionCell: View {
    let kind: PorterListingActionKind
    let entryName: String
    let isBusy: Bool
    let isDisabled: Bool
    let action: () -> Void

    @State private var isHovering = false

    private var iconColor: Color {
        if kind.isDestructive {
            return isHovering ? Color.red.opacity(0.92) : Color.secondary.opacity(0.72)
        }
        if isHovering {
            return Color.porterAccent
        }
        return Color.secondary.opacity(0.88)
    }

    private var cellFill: Color {
        if kind.isDestructive {
            return isHovering ? Color.red.opacity(0.12) : Color.clear
        }
        return isHovering ? Color.porterAccent.opacity(0.10) : Color.clear
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(cellFill)
                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.58)
                } else {
                    Image(systemName: kind.symbolName)
                        .font(.system(size: 13, weight: .medium))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(iconColor)
                }
            }
            .frame(width: 30, height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(kind.help)
        .accessibilityLabel("\(kind.accessibilityVerb) \(entryName)")
        .disabled(isDisabled)
        .porterPointingHandCursor(!isDisabled)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}

private struct PorterCursorArea: NSViewRepresentable {
    let cursor: NSCursor

    func makeNSView(context: Context) -> CursorView {
        let view = CursorView()
        view.cursor = cursor
        return view
    }

    func updateNSView(_ nsView: CursorView, context: Context) {
        nsView.cursor = cursor
    }

    final class CursorView: NSView {
        var cursor: NSCursor = .arrow {
            didSet {
                window?.invalidateCursorRects(for: self)
            }
        }

        override func resetCursorRects() {
            super.resetCursorRects()
            addCursorRect(bounds, cursor: cursor)
        }

        override func layout() {
            super.layout()
            window?.invalidateCursorRects(for: self)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.invalidateCursorRects(for: self)
        }
    }
}
