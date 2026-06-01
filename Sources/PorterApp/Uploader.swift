import Foundation
import PorterCore

struct UploadProgressUpdate: Sendable {
    enum Phase: Sendable {
        case preparing
        case uploading
    }

    let phase: Phase
    let completedCount: Int
    let totalCount: Int
    let detail: String?
}

enum Uploader {
    struct Outcome: Sendable {
        let message: String
        let wasCancelled: Bool
    }

    private struct LocalUploadCandidate: Sendable {
        let url: URL
        let name: String
        let path: String
        let isDirectory: Bool
    }

    static func upload(
        fileURLs: [URL],
        host: String,
        remotePath: String,
        conflictStrategy: UploadConflictStrategy,
        cancellation: PorterSubprocessCancellation? = nil,
        onProgress: (@Sendable (UploadProgressUpdate) -> Void)? = nil
    ) async -> Outcome {
        let trimmedRemote = remotePath.trimmingCharacters(in: .whitespacesAndNewlines)
        var output: [String] = []
        var failures: [String] = []
        var skipped: [String] = []

        let candidates = prepareCandidates(from: fileURLs, output: &output, failures: &failures)
        guard !candidates.isEmpty else {
            if failures.isEmpty {
                return Outcome(message: "没有可上传的本地文件。", wasCancelled: false)
            }
            return Outcome(message: failureSummary(failures: failures, skipped: skipped, uploaded: [], output: output), wasCancelled: false)
        }

        let total = candidates.count
        reportProgress(onProgress, phase: .preparing, completed: 0, total: total, detail: "正在检查 \(total) 项…")

        var toUpload = candidates
        if conflictStrategy == .skip {
            let remotePaths = candidates.map { RemotePathCodec.childPath(in: trimmedRemote, name: $0.name) }
            switch await batchRemoteExistence(host: host, paths: remotePaths, cancellation: cancellation) {
            case .cancelled:
                return Outcome(message: "上传已取消。", wasCancelled: true)
            case .failed:
                return Outcome(
                    message: "无法检查远端是否已存在同名项，上传已中止。",
                    wasCancelled: false
                )
            case .success(let exists):
                var next: [LocalUploadCandidate] = []
                for (index, candidate) in candidates.enumerated() {
                    guard index < exists.count else {
                        failures.append(candidate.name)
                        output.append("无法检查远端是否已存在：\(candidate.name)")
                        continue
                    }
                    switch exists[index] {
                    case true:
                        skipped.append(candidate.name)
                        output.append("已跳过（远端已存在）：\(candidate.name)")
                    case false:
                        next.append(candidate)
                    case nil:
                        failures.append(candidate.name)
                        output.append("无法检查远端是否已存在：\(candidate.name)")
                    }
                }
                toUpload = next
                reportProgress(
                    onProgress,
                    phase: .preparing,
                    completed: total,
                    total: total,
                    detail: skipped.isEmpty ? nil : "已跳过 \(skipped.count) 项"
                )
            }
        }

        guard !toUpload.isEmpty else {
            return Outcome(
                message: successSummary(uploaded: [], skipped: skipped, failures: failures, output: output),
                wasCancelled: false
            )
        }

        if cancellation?.isCancelled == true {
            return Outcome(message: "上传已取消。", wasCancelled: true)
        }

        let uploadItems = toUpload.map {
            PorterSFTPBatch.UploadItem(localAbsolutePath: $0.path, isDirectory: $0.isDirectory)
        }
        let script = PorterSFTPBatch.buildMultiUploadScript(remoteDirectory: trimmedRemote, items: uploadItems)
        let names = toUpload.map(\.name).joined(separator: ", ")
        reportProgress(
            onProgress,
            phase: .uploading,
            completed: 0,
            total: toUpload.count,
            detail: names
        )

        let result = await Task.detached(priority: .userInitiated) {
            PorterSFTPBatch.run(host: host, batchScript: script, cancellation: cancellation)
        }.value

        if result.wasCancelled {
            return Outcome(message: "上传已取消。", wasCancelled: true)
        }

        output.append(result.output)
        let uploaded: [String]
        if result.exitCode == 0 {
            uploaded = toUpload.map(\.name)
            reportProgress(onProgress, phase: .uploading, completed: toUpload.count, total: toUpload.count, detail: nil)
        } else {
            uploaded = []
            failures.append(contentsOf: toUpload.map(\.name))
        }

        if failures.isEmpty {
            return Outcome(
                message: successSummary(uploaded: uploaded, skipped: skipped, failures: failures, output: output),
                wasCancelled: false
            )
        }

        return Outcome(
            message: failureSummary(failures: failures, skipped: skipped, uploaded: uploaded, output: output),
            wasCancelled: false
        )
    }

    private static func prepareCandidates(
        from fileURLs: [URL],
        output: inout [String],
        failures: inout [String]
    ) -> [LocalUploadCandidate] {
        var candidates: [LocalUploadCandidate] = []
        for fileURL in fileURLs where fileURL.isFileURL {
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
            candidates.append(
                LocalUploadCandidate(url: fileURL, name: name, path: path, isDirectory: isDir.boolValue)
            )
        }
        return candidates
    }

    private enum BatchExistenceOutcome: Sendable {
        case success([Bool?])
        case failed
        case cancelled
    }

    private static func batchRemoteExistence(
        host: String,
        paths: [String],
        cancellation: PorterSubprocessCancellation?
    ) async -> BatchExistenceOutcome {
        guard !paths.isEmpty else { return .success([]) }
        let script = RemoteShellPath.batchItemExistenceProbeScript(paths: paths)
        let result = await Task.detached(priority: .userInitiated) {
            PorterSSH.run(host: host, remoteCommand: script, cancellation: cancellation)
        }.value

        if result.wasCancelled {
            return .cancelled
        }
        guard result.exitCode == 0 else {
            return .failed
        }
        let parsed = RemoteShellPath.parseBatchExistenceProbeOutput(result.output, count: paths.count)
        if parsed.contains(where: { $0 == nil }) {
            return .failed
        }
        return .success(parsed)
    }

    private static func reportProgress(
        _ onProgress: (@Sendable (UploadProgressUpdate) -> Void)?,
        phase: UploadProgressUpdate.Phase,
        completed: Int,
        total: Int,
        detail: String?
    ) {
        onProgress?(
            UploadProgressUpdate(
                phase: phase,
                completedCount: completed,
                totalCount: total,
                detail: detail
            )
        )
    }

    private static func successSummary(
        uploaded: [String],
        skipped: [String],
        failures: [String],
        output: [String]
    ) -> String {
        if !failures.isEmpty {
            return failureSummary(failures: failures, skipped: skipped, uploaded: uploaded, output: output)
        }

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

    private static func failureSummary(
        failures: [String],
        skipped: [String],
        uploaded: [String],
        output: [String]
    ) -> String {
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
}
