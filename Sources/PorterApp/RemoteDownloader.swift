import Foundation

enum RemoteDownloader {
    static func download(host: String, remotePath: String, destinationDirectory: URL) async -> String {
        let result = await Task.detached(priority: .userInitiated) {
            runSCP(host: host, remotePath: remotePath, destinationDirectory: destinationDirectory)
        }.value

        if result.exitCode == 0 {
            return "下载完成：\(remotePath) → \(destinationDirectory.path)"
        }

        let detail = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        if detail.isEmpty {
            return "下载失败：\(remotePath)（退出码 \(result.exitCode)）"
        }
        return "下载失败：\(remotePath)\n\(detail)"
    }

    private static func runSCP(host: String, remotePath: String, destinationDirectory: URL) -> (exitCode: Int32, output: String) {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/scp")
        process.arguments = [
            "-r",
            "\(host):\(remoteShellEscaped(remotePath))",
            destinationDirectory.path,
        ]
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
