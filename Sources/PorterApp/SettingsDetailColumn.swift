import PorterCore
import SwiftUI

struct SettingsDetailColumn: View {
    @EnvironmentObject private var appearanceSettings: AppearanceSettingsStore
    @EnvironmentObject private var uploadPreferences: UploadPreferencesStore
    @EnvironmentObject private var terminalPreferences: TerminalPreferencesStore
    @Binding var selection: SettingsSection

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 22) {
                contentHeader

                switch selection {
                case .appearance:
                    appearancePane
                case .transfer:
                    transferPane
                case .terminal:
                    terminalPane
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

    private var transferPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingCard {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("上传冲突策略")
                            .font(.system(.headline).weight(.semibold))
                            .foregroundStyle(.primary)

                        Text("SFTP put 默认直接覆盖，无确认对话框；仅在「跳过」模式下会先检查远端是否已有同名项。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    UploadConflictStrategyPicker(selection: $uploadPreferences.conflictStrategy)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer(minLength: 0)
        }
    }

    private var terminalPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingCard {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("终端应用")
                            .font(.system(.headline).weight(.semibold))
                            .foregroundStyle(.primary)

                        Text("单选一项；系统自带终端列在首位，第三方终端紧随其后。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    ExternalTerminalAppPicker(selection: $terminalPreferences.selectedApp)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer(minLength: 0)
        }
    }

    private var configurationPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            SSHConfigPathSettingsCard()
            DefaultDownloadDirectorySettingsCard()
            RemoteEditCacheSettingsCard()

            SettingCard {
                VStack(alignment: .leading, spacing: 6) {
                    Text("远端目录")
                        .font(.system(.headline).weight(.semibold))
                    Text("每台主机的默认上传目录仍在主窗口中设置；本机默认下载目录见上方。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer(minLength: 0)
        }
    }
}
