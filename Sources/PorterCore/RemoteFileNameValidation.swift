import Foundation

/// Cross-platform constraints for a *single* remote file/folder name (path component).
///
/// **Security note:** POSIX `mv` uses ``RemoteShellPath`` single-quoted arguments; rejecting odd characters reduces
/// foot-guns across SFTP/rsync/other tooling even when the immediate shell snippet is escaped. Do not concatenate
/// unquoted names into scripts.
///
/// Compatibility target: sane subset that works across **Linux/macOS POSIX** namespaces and typical **Windows/NTFS + SMB**.
public enum RemoteFileNameValidation {

    /// Portability failures for one path segment (basename only; no `/` traversal).
    public enum Issue: Equatable {
        /// After trimming enforced edge whitespace/nothing substantive remains.
        case empty
        /// Leading/trailing ``CharacterSet.whitespacesAndNewlines`` (`raw != trimmed`): invisible in UI paths and unsafe on SMB/Win32.
        case hasInvisibleEdgeWhitespace
        /// Entire segment is `"."` or `".."`.
        case reservedAlias
        /// Contains `/`, ``\``, NUL, ASCII/DEL controls, or characters illegal on NTFS/portable tooling.
        case forbiddenCharacterOrControl
        /// Basename ends with ASCII `.` (`foo.` …): invalid on Windows and breaks many SMB clients.
        case trailingPeriodDisallowedOnWindows
        /// Win32 reserved device pattern (`CON`, `NUL`, `COM1`, `LPT3`, `CLOCK$`, …) matched case-insensitively on stem before first `.`.
        case windowsReservedDeviceName
        /// Typical `NAME_MAX` / portable single-component cap (UTF-8 bytes).
        case utf8TooLong(maxUTF8Bytes: Int)
    }

    private static let posixLocale = Locale(identifier: "en_US_POSIX")

    /// Characters invalid in Windows file names, plus `/` and ``\`` (path splitters / traversal).
    private static let forbiddenScalarValues: Set<UInt32> = {
        var s = Set<UInt32>()
        for scalar in "/\\:*?\"<>|".unicodeScalars {
            s.insert(scalar.value)
        }
        for v in UInt32(0) ... UInt32(31) {
            s.insert(v)
        }
        s.insert(127) // DEL
        return s
    }()

    /// ``CON``, ``NUL``, ``COM1`` … — compare using uppercased stem before first unescaped `.`.
    private static let windowsReservedUppercased: Set<String> = [
        "CON", "PRN", "AUX", "NUL",
        "COM0", "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9",
        "LPT0", "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9",
        "CLOCK$", "CONIN$", "CONOUT$",
    ]

    /// Leading/trailing Unicode whitespace/newlines are rejected outright (`raw != trimmed`), then rules below apply.
    public static func validatePortableFileName(_ raw: String) -> Issue? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw != trimmed { return .hasInvisibleEdgeWhitespace }
        if trimmed.isEmpty { return .empty }
        if trimmed == "." || trimmed == ".." { return .reservedAlias }

        for scalar in trimmed.unicodeScalars {
            if scalar.properties.generalCategory == .control {
                return .forbiddenCharacterOrControl
            }
            if forbiddenScalarValues.contains(scalar.value) {
                return .forbiddenCharacterOrControl
            }
        }

        if trimmed.last == "." { return .trailingPeriodDisallowedOnWindows }

        let stem = windowsComparisonStem(for: trimmed)
        if windowsReservedUppercased.contains(stem.uppercased(with: posixLocale)) {
            return .windowsReservedDeviceName
        }

        let limit = 255
        if trimmed.utf8.count > limit {
            return .utf8TooLong(maxUTF8Bytes: limit)
        }
        return nil
    }

    /// First segment before `.` when the segment has a non-empty prefix; otherwise the full string (e.g. `.gitignore`).
    private static func windowsComparisonStem(for name: String) -> String {
        guard let dot = name.firstIndex(of: ".") else { return name }
        let head = String(name[..<dot])
        if head.isEmpty { return name }
        return head
    }
}
