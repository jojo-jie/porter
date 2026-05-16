import Foundation
import SwiftUI

/// When a remote item with the same name already exists at the upload destination.
enum UploadConflictStrategy: String, CaseIterable, Identifiable {
    case overwrite
    case skip

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overwrite: return "覆盖"
        case .skip: return "跳过"
        }
    }

    var subtitle: String {
        switch self {
        case .overwrite:
            return "SFTP put 直接覆盖同名文件或目录，不弹确认。"
        case .skip:
            return "远端已存在同名项时不上传，并在结果中列出已跳过项。"
        }
    }

    var symbolName: String {
        switch self {
        case .overwrite: return "arrow.triangle.2.circlepath"
        case .skip: return "forward.end"
        }
    }
}

@MainActor
final class UploadPreferencesStore: ObservableObject {
    private let defaultsKey = "porter.uploadConflictStrategy"

    @Published var conflictStrategy: UploadConflictStrategy {
        didSet {
            UserDefaults.standard.set(conflictStrategy.rawValue, forKey: defaultsKey)
        }
    }

    init() {
        let raw = UserDefaults.standard.string(forKey: defaultsKey)
        conflictStrategy = raw.flatMap(UploadConflictStrategy.init(rawValue:)) ?? .overwrite
    }
}
