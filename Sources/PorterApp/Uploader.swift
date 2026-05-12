import Foundation

enum Uploader {
    static func upload(fileURLs: [URL], host: String, remotePath: String) async -> String {
        var output: [String] = []
        var failures: [String] = []

        for fileURL in fileURLs {
            let result = runSCP(fileURL: fileURL, host: host, remotePath: remotePath)
            output.append(result.output)
            if result.exitCode != 0 {
                failures.append(fileURL.lastPathComponent)
            }
        }

        if failures.isEmpty {
            return "上传完成：\(fileURLs.map(\.lastPathComponent).joined(separator: ", "))"
        }

        let detail = output.filter { !$0.isEmpty }.joined(separator: "\n")
        return "上传失败：\(failures.joined(separator: ", "))\n\(detail)"
    }

    private static func runSCP(fileURL: URL, host: String, remotePath: String) -> (exitCode: Int32, output: String) {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/scp")
        process.arguments = ["-r", fileURL.path, "\(host):\(remoteShellEscaped(remotePath))"]
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
        } catch {
            return (1, error.localizedDescription)
        }
    }

    private static func remoteShellEscaped(_ value: String) -> String {
        var escaped = ""
        for (index, character) in value.enumerated() {
            if index == 0, character == "~" {
                escaped.append(character)
            } else if "\\'\"$` !()[]{};&|<>*?".contains(character) {
                escaped.append("\\")
                escaped.append(character)
            } else {
                escaped.append(character)
            }
        }
        return escaped
    }
}
