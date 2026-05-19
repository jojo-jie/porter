import SwiftUI

struct RemoteListingRow: View, Equatable {
    let entry: RemoteListingEntry
    let isSelected: Bool
    let isHovered: Bool
    let isDownloading: Bool
    let isEditing: Bool
    let isRenaming: Bool
    let isDeleting: Bool
    let showsEditAction: Bool
    let onRowTap: () -> Void
    let onHoverChange: (Bool) -> Void
    let onDownload: () -> Void
    let onEdit: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void

    private var isBusy: Bool {
        isDownloading || isEditing || isRenaming || isDeleting
    }

    private var isHighlighted: Bool {
        isSelected || isHovered
    }

    private var shouldShowActions: Bool {
        entry.name != ".." && (isHovered || isBusy)
    }

    var body: some View {
        HStack(spacing: 0) {
            rowContent
                .contentShape(Rectangle())
                .frame(maxWidth: .infinity, alignment: .leading)
                .onTapGesture(perform: onRowTap)

            Group {
                if shouldShowActions {
                    PorterListingActionStrip(
                        entryName: entry.name,
                        showsEdit: showsEditAction,
                        isDownloading: isDownloading,
                        isEditing: isEditing,
                        isRenaming: isRenaming,
                        isDeleting: isDeleting,
                        isDisabled: isBusy,
                        onEdit: onEdit,
                        onDownload: onDownload,
                        onRename: onRename,
                        onDelete: onDelete
                    )
                }
            }
            .frame(width: showsEditAction ? 148 : 118, alignment: .center)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isHighlighted ? Color.porterSidebarRowHighlight : Color.clear)
        )
        .contentShape(Rectangle())
        .transaction { $0.disablesAnimations = true }
        .onHover(perform: onHoverChange)
    }

    private var rowContent: some View {
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
    }

    nonisolated static func == (lhs: RemoteListingRow, rhs: RemoteListingRow) -> Bool {
        lhs.entry == rhs.entry
            && lhs.isSelected == rhs.isSelected
            && lhs.isHovered == rhs.isHovered
            && lhs.isDownloading == rhs.isDownloading
            && lhs.isEditing == rhs.isEditing
            && lhs.isRenaming == rhs.isRenaming
            && lhs.isDeleting == rhs.isDeleting
            && lhs.showsEditAction == rhs.showsEditAction
    }
}
