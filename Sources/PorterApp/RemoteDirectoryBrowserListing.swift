import Foundation
import PorterCore

enum RemoteSSH {
    /// Runs a non-interactive remote shell snippet; output is stdout+stderr merged.
    static func run(host: String, bash: String) -> (exitCode: Int32, output: String) {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = [
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=20",
            host,
            bash,
        ]
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8) ?? ""
            return (process.terminationStatus, text)
        } catch {
            return (127, error.localizedDescription)
        }
    }
}

struct RemoteListingEntry: Identifiable, Hashable {
    var id: String { name }

    /// Synthetic `..` row for hierarchy navigation.
    static let parentDirectory = RemoteListingEntry(
        name: "..",
        permissions: "",
        modifiedDisplay: "—",
        sizeDisplay: "—",
        kindLabel: "",
        fileTypeMarker: "",
        isDirectory: true,
        navigable: true,
        sortKey: ""
    )

    let name: String
    let permissions: String
    let modifiedDisplay: String
    let sizeDisplay: String
    let kindLabel: String
    let fileTypeMarker: String
    let isDirectory: Bool
    var navigable: Bool
    /// ISO date `yyyy-MM-dd HH:mm` or raw tail for fallback sorting.
    let sortKey: String

    static func lsParse(lines: String) -> [RemoteListingEntry] {
        lines.split(separator: "\n", omittingEmptySubsequences: false).compactMap { rawLine -> RemoteListingEntry? in
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { return nil }
            if line.hasPrefix("total ") { return nil }

            guard let gnu = gnuLongIsoLine(from: line) else {
                return legacyWhitespaceLine(from: line)
            }
            return gnu
        }
    }

    private static func gnuLongIsoLine(from line: String) -> RemoteListingEntry? {
        let pattern = #"^([dl\-])([rwxsSt\-]{9}[+@\.]?)\s+\S+\s+\S+\s+\S+\s+(\d+)\s+(\d{4}-\d{2}-\d{2})\s+(\d{2}:\d{2})\s+(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let modeR = Range(match.range(at: 1), in: line),
              let permR = Range(match.range(at: 2), in: line),
              let sizeR = Range(match.range(at: 3), in: line),
              let dateR = Range(match.range(at: 4), in: line),
              let timeR = Range(match.range(at: 5), in: line),
              let nameR = Range(match.range(at: 6), in: line)
        else {
            return nil
        }

        let typeChar = String(line[modeR])
        let perm = "\(typeChar)\(String(line[permR]))"
        let size = String(line[sizeR])
        let datePart = String(line[dateR])
        let timePart = String(line[timeR])
        let nameField = String(line[nameR]).trimmingCharacters(in: .whitespaces)

        guard !nameField.isEmpty, nameField != ".", nameField != ".." else { return nil }

        let (displayName, isDir, navigable): (String, Bool, Bool) =
            switch typeChar {
            case "d":
                (nameField, true, true)
            case "l":
                navigableSymlink(displayName: nameField)
            default:
                (nameField, false, false)
            }

        let kind: String =
            switch typeChar {
            case "d": "文件夹"
            case "-": "文件"
            case "l": "符号链接"
            default: "其他"
            }

        return RemoteListingEntry(
            name: displayName,
            permissions: perm,
            modifiedDisplay: "\(datePart) \(timePart)",
            sizeDisplay: isDir ? "—" : RemoteByteCountFormatting.string(forBytes: UInt64(size) ?? 0),
            kindLabel: kind,
            fileTypeMarker: typeChar,
            isDirectory: isDir,
            navigable: navigable,
            sortKey: "\(datePart) \(timePart)"
        )
    }

    private static func navigableSymlink(displayName: String) -> (String, Bool, Bool) {
        let arrow = " -> "
        guard let splitRange = displayName.range(of: arrow) else {
            return (displayName, false, false)
        }
        let linkName = String(displayName[..<splitRange.lowerBound]).trimmingCharacters(in: .whitespaces)
        guard !linkName.isEmpty else { return (displayName, false, false) }
        return (linkName, false, false)
    }

    private static func legacyWhitespaceLine(from line: String) -> RemoteListingEntry? {
        let pieces = line.split(whereSeparator: \.isWhitespace).map(String.init)
        guard pieces.count >= 9 else { return nil }
        let mode = pieces[0]
        guard let typeChar = mode.first, "dl-".contains(typeChar) else { return nil }

        let name = pieces.dropFirst(8).joined(separator: " ")
        guard !name.isEmpty, name != ".", name != ".." else { return nil }

        let isDir = typeChar == "d"
        let month = pieces[5]
        let day = pieces[6]
        let timeOrYear = pieces[7]
        let modified = "\(month) \(day) \(timeOrYear)"
        let size = pieces[4]

        return RemoteListingEntry(
            name: name,
            permissions: mode,
            modifiedDisplay: modified,
            sizeDisplay: isDir ? "—" : RemoteByteCountFormatting.string(forBytes: UInt64(size) ?? 0),
            kindLabel: isDir ? "文件夹" : (typeChar == "l" ? "符号链接" : "文件"),
            fileTypeMarker: String(typeChar),
            isDirectory: isDir,
            navigable: isDir,
            sortKey: modified
        )
    }
}

private enum RemoteByteCountFormatting {
    static func string(forBytes bytes: UInt64) -> String {
        let formatter = Foundation.ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}
