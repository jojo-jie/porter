import Foundation
import PorterCore

private func posixSingleQuotedForTest(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

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

let webInner = RemoteShellPath.changeDirectoryCommand(for: "/var/www/app") + " && exec bash -i"
let webB64 = Data(webInner.utf8).base64EncodedString()
let webRemote = "bash -lc \"$(printf %s \(posixSingleQuotedForTest(webB64)) | base64 -d)\""
let webExpected =
    "ssh -t -- \(posixSingleQuotedForTest("web")) \(posixSingleQuotedForTest(webRemote))"
expectEqual(
    PorterSSHInteractiveCommand.localShellInvocation(hostAlias: "web", remotePath: "/var/www/app"),
    webExpected,
    "ssh invocation uses base64-wrapped remote script for paths with quotes"
)

let edgeInner = RemoteShellPath.changeDirectoryCommand(for: "~/two words/it's") + " && exec bash -i"
let edgeB64 = Data(edgeInner.utf8).base64EncodedString()
let edgeRemote = "bash -lc \"$(printf %s \(posixSingleQuotedForTest(edgeB64)) | base64 -d)\""
let edgeExpected =
    "ssh -t -- \(posixSingleQuotedForTest("edge-host")) \(posixSingleQuotedForTest(edgeRemote))"
expectEqual(
    PorterSSHInteractiveCommand.localShellInvocation(hostAlias: "edge-host", remotePath: "~/two words/it's"),
    edgeExpected,
    "ssh invocation base64-wraps home-relative cd with embedded quotes"
)

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

expectEqual(
    RemotePathCodec.childPath(in: "~/uploads", name: "readme.txt"),
    "~/uploads/readme.txt",
    "child path under home directory"
)
expectEqual(
    RemotePathCodec.childPath(in: "/var/www/app", name: "index.html"),
    "/var/www/app/index.html",
    "child path under absolute directory"
)
expectEqual(
    RemoteShellPath.itemExistsTestLine(for: "~/uploads/readme.txt"),
    #"test -e -- "$HOME"/'uploads/readme.txt'"#,
    "exists probe quotes home-relative path"
)
expectEqual(
    RemoteShellPath.itemExistsTestLine(for: "/var/www/app"),
    #"test -e -- '/var/www/app'"#,
    "exists probe quotes absolute path"
)

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
