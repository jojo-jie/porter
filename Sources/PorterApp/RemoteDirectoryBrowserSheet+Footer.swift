import AppKit
import Foundation
import PorterCore
import SwiftUI

extension RemoteDirectoryBrowserSheet {
    var footerBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("当前路径")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.tertiary)
                Text(browser.resolvedPWD.isEmpty ? browser.currentLogicalPath : browser.resolvedPWD)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)

                if let footerStatusMessage {
                    Text(footerStatusMessage)
                        .font(.caption)
                        .foregroundStyle(footerStatusMessage.contains("失败") ? Color.red.opacity(0.9) : Color.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button("取消", role: .cancel) {
                onDismiss()
            }
            .keyboardShortcut(.cancelAction)
            .porterPointingHandCursor()

            Button("使用此目录") {
                let choice = browser.resolvedPWD.isEmpty ? browser.currentLogicalPath : browser.resolvedPWD
                boundPath = choice
                onDismiss()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .tint(Color.porterAccent)
            .disabled(browser.isLoading || browser.errorMessage != nil)
            .porterPointingHandCursor(!browser.isLoading && browser.errorMessage == nil)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}
