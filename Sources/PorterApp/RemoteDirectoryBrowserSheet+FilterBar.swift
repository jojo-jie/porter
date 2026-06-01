import AppKit
import Foundation
import PorterCore
import SwiftUI

extension RemoteDirectoryBrowserSheet {
    var filterBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.tertiary)
                    .imageScale(.small)

                TextField("筛选当前目录中的文件或文件夹", text: $filterText)
                    .textFieldStyle(.plain)
                    .frame(maxWidth: .infinity)

                if !filterText.isEmpty {
                    Button {
                        filterText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("清空筛选")
                    .porterPointingHandCursor()
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.porterSurface.opacity(0.85))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.porterBorder, lineWidth: 1)
            )

            filterToolbarIconButton(
                systemName: "folder.badge.plus",
                help: "在当前远端目录新建文件夹",
                accessibilityLabel: "新建文件夹"
            ) {
                beginNewItem(.folder)
            }

            filterToolbarIconButton(
                systemName: "doc.badge.plus",
                help: "在当前远端目录新建空文件",
                accessibilityLabel: "新建空文件"
            ) {
                beginNewItem(.file)
            }

            Button {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                    listRefreshSpin += 1
                }
                Task { await browser.refreshList(force: true) }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .imageScale(.medium)
                    .rotationEffect(.degrees(Double(listRefreshSpin) * 360))
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
            .help("重新加载当前远端目录列表")
            .accessibilityLabel("刷新目录列表")
            .disabled(browser.isLoading)
            .porterPointingHandCursor(!browser.isLoading)
        }
    }

    var canMutateCurrentDirectory: Bool {
        !browser.isLoading && browser.errorMessage == nil && !isCreatingNewItem
    }

    @ViewBuilder
    func filterToolbarIconButton(
        systemName: String,
        help: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .imageScale(.medium)
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
        .help(help)
        .accessibilityLabel(accessibilityLabel)
        .disabled(!canMutateCurrentDirectory)
        .porterPointingHandCursor(canMutateCurrentDirectory)
    }
}
