import Foundation
import PorterCore

enum Uploader {
    static func upload(
        fileURLs: [URL],
        host: String,
        remotePath: String,
        conflictStrategy: UploadConflictStrategy
    ) async -> String {
        let trimmedRemote = remotePath.trimmingCharacters(in: .whitespacesAndNewlines)
        var output: [String] = []
        var failures: [String] = []
        var skipped: [String] = []
        var uploaded: [String] = []

        for fileURL in fileURLs {
            guard fileURL.isFileURL else { continue }
            let path = fileURL.path
            let name = fileURL.lastPathComponent
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else {
                failures.append(name)
                output.append("路径不存在：\(path)")
                continue
            }
            guard FileManager.default.isReadableFile(atPath: path) else {
                failures.append(name)
                output.append("无法读取：\(path)")
                continue
            }

            if conflictStrategy == .skip {
                let remoteDestination = RemotePathCodec.childPath(in: trimmedRemote, name: name)
                switch await remoteItemExists(host: host, path: remoteDestination) {
                case true:
                    skipped.append(name)
                    output.append("已跳过（远端已存在）：\(name)")
                    continue
                case false:
                    break
                case nil:
                    failures.append(name)
                    output.append("无法检查远端是否已存在：\(name)")
                    continue
                }
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
                failures.append(name)
            } else {
                uploaded.append(name)
            }
        }

        let namesAttempted = fileURLs.filter(\.isFileURL).map(\.lastPathComponent)
        guard !namesAttempted.isEmpty else {
            return "没有可上传的本地文件。"
        }

        if failures.isEmpty {
            var parts: [String] = []
            if !uploaded.isEmpty {
                parts.append("上传完成（SFTP）：\(uploaded.joined(separator: ", "))")
            }
            if !skipped.isEmpty {
                parts.append("已跳过 \(skipped.count) 项（远端已存在）：\(skipped.joined(separator: ", "))")
            }
            if parts.isEmpty {
                return "没有可上传的本地文件。"
            }
            return parts.joined(separator: "\n")
        }

        let detail = output.filter { !$0.isEmpty }.joined(separator: "\n")
        var summary = "上传失败：\(failures.joined(separator: ", "))"
        if !skipped.isEmpty {
            summary += "\n已跳过：\(skipped.joined(separator: ", "))"
        }
        if !uploaded.isEmpty {
            summary += "\n已成功：\(uploaded.joined(separator: ", "))"
        }
        return summary + "\n" + detail
    }

    private static func remoteItemExists(host: String, path: String) async -> Bool? {
        let probe = RemoteShellPath.itemExistsTestLine(for: path)
        let result = await Task.detached(priority: .userInitiated) {
            PorterSSH.run(host: host, remoteCommand: probe)
        }.value
        switch result.exitCode {
        case 0:
            return true
        case 1:
            return false
        default:
            return nil
        }
    }
}
