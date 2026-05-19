import AppKit
import Foundation
import PorterCore
import SwiftUI

extension RemoteDirectoryBrowserSheet {
    func newItemPromptOverlay(_ prompt: NewItemPrompt) -> some View {
        let isFolder = prompt.kind == .folder
        let fieldLabel = isFolder ? "文件夹名称 *" : "文件名称 *"
        let helpText = isFolder
            ? "将在当前远端目录下创建文件夹。若同名路径已存在，则不会覆盖。"
            : "将在当前远端目录下创建空文件。若同名路径已存在，则不会覆盖。"

        return ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    cancelNewItemPrompt()
                }

            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    VStack(alignment: .leading, spacing: 16) {
                        newItemPromptField(label: fieldLabel)

                        Text(helpText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        if let newItemPromptErrorText {
                            Text(newItemPromptErrorText)
                                .font(.caption)
                                .foregroundStyle(Color.red)
                                .fixedSize(horizontal: false, vertical: true)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 34)
                    .padding(.bottom, 24)

                    Button {
                        cancelNewItemPrompt()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 12)
                    .padding(.trailing, 12)
                    .accessibilityLabel("关闭新建")
                    .porterPointingHandCursor()
                }

                HStack(spacing: 10) {
                    Spacer()
                    Button("取消", role: .cancel) {
                        cancelNewItemPrompt()
                    }
                    .keyboardShortcut(.cancelAction)
                    .porterPointingHandCursor()

                    Button("确认") {
                        continueNewItemPrompt(prompt)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.porterAccent)
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
                    .porterPointingHandCursor()
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .frame(width: 560)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.porterSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.porterBorder, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.20), radius: 22, x: 0, y: 12)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .onTapGesture {}
            .modifier(PorterRenameCardShakeEffect(amplitude: 12, phase: newItemCardShakePhase))
            .onAppear {
                isNewItemPromptFocused = true
            }
            .animation(.easeOut(duration: 0.18), value: newItemPromptErrorText)
        }
    }

    func newItemPromptField(label: String) -> some View {
        let borderAccent = newItemPromptErrorText == nil ? Color.porterAccent : Color.red

        return VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(.caption).weight(.medium))
                .foregroundStyle(borderAccent)
                .padding(.horizontal, 6)
                .background(Color.porterSurface)
                .offset(x: 12, y: 8)
                .zIndex(1)

            TextField("", text: $newItemDraftName)
                .textFieldStyle(.plain)
                .font(.system(size: 16, design: .monospaced))
                .focused($isNewItemPromptFocused)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.porterSurface.opacity(0.85))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(borderAccent.opacity(newItemPromptErrorText == nil ? 0.55 : 0.85), lineWidth: newItemPromptErrorText == nil ? 1.5 : 2)
                )
                .onChange(of: newItemDraftName) { _, _ in
                    newItemPromptErrorText = nil
                }
        }
    }

    func renamePromptOverlay(_ prompt: RenamePrompt) -> some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    cancelRenamePrompt()
                }

            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    VStack(alignment: .leading, spacing: 16) {
                        renamePromptField

                        Text("请输入新的文件或文件夹名称。点击下方「确认」后，远端会立即使用该名称。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        if let renamePromptErrorText {
                            Text(renamePromptErrorText)
                                .font(.caption)
                                .foregroundStyle(Color.red)
                                .fixedSize(horizontal: false, vertical: true)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 34)
                    .padding(.bottom, 24)

                    Button {
                        cancelRenamePrompt()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 12)
                    .padding(.trailing, 12)
                    .accessibilityLabel("关闭重命名")
                    .porterPointingHandCursor()
                }

                HStack(spacing: 10) {
                    Spacer()
                    Button("取消", role: .cancel) {
                        cancelRenamePrompt()
                    }
                    .keyboardShortcut(.cancelAction)
                    .porterPointingHandCursor()

                    Button("确认") {
                        continueRenamePrompt(prompt)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.porterAccent)
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
                    .porterPointingHandCursor()
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .frame(width: 560)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.porterSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.porterBorder, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.20), radius: 22, x: 0, y: 12)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .onTapGesture {}
            .modifier(PorterRenameCardShakeEffect(amplitude: 12, phase: renameCardShakePhase))
            .onAppear {
                isRenamePromptFocused = true
            }
            .animation(.easeOut(duration: 0.18), value: renamePromptErrorText)
        }
    }

    var renamePromptField: some View {
        let borderAccent = renamePromptErrorText == nil ? Color.porterAccent : Color.red

        return VStack(alignment: .leading, spacing: 4) {
            Text("新名称 *")
                .font(.system(.caption).weight(.medium))
                .foregroundStyle(borderAccent)
                .padding(.horizontal, 6)
                .background(Color.porterSurface)
                .offset(x: 12, y: 8)
                .zIndex(1)

            TextField("", text: $renameDraftName)
                .textFieldStyle(.plain)
                .font(.system(size: 16, design: .monospaced))
                .focused($isRenamePromptFocused)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.porterSurface.opacity(0.85))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(borderAccent.opacity(renamePromptErrorText == nil ? 0.55 : 0.85), lineWidth: renamePromptErrorText == nil ? 1.5 : 2)
                )
                .onChange(of: renameDraftName) { _, _ in
                    renamePromptErrorText = nil
                }
        }
    }

    func deleteConfirmationOverlay(_ confirmation: DeleteConfirmation) -> some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    cancelDeleteConfirmation()
                }

            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    VStack(alignment: .leading, spacing: 16) {
                        deleteTargetField(confirmation.entry)

                        Text(
                            confirmation.entry.isDirectory
                                ? "将删除整个文件夹及其中的全部内容。此操作无法在 Porter 内撤销。"
                                : "远端文件将立即被删除。此操作无法在 Porter 内撤销。"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 34)
                    .padding(.bottom, 24)

                    Button {
                        cancelDeleteConfirmation()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 12)
                    .padding(.trailing, 12)
                    .accessibilityLabel("关闭删除确认")
                    .porterPointingHandCursor()
                }

                HStack(spacing: 10) {
                    Spacer()
                    Button("取消", role: .cancel) {
                        cancelDeleteConfirmation()
                    }
                    .keyboardShortcut(.cancelAction)
                    .porterPointingHandCursor()

                    Button("删除", role: .destructive) {
                        confirmDelete(confirmation)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .porterPointingHandCursor()
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .frame(width: 560)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.porterSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.porterBorder, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.20), radius: 22, x: 0, y: 12)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .onTapGesture {}
        }
    }

    func deleteTargetField(_ entry: RemoteListingEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("将删除 *")
                .font(.system(.caption).weight(.medium))
                .foregroundStyle(Color.red.opacity(0.88))
                .padding(.horizontal, 6)
                .background(Color.porterSurface)
                .offset(x: 12, y: 8)
                .zIndex(1)

            Text(entry.name)
                .font(.system(size: 16, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.porterSurface.opacity(0.85))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.red.opacity(0.45), lineWidth: 1.5)
                )
        }
    }

}

/// Horizontal damped shake driven by animating ``phase`` from 0 → 1.
private struct PorterRenameCardShakeEffect: GeometryEffect {
    var amplitude: CGFloat
    var phase: CGFloat

    var animatableData: CGFloat {
        get { phase }
        set { phase = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let damping = 1.0 - phase
        let offset = amplitude * damping * sin(phase * CGFloat.pi * 7)
        return ProjectionTransform(CGAffineTransform(translationX: offset, y: 0))
    }
}

