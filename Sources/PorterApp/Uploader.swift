import Foundation
import PorterCore

enum Uploader {
    static func upload(fileURLs: [URL], host: String, remotePath: String) async -> String {
        let trimmedRemote = remotePath.trimmingCharacters(in: .whitespacesAndNewlines)
        var output: [String] = []
        var failures: [String] = []

        for fileURL in fileURLs {
            guard fileURL.isFileURL else { continue }
            let path = fileURL.path
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else {
                failures.append(fileURL.lastPathComponent)
                output.append("路径不存在：\(path)")
                continue
            }
            guard FileManager.default.isReadableFile(atPath: path) else {
                failures.append(fileURL.lastPathComponent)
                output.append("无法读取：\(path)")
                continue
            }

            let script = PorterSFTPBatch.buildUploadScript(
                remoteDirectory: trimmedRemote,
                localAbsolutePath: path,
                isDirectory: isDir.boolValue
            )
            let result = await Task.detached(priority: .userInitiated) {
                PorterSFTPBatch.run(host: host, batchScript: script)
            }.value
            output.append(result.output)
            if result.exitCode != 0 {
                failures.append(fileURL.lastPathComponent)
            }
        }

        let namesAttempted = fileURLs.filter(\.isFileURL).map(\.lastPathComponent)
        guard !namesAttempted.isEmpty else {
            return "没有可上传的本地文件。"
        }

        if failures.isEmpty {
            return "上传完成（SFTP）：\(namesAttempted.joined(separator: ", "))"
        }

        let detail = output.filter { !$0.isEmpty }.joined(separator: "\n")
        return "上传失败：\(failures.joined(separator: ", "))\n\(detail)"
    }
}
