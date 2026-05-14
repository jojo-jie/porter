import AppKit
import SwiftUI

enum AppAppearanceMode: String, CaseIterable, Identifiable {
    case light
    case dark
    case system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light: return "浅色"
        case .dark: return "深色"
        case .system: return "系统"
        }
    }

    var symbolName: String {
        switch self {
        case .light: return "sun.max"
        case .dark: return "moon"
        case .system: return "macbook"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        case .system: return nil
        }
    }
}

@MainActor
final class AppearanceSettingsStore: ObservableObject {
    private let defaultsKey = "porter.appearanceMode"

    @Published var mode: AppAppearanceMode {
        didSet {
            UserDefaults.standard.set(mode.rawValue, forKey: defaultsKey)
            apply()
        }
    }

    init() {
        let rawValue = UserDefaults.standard.string(forKey: defaultsKey)
        mode = rawValue.flatMap(AppAppearanceMode.init(rawValue:)) ?? .system
        apply()
    }

    private func apply() {
        let appearance = mode.nsAppearance
        NSApplication.shared.appearance = appearance
        NSApplication.shared.windows.forEach { window in
            window.appearance = appearance
        }
    }
}

enum SettingsSection: String, CaseIterable, Identifiable {
    case appearance
    case configuration

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appearance: return "外观"
        case .configuration: return "配置"
        }
    }

    var subtitle: String {
        switch self {
        case .appearance: return "调整 Porter 的主题外观。"
        case .configuration: return "查看当前配置来源和主窗口中的连接设置说明。"
        }
    }

    var symbolName: String {
        switch self {
        case .appearance: return "sun.max"
        case .configuration: return "gearshape"
        }
    }
}

/// 嵌入 `NavigationSplitView` 左栏；与主页共用同一导航结构，避免切换时窗口工具栏重算导致抖动。
struct SettingsSidebarColumn: View {
    @Binding var selection: SettingsSection
    @State private var isBackButtonHovered = false
    @State private var hoveredSection: SettingsSection?

    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                onDismiss()
            } label: {
                Label("返回应用", systemImage: "arrow.left")
                    .font(.system(.body).weight(.medium))
                    .imageScale(.medium)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(isBackButtonHovered ? Color.porterSidebarRowHighlight : Color.clear)
                    )
                    .animation(nil, value: isBackButtonHovered)
                    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .keyboardShortcut(.cancelAction)
            .onHover { isHovering in
                withoutAnimation {
                    isBackButtonHovered = isHovering
                }
            }

            Rectangle()
                .fill(Color.porterBorder.opacity(0.7))
                .frame(height: 1)
                .padding(.vertical, 12)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(SettingsSection.allCases) { section in
                    sidebarButton(for: section)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.porterSidebar)
    }

    private func sidebarButton(for section: SettingsSection) -> some View {
        let isHighlighted = selection == section || hoveredSection == section

        return Button {
            withoutAnimation {
                selection = section
            }
        } label: {
            Label(section.title, systemImage: section.symbolName)
                .font(.system(.body).weight(selection == section ? .semibold : .regular))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isHighlighted ? Color.porterSidebarRowHighlight : Color.clear)
                )
                .animation(nil, value: isHighlighted)
        }
        .buttonStyle(.plain)
        .foregroundStyle(selection == section ? Color.primary : Color.secondary)
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onHover { isHovering in
            withoutAnimation {
                hoveredSection = isHovering ? section : nil
            }
        }
    }

    private func withoutAnimation(_ updates: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, updates)
    }
}

struct SettingsDetailColumn: View {
    @EnvironmentObject private var appearanceSettings: AppearanceSettingsStore
    @Binding var selection: SettingsSection

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 22) {
                contentHeader

                switch selection {
                case .appearance:
                    appearancePane
                case .configuration:
                    configurationPane
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: 720, alignment: .topLeading)
            .padding(.horizontal, 48)
            .padding(.top, 44)
            .padding(.bottom, 48)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.porterCanvas)
        .porterOverlayScrollIndicators()
        .scrollContentBackground(.hidden)
    }

    private var contentHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(selection.title)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.primary)

            Text(selection.subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var appearancePane: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingCard {
                HStack(alignment: .center, spacing: 24) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("主题")
                            .font(.system(.headline).weight(.semibold))
                            .foregroundStyle(.primary)

                        Text("使用浅色、深色，或匹配系统设置")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .layoutPriority(1)

                    Spacer(minLength: 20)

                    AppearanceModePicker(selection: $appearanceSettings.mode)
                        .frame(width: 320)
                }
            }

            Spacer(minLength: 0)
        }
    }

    private var configurationPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingCard {
                VStack(alignment: .leading, spacing: 6) {
                    Text("配置")
                        .font(.system(.headline).weight(.semibold))
                    Text("主机与路径配置会继续使用主窗口中的 ~/.ssh/config 与远程目录设置。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer(minLength: 0)
        }
    }
}

private struct AppearanceModePicker: View {
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

private struct SettingCard<Content: View>: View {
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
