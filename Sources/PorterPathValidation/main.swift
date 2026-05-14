import PorterCore

private func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
    guard actual == expected else {
        fatalError("\(message): expected \(expected), got \(actual)")
    }
}

expectEqual(RemoteShellPath.changeDirectoryCommand(for: ""), #"cd "$HOME""#, "empty path uses home")
expectEqual(RemoteShellPath.changeDirectoryCommand(for: "~"), #"cd "$HOME""#, "tilde path uses home")
expectEqual(RemoteShellPath.changeDirectoryCommand(for: "~/uploads"), #"cd "$HOME"/'uploads'"#, "home-relative path is quoted")
expectEqual(RemoteShellPath.changeDirectoryCommand(for: "~/two words/it's"), #"cd "$HOME"/'two words/it'"'"'s'"#, "home-relative path escapes quotes")
expectEqual(RemoteShellPath.changeDirectoryCommand(for: "/var/www/app"), #"cd '/var/www/app'"#, "absolute path is quoted")
expectEqual(RemoteShellPath.changeDirectoryCommand(for: "relative path/it's"), #"cd 'relative path/it'"'"'s'"#, "relative path escapes quotes")
expectEqual(RemoteShellPath.changeDirectoryCommand(for: "-dash"), #"cd ./'-dash'"#, "dash-prefixed relative path is not treated as an option")

expectEqual(
    RemoteShellPath.moveItemShellCommand(from: "/tmp/a b", to: "/tmp/c'd"),
    #"mv -- '/tmp/a b' '/tmp/c'"'"'d'"#,
    "move command quotes paths and uses --"
)

expectEqual(
    RemoteShellPath.removeItemShellCommand(path: "/tmp/a b", recursive: false),
    #"rm -f -- '/tmp/a b'"#,
    "remove file command quotes path and uses --"
)

expectEqual(
    RemoteShellPath.removeItemShellCommand(path: "/tmp/c'd", recursive: true),
    #"rm -rf -- '/tmp/c'"'"'d'"#,
    "remove directory command quotes path and uses --"
)

expectEqual(RemotePathCodec.split(""), ["~"], "empty input splits to home")
expectEqual(RemotePathCodec.split("~"), ["~"], "tilde splits to home")
expectEqual(RemotePathCodec.split("~/uploads"), ["~", "uploads"], "home-relative input splits into components")
expectEqual(RemotePathCodec.split("/var/www/app"), ["/", "var", "www", "app"], "absolute input splits into components")
expectEqual(RemotePathCodec.join(["~", "two words", "it's"]), "~/two words/it's", "home-relative components join")
expectEqual(RemotePathCodec.join(["/", "var", "www", "app"]), "/var/www/app", "absolute components join")

expectEqual(PorterSFTPBatch.batchQuotedPath("/tmp/a"), "\"/tmp/a\"", "sftp batch quotes plain path")
expectEqual(PorterSFTPBatch.batchQuotedPath("/tmp/a\\\"b"), "\"/tmp/a\\\\\\\"b\"", "sftp batch escapes quotes and backslashes")

guard RemoteFileNameValidation.validatePortableFileName("readme.txt") == nil else {
    fatalError("normal file name validates")
}
guard RemoteFileNameValidation.validatePortableFileName("") == .empty else {
    fatalError("empty name")
}
guard RemoteFileNameValidation.validatePortableFileName("  ") == .hasInvisibleEdgeWhitespace else {
    fatalError("whitespace-only should hit edge rule, not silent trim")
}
guard RemoteFileNameValidation.validatePortableFileName("ok ") == .hasInvisibleEdgeWhitespace else {
    fatalError("trailing ASCII space must be rejected explicitly")
}
guard RemoteFileNameValidation.validatePortableFileName(".") == .reservedAlias else {
    fatalError("dot alias rejected")
}
guard RemoteFileNameValidation.validatePortableFileName("..") == .reservedAlias else {
    fatalError("dotdot alias rejected")
}
guard RemoteFileNameValidation.validatePortableFileName(".hidden") == nil else {
    fatalError("dot-prefixed real name allowed")
}
guard RemoteFileNameValidation.validatePortableFileName("a/b") == .forbiddenCharacterOrControl else {
    fatalError("slash rejected in single component")
}
guard RemoteFileNameValidation.validatePortableFileName(#"a\b"#) == .forbiddenCharacterOrControl else {
    fatalError("backslash rejected for Windows/SMB portability")
}
guard RemoteFileNameValidation.validatePortableFileName("a\nb") == .forbiddenCharacterOrControl else {
    fatalError("newline rejected")
}
guard RemoteFileNameValidation.validatePortableFileName("a:b") == .forbiddenCharacterOrControl else {
    fatalError("colon rejected for Windows / streams")
}
guard RemoteFileNameValidation.validatePortableFileName("name.") == .trailingPeriodDisallowedOnWindows else {
    fatalError("trailing period rejected for Windows")
}
guard RemoteFileNameValidation.validatePortableFileName("CON.txt") == .windowsReservedDeviceName else {
    fatalError("windows reserved base name with extension")
}
guard RemoteFileNameValidation.validatePortableFileName("nul") == .windowsReservedDeviceName else {
    fatalError("windows reserved short name")
}
guard RemoteFileNameValidation.validatePortableFileName("notcon") == nil else {
    fatalError("non-reserved prefix should pass")
}
guard RemoteFileNameValidation.validatePortableFileName(String(repeating: "x", count: 256))
    == .utf8TooLong(maxUTF8Bytes: 255)
else {
    fatalError("overlong UTF-8 length rejected")
}

print("Remote path validation passed")
