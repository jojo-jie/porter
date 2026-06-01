import Foundation

/// Cooperative cancellation for `Process`-backed OpenSSH invocations.
public final class PorterSubprocessCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    public private(set) var isCancelled = false

    public init() {}

    public func cancel() {
        lock.lock()
        defer { lock.unlock() }
        isCancelled = true
        process?.terminate()
    }

    func attach(_ process: Process) {
        lock.lock()
        defer { lock.unlock() }
        self.process = process
        if isCancelled {
            process.terminate()
        }
    }
}

public enum PorterSubprocess {
    public struct Result: Sendable {
        public let exitCode: Int32
        public let output: String
        public let wasCancelled: Bool
    }

    public static func run(
        executable: String,
        arguments: [String],
        stdin: String? = nil,
        cancellation: PorterSubprocessCancellation? = nil
    ) -> Result {
        if cancellation?.isCancelled == true {
            return Result(exitCode: 130, output: "已取消。", wasCancelled: true)
        }

        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdinPipe = stdin != nil ? Pipe() : nil

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        if let stdinPipe {
            process.standardInput = stdinPipe
        }

        cancellation?.attach(process)

        do {
            try process.run()
            if let stdin, let stdinPipe, let data = stdin.data(using: .utf8) {
                stdinPipe.fileHandleForWriting.write(data)
                stdinPipe.fileHandleForWriting.closeFile()
            }
            process.waitUntilExit()
            let out = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let err = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let merged = [out, err].filter { !$0.isEmpty }.joined(separator: "\n")
            let wasCancelled = cancellation?.isCancelled == true
            return Result(exitCode: process.terminationStatus, output: merged, wasCancelled: wasCancelled)
        } catch {
            return Result(exitCode: 127, output: error.localizedDescription, wasCancelled: cancellation?.isCancelled == true)
        }
    }
}
