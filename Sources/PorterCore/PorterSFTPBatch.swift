import Foundation

/// OpenSSH `sftp(1)` batch-mode helpers: SFTP subsystem over SSH (same wire protocol as clients like Termius).
public enum PorterSFTPBatch {
    public struct UploadItem: Sendable {
        public let localAbsolutePath: String
        public let isDirectory: Bool

        public init(localAbsolutePath: String, isDirectory: Bool) {
            self.localAbsolutePath = localAbsolutePath
            self.isDirectory = isDirectory
        }
    }

    /// Produce a `-b` batch token with double-quote rules from the sftp(1) manual.
    public static func batchQuotedPath(_ path: String) -> String {
        let escaped = path.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    public static func run(
        host: String,
        batchScript: String,
        cancellation: PorterSubprocessCancellation? = nil
    ) -> (exitCode: Int32, output: String, wasCancelled: Bool) {
        let result = PorterSubprocess.run(
            executable: "/usr/bin/sftp",
            arguments: [
                "-b", "-",
                "-o", "BatchMode=yes",
                "-o", "ConnectTimeout=20",
                host,
            ],
            stdin: batchScript,
            cancellation: cancellation
        )
        return (result.exitCode, result.output, result.wasCancelled)
    }

    /// After `cd` into `remoteDirectory`, uploads one local filesystem object (file or directory).
    public static func buildUploadScript(remoteDirectory: String, localAbsolutePath: String, isDirectory: Bool) -> String {
        buildMultiUploadScript(
            remoteDirectory: remoteDirectory,
            items: [UploadItem(localAbsolutePath: localAbsolutePath, isDirectory: isDirectory)]
        )
    }

    /// One `cd`, then multiple `put` operations in a single SFTP batch session.
    public static func buildMultiUploadScript(remoteDirectory: String, items: [UploadItem]) -> String {
        guard !items.isEmpty else { return "" }
        var lines = ["cd \(batchQuotedPath(remoteDirectory))"]
        for item in items {
            let op = item.isDirectory ? "put -pr" : "put -p"
            lines.append("\(op) \(batchQuotedPath(item.localAbsolutePath))")
        }
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
