import Foundation

/// OpenSSH `sftp(1)` batch-mode helpers: SFTP subsystem over SSH (same wire protocol as clients like Termius).
public enum PorterSFTPBatch {
    /// Produce a `-b` batch token with double-quote rules from the sftp(1) manual.
    public static func batchQuotedPath(_ path: String) -> String {
        let escaped = path.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    public static func run(host: String, batchScript: String) -> (exitCode: Int32, output: String) {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdinPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/sftp")
        process.arguments = [
            "-b", "-",
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=20",
            host,
        ]
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
            if let data = batchScript.data(using: String.Encoding.utf8) {
                stdinPipe.fileHandleForWriting.write(data)
            }
            stdinPipe.fileHandleForWriting.closeFile()
            process.waitUntilExit()
            let out = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let err = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let merged = [out, err].filter { !$0.isEmpty }.joined(separator: "\n")
            return (process.terminationStatus, merged)
        } catch {
            return (127, error.localizedDescription)
        }
    }

    /// After `cd` into `remoteDirectory`, uploads one local filesystem object (file or directory).
    public static func buildUploadScript(remoteDirectory: String, localAbsolutePath: String, isDirectory: Bool) -> String {
        let op = isDirectory ? "put -pr" : "put -p"
        let lines = [
            "cd \(batchQuotedPath(remoteDirectory))",
            "\(op) \(batchQuotedPath(localAbsolutePath))",
        ]
        return lines.joined(separator: "\n") + "\n"
    }

    /// `lcd` to the destination folder, then `get` one remote path (file or directory tree).
    public static func buildDownloadScript(remotePath: String, localDestinationDirectory: String, remoteIsDirectory: Bool) -> String {
        let getOp = remoteIsDirectory ? "get -rp" : "get -p"
        let lines = [
            "lcd \(batchQuotedPath(localDestinationDirectory))",
            "\(getOp) \(batchQuotedPath(remotePath))",
        ]
        return lines.joined(separator: "\n") + "\n"
    }
}
