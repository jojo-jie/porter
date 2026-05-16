import Foundation
import SwiftUI

@MainActor
final class DownloadPreferencesStore: ObservableObject {
    private let defaultsKey = "porter.defaultDownloadDirectoryPath"

    @Published var downloadDirectoryPath: String {
        didSet {
            let trimmed = downloadDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                UserDefaults.standard.removeObject(forKey: defaultsKey)
                if !downloadDirectoryPath.isEmpty {
                    downloadDirectoryPath = ""
                }
                return
            }

            let expanded = (trimmed as NSString).expandingTildeInPath
            if expanded != downloadDirectoryPath {
                downloadDirectoryPath = expanded
                return
            }

            UserDefaults.standard.set(expanded, forKey: defaultsKey)
        }
    }

    var hasConfiguredPath: Bool {
        !downloadDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Valid existing directory for downloads; nil when unset or path is missing/not a folder.
    var resolvedDirectoryURL: URL? {
        let expanded = expandedPath
        guard !expanded.isEmpty else { return nil }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: expanded, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            return nil
        }
        return URL(fileURLWithPath: expanded, isDirectory: true)
    }

    var validationIssue: String? {
        let expanded = expandedPath
        guard !expanded.isEmpty else { return nil }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: expanded, isDirectory: &isDirectory) else {
            return "目录不存在；下载时将改为每次选择保存位置。"
        }
        guard isDirectory.boolValue else {
            return "路径不是文件夹；下载时将改为每次选择保存位置。"
        }
        return nil
    }

    init() {
        downloadDirectoryPath = UserDefaults.standard.string(forKey: defaultsKey) ?? ""
    }

    func clear() {
        downloadDirectoryPath = ""
    }

    func setDirectory(from url: URL) {
        downloadDirectoryPath = url.path
    }

    private var expandedPath: String {
        let trimmed = downloadDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return (trimmed as NSString).expandingTildeInPath
    }
}
