import CryptoKit
import Foundation

public enum RemoteEditCacheError: Error, LocalizedError {
    case cachesDirectoryUnavailable

    public var errorDescription: String? {
        switch self {
        case .cachesDirectoryUnavailable:
            return "无法访问本机缓存目录"
        }
    }
}

/// Local staging under `Library/Caches/Porter/remote-edit` for remote file editing.
public enum RemoteEditCache {
    public static let cacheFolderName = "remote-edit"

    public static func cacheRootURL(fileManager: FileManager = .default) -> URL? {
        guard let cachesRoot = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        return cachesRoot
            .appendingPathComponent("Porter", isDirectory: true)
            .appendingPathComponent(cacheFolderName, isDirectory: true)
    }

    public static func stagingDirectoryURL(
        host: String,
        remotePath: String,
        fileManager: FileManager = .default
    ) throws -> URL {
        guard let root = cacheRootURL(fileManager: fileManager) else {
            throw RemoteEditCacheError.cachesDirectoryUnavailable
        }
        let hostFolder = sanitizedHostFolderName(host)
        let pathHash = remotePathHash(canonicalCachePath(remotePath))
        let directory = root
            .appendingPathComponent(hostFolder, isDirectory: true)
            .appendingPathComponent(pathHash, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    public static func sanitizedHostFolderName(_ host: String) -> String {
        var sanitized = host
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
        if sanitized.isEmpty {
            sanitized = "_"
        }
        if sanitized == "." || sanitized == ".." {
            sanitized = "_\(sanitized)"
        }
        return sanitized
    }

    /// Normalizes logical remote paths so equivalent forms share one cache directory.
    public static func canonicalCachePath(_ remotePath: String) -> String {
        RemotePathCodec.join(RemotePathCodec.split(remotePath))
    }

    public static func remotePathHash(_ remotePath: String) -> String {
        let digest = SHA256.hash(data: Data(remotePath.utf8))
        return digest.prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    public static func measuredSizeInBytes(fileManager: FileManager = .default) -> Int64 {
        guard let root = cacheRootURL(fileManager: fileManager),
              fileManager.fileExists(atPath: root.path)
        else {
            return 0
        }
        return directorySize(at: root, fileManager: fileManager)
    }

    public static func directorySize(at url: URL, fileManager: FileManager = .default) -> Int64 {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey, .totalFileAllocatedSizeKey]
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: keys),
                  values.isRegularFile == true
            else {
                continue
            }
            let allocated = values.totalFileAllocatedSize ?? values.fileSize ?? 0
            total += Int64(allocated)
        }
        return total
    }

    /// Human-readable size in megabytes (binary MB, one decimal place).
    public static func formattedMegabytes(forBytes bytes: Int64) -> String {
        let megabytes = Double(bytes) / 1_048_576.0
        return String(format: "%.1f MB", megabytes)
    }

    @discardableResult
    public static func clear(fileManager: FileManager = .default) throws -> Bool {
        guard let root = cacheRootURL(fileManager: fileManager) else {
            return false
        }
        guard fileManager.fileExists(atPath: root.path) else {
            return false
        }
        try fileManager.removeItem(at: root)
        return true
    }
}
