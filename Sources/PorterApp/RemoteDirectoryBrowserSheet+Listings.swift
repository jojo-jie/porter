import AppKit
import Foundation
import PorterCore
import SwiftUI

extension RemoteDirectoryBrowserSheet {
    var displayedEntries: [RemoteListingEntry] {
        let query = filterText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return browser.entries }
        return browser.entries.filter { entry in
            entry.name == ".." || entry.name.localizedCaseInsensitiveContains(query)
        }
    }

    var listingsTable: some View {
        ZStack {
            if let err = browser.errorMessage {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.orange.opacity(0.9))
                    Text(err)
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding(24)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    tableHeaderRow

                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(displayedEntries) { entry in
                                listingRow(entry)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .transaction { $0.disablesAnimations = true }
                    }
                    .porterOverlayScrollIndicators()
                }
            }

            if !browser.isLoading, browser.errorMessage == nil, displayedEntries.isEmpty {
                ContentUnavailableView(
                    "未找到匹配项目",
                    systemImage: "magnifyingglass",
                    description: Text("请尝试其他筛选关键词。")
                )
                .foregroundStyle(.secondary)
            }

            if browser.isLoading {
                ZStack {
                    Color.porterCanvas.opacity(0.45)
                    ProgressView()
                        .controlSize(.regular)
                }
                .allowsHitTesting(false)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.porterSurface.opacity(0.45))
    }

    var tableHeaderRow: some View {
        HStack(spacing: 0) {
            Text("名称")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("修改时间")
                .frame(width: 150, alignment: .leading)
            Text("大小")
                .frame(width: 88, alignment: .trailing)
            Text("类型")
                .frame(width: 72, alignment: .leading)
            Text("操作")
                .frame(width: 156, alignment: .center)
        }
        .font(.system(.caption2).weight(.semibold))
        .foregroundStyle(.tertiary)
        .textCase(nil)
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(Color.porterSurface.opacity(0.9))
        .porterPointingHandCursor(false)
    }

    func listingRow(_ entry: RemoteListingEntry) -> some View {
        let remotePath = browser.remotePath(for: entry)
        return RemoteListingRow(
            entry: entry,
            isSelected: selectedName == entry.name,
            isHovered: hoveredName == entry.name,
            isDownloading: downloadingNames.contains(entry.name),
            isEditing: remoteFileEditCoordinator.isBusy(host: browser.hostAlias, remotePath: remotePath),
            isRenaming: renamingNames.contains(entry.name),
            isDeleting: deletingNames.contains(entry.name),
            showsEditAction: showsEditAction(for: entry),
            onRowTap: {
                handleListingRowTap(entry)
            },
            onHoverChange: { isHovering in
                withoutAnimation {
                    hoveredName = isHovering ? entry.name : (hoveredName == entry.name ? nil : hoveredName)
                }
            },
            onDownload: {
                chooseDestinationAndDownload(entry)
            },
            onEdit: {
                beginRemoteEdit(entry)
            },
            onRename: {
                beginRename(entry)
            },
            onDelete: {
                beginDelete(entry)
            }
        )
        .equatable()
    }

    func showsEditAction(for entry: RemoteListingEntry) -> Bool {
        entry.name != ".." && !entry.isDirectory
    }

    func selectListingEntry(_ entry: RemoteListingEntry) {
        withoutAnimation {
            selectedName = entry.name
        }
    }

    func handleListingRowTap(_ entry: RemoteListingEntry) {
        selectListingEntry(entry)

        if rowClickTracker.registerClick(on: entry.name) {
            navigateIntoListingEntry(entry)
        }
    }

    func navigateIntoListingEntry(_ entry: RemoteListingEntry) {
        guard !browser.isLoading else { return }
        withoutAnimation {
            selectedName = entry.name
        }
        if entry.name == ".." {
            browser.goToParent()
        } else if entry.navigable, entry.isDirectory {
            browser.openEntry(entry)
        }
    }
}
