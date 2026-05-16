import Foundation
import PorterCore

enum ConnectionPreflight {
    static func test(hostAlias: String) async -> String {
        let trimmed = hostAlias.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "未指定 SSH Host alias。"
        }

        let sshResult = await Task.detached(priority: .userInitiated) {
            runSSHProbe(hostAlias: trimmed)
        }.value

        if sshResult.exitCode != 0 {
            return "SSH 失败：\(humanReadableProbeOutput(sshResult.output, fallback: "退出码 \(sshResult.exitCode)"))"
        }

        let sftpResult = await Task.detached(priority: .userInitiated) {
            PorterSFTPBatch.run(host: trimmed, batchScript: "pwd\n")
        }.value

        if sftpResult.exitCode != 0 {
            return "SSH 已通过；SFTP 失败：\(humanReadableProbeOutput(sftpResult.output, fallback: "退出码 \(sftpResult.exitCode)"))"
        }

        let detail = sftpResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
        if detail.isEmpty {
            return "连接正常：SSH 与 SFTP 均可用。"
        }
        return "连接正常：SSH 与 SFTP 均可用（远端 pwd：\(detail.prefix(120))）。"
    }

    private static func runSSHProbe(hostAlias: String) -> (exitCode: Int32, output: String) {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = [
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=10",
            hostAlias,
            "/bin/true",
        ]
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
            process.waitUntilExit()
            let out = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let err = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let merged = [out, err].filter { !$0.isEmpty }.joined(separator: "\n")
            return (process.terminationStatus, merged)
        } catch {
            return (127, error.localizedDescription)
        }
    }

    private static func humanReadableProbeOutput(_ output: String, fallback: String) -> String {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return fallback }
        let lines = trimmed.components(separatedBy: .newlines).filter { !$0.isEmpty }
        let condensed = lines.prefix(4).joined(separator: " ")
        return condensed.count > 280 ? String(condensed.prefix(280)) + "…" : condensed
    }
}
