import Foundation
import SwiftUI

@MainActor
final class SSHConfigPreferencesStore: ObservableObject {
    private let defaultsKey = "porter.sshConfigPath"

    @Published var configPath: String {
        didSet {
            let normalized = configPath.trimmingCharacters(in: .whitespacesAndNewlines)
            let stored = normalized.isEmpty ? SSHConfigPathResolver.defaultConfigPath : normalized
            if stored != configPath {
                configPath = stored
                return
            }
            UserDefaults.standard.set(stored, forKey: defaultsKey)
            NotificationCenter.default.post(name: .porterSSHConfigPathChanged, object: nil)
        }
    }

    var resolvedConfigURL: URL {
        SSHConfigPathResolver.resolvedFileURL(forConfigPath: configPath)
    }

    var configFileExists: Bool {
        FileManager.default.fileExists(atPath: resolvedConfigURL.path)
    }

    var displayPath: String {
        configPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? SSHConfigPathResolver.defaultConfigPath
            : configPath
    }

    init() {
        let stored = UserDefaults.standard.string(forKey: defaultsKey)
        configPath = stored?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? stored!
            : SSHConfigPathResolver.defaultConfigPath
    }

    func resetToDefault() {
        configPath = SSHConfigPathResolver.defaultConfigPath
    }
}
