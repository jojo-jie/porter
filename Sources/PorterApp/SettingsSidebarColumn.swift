import SwiftUI

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
