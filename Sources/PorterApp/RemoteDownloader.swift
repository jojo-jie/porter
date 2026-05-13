import Foundation
import PorterCore

enum RemoteDownloader {
    static func download(
        host: String,
        remotePath: String,
        destinationDirectory: URL,
        remoteIsDirectory: Bool
    ) async -> String {
        let result = await Task.detached(priority: .userInitiated) {
            let script = PorterSFTPBatch.buildDownloadScript(
                remotePath: remotePath,
                localDestinationDirectory: destinationDirectory.path,
                remoteIsDirectory: remoteIsDirectory
            )
            return PorterSFTPBatch.run(host: host, batchScript: script)
        }.value

        if result.exitCode == 0 {
            return "下载完成（SFTP）：\(remotePath) → \(destinationDirectory.path)"
        }

        let detail = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        if detail.isEmpty {
            return "下载失败：\(remotePath)（退出码 \(result.exitCode)）"
        }
        return "下载失败：\(remotePath)\n\(detail)"
    }
}
