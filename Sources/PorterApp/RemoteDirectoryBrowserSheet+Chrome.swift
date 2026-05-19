import AppKit
import Foundation
import PorterCore
import SwiftUI

extension RemoteDirectoryBrowserSheet {
    var sheetHeader: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("选择远程目录")
                    .font(.system(.headline).weight(.semibold))
                Text(browser.hostAlias)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .porterPointingHandCursor()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    var navigationBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 2) {
                Button {
                    browser.goBack()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.borderless)
                .disabled(!browser.canGoBack || browser.isLoading)
                .help("后退")
                .porterPointingHandCursor(browser.canGoBack && !browser.isLoading)

                Button {
                    browser.goForward()
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.borderless)
                .disabled(!browser.canGoForward || browser.isLoading)
                .help("前进")
                .porterPointingHandCursor(browser.canGoForward && !browser.isLoading)
            }
            .foregroundStyle(.primary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(Color.porterAccent)
                        .imageScale(.small)
                    ForEach(Array(browser.segments.enumerated()), id: \.offset) { index, segment in
                        if index > 0 {
                            Image(systemName: "chevron.compact.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        Button {
                            browser.goToBreadcrumb(index: index)
                        } label: {
                            Text(displaySegment(segment, isFirst: index == 0))
                                .font(.system(.subheadline, design: .monospaced))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(index == browser.segments.count - 1 ? Color.primary : Color.porterAccent)
                        .disabled(browser.isLoading)
                        .porterPointingHandCursor(!browser.isLoading)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    func displaySegment(_ segment: String, isFirst: Bool) -> String {
        if isFirst, segment == "/" { return "/" }
        if isFirst, segment == "~" { return "~" }
        return segment
    }
}
