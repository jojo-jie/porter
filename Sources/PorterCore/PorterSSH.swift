import Foundation

/// Non-interactive OpenSSH `ssh(1)` helpers (batch mode, merged stdout/stderr).
public enum PorterSSH {
    public static func run(
        host: String,
        remoteCommand: String,
        cancellation: PorterSubprocessCancellation? = nil
    ) -> (exitCode: Int32, output: String, wasCancelled: Bool) {
        let result = PorterSubprocess.run(
            executable: "/usr/bin/ssh",
            arguments: [
                "-o", "BatchMode=yes",
                "-o", "ConnectTimeout=20",
                host,
                remoteCommand,
            ],
            cancellation: cancellation
        )
        return (result.exitCode, result.output, result.wasCancelled)
    }
}
