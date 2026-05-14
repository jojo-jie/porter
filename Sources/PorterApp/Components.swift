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

            Text("可直接输入路径，或通过右侧按钮连接远端浏览；上传时路径将交给 scp，连接仍走 ~/.ssh/config。")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}

struct StatusRow: View {
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
