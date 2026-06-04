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

expectEqual(
    RemoteShellPath.createDirectoryShellCommand(path: "/tmp/a b"),
    "if test -e -- '/tmp/a b'; then exit 2; fi\nmkdir -p -- '/tmp/a b'",
    "create directory probes existence and quotes path"
)

expectEqual(
    RemoteShellPath.createEmptyFileShellCommand(path: "~/new file"),
    "if test -e -- \"$HOME\"/'new file'; then exit 2; fi\ntouch -- \"$HOME\"/'new file'",
    "create empty file probes home-relative path and quotes tail"
)

expectEqual(RemotePathCodec.split(""), ["~"], "empty input splits to home")
expectEqual(RemotePathCodec.split("~"), ["~"], "tilde splits to home")
expectEqual(RemotePathCodec.split("~/uploads"), ["~", "uploads"], "home-relative input splits into components")
expectEqual(RemotePathCodec.split("/var/www/app"), ["/", "var", "www", "app"], "absolute input splits into components")
expectEqual(RemotePathCodec.join(["~", "two words", "it's"]), "~/two words/it's", "home-relative components join")
expectEqual(RemotePathCodec.join(["/", "var", "www", "app"]), "/var/www/app", "absolute components join")
expectEqual(
    RemotePathCodec.resolve("logs/archive", against: ["~", "uploads"]),
    ["~", "uploads", "logs", "archive"],
    "relative typed path resolves under current directory"
)
expectEqual(
    RemotePathCodec.resolve("../shared/./assets", against: ["/", "var", "www", "app"]),
    ["/", "var", "www", "shared", "assets"],
    "relative typed path normalizes parent and dot segments"
)
expectEqual(
    RemotePathCodec.resolve("/srv/releases", against: ["~", "uploads"]),
    ["/", "srv", "releases"],
    "absolute typed path replaces current directory"
)

expectEqual(PorterSFTPBatch.batchQuotedPath("/tmp/a"), "\"/tmp/a\"", "sftp batch quotes plain path")
expectEqual(PorterSFTPBatch.batchQuotedPath("/tmp/a\\\"b"), "\"/tmp/a\\\\\\\"b\"", "sftp batch escapes quotes and backslashes")

expectEqual(
    PorterSFTPBatch.buildMultiUploadScript(
        remoteDirectory: "/var/www",
        items: [
            PorterSFTPBatch.UploadItem(localAbsolutePath: "/tmp/a.txt", isDirectory: false),
            PorterSFTPBatch.UploadItem(localAbsolutePath: "/tmp/pkg", isDirectory: true),
        ]
    ),
    """
    cd "/var/www"
    put -p "/tmp/a.txt"
    put -pr "/tmp/pkg"

    """,
    "multi upload uses one cd and multiple puts"
)

let probeScript = RemoteShellPath.batchItemExistenceProbeScript(paths: ["~/uploads/a", "/var/www/app"])
expectEqual(
    probeScript,
    """
    set +e
    if test -e -- "$HOME"/'uploads/a'; then echo "PORTER_EXISTS 0 1"; else echo "PORTER_EXISTS 0 0"; fi
    if test -e -- '/var/www/app'; then echo "PORTER_EXISTS 1 1"; else echo "PORTER_EXISTS 1 0"; fi
    """,
    "batch existence probe emits indexed markers"
)
let probeOutput = """
PORTER_EXISTS 0 1
PORTER_EXISTS 1 0
"""
let parsedExistence = RemoteShellPath.parseBatchExistenceProbeOutput(probeOutput, count: 2)
guard parsedExistence.count == 2, parsedExistence[0] == true, parsedExistence[1] == false else {
    fatalError("batch existence parser maps markers to booleans: \(parsedExistence)")
}

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

expectEqual(RemoteEditCache.sanitizedHostFolderName("my/host:22"), "my_host_22", "host folder sanitizes slashes and colons")
expectEqual(RemoteEditCache.sanitizedHostFolderName(""), "_", "empty host folder becomes underscore")
expectEqual(RemoteEditCache.sanitizedHostFolderName(".."), "_..", "dot-dot host folder is escaped")
expectEqual(
    RemoteEditCache.remotePathHash(RemoteEditCache.canonicalCachePath("~/proj/")),
    RemoteEditCache.remotePathHash(RemoteEditCache.canonicalCachePath("~/proj")),
    "canonical cache path ignores trailing slash"
)
expectEqual(RemoteEditCache.remotePathHash("/var/www/app"), RemoteEditCache.remotePathHash("/var/www/app"), "remote path hash is stable")
expectEqual(RemoteEditCache.formattedMegabytes(forBytes: 0), "0.0 MB", "zero bytes formats as megabytes")
expectEqual(RemoteEditCache.formattedMegabytes(forBytes: 1_048_576), "1.0 MB", "one binary megabyte formats with one decimal")

let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("porter-cache-test-\(UUID().uuidString)", isDirectory: true)
do {
    try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempRoot) }

    let sampleFile = tempRoot.appendingPathComponent("sample.txt")
    try "hello".write(to: sampleFile, atomically: true, encoding: .utf8)
    let measured = RemoteEditCache.directorySize(at: tempRoot)
    guard measured > 0 else {
        fatalError("directory size should count regular files")
    }
    try FileManager.default.removeItem(at: sampleFile)
    expectEqual(RemoteEditCache.directorySize(at: tempRoot), 0, "empty directory reports zero size")
} catch {
    fatalError("cache size test failed: \(error)")
}

let sshConfigTempRoot = FileManager.default.temporaryDirectory
    .appendingPathComponent("porter-ssh-config-test-\(UUID().uuidString)", isDirectory: true)
do {
    try FileManager.default.createDirectory(at: sshConfigTempRoot, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: sshConfigTempRoot) }

    let configURL = sshConfigTempRoot.appendingPathComponent("config")
    let includeDirectory = sshConfigTempRoot.appendingPathComponent("includes", isDirectory: true)
    try FileManager.default.createDirectory(at: includeDirectory, withIntermediateDirectories: true)

    try """
    Host app
      HostName=app.internal
      User deploy
      Port 2201

    Include=includes/*.conf

    Host *
      User wildcard

    Host github
      HostName github.com
      User git

    Host !blocked
      HostName blocked.internal
    """.write(to: configURL, atomically: true, encoding: .utf8)

    try """
    Host quoted
      HostName "host#with-comment-marker"
      User "deploy user" # real comment
      Port 2222
    """.write(to: includeDirectory.appendingPathComponent("quoted.conf"), atomically: true, encoding: .utf8)

    try """
    Include ../config

    Host nested
      HostName nested.internal
    """.write(to: includeDirectory.appendingPathComponent("nested.conf"), atomically: true, encoding: .utf8)

    let hosts = SSHConfigParser.loadHosts(configURL: configURL)
    expectEqual(hosts.map(\.name), ["app", "nested", "quoted"], "ssh config parser expands includes and filters aliases")

    guard let appHost = hosts.first(where: { $0.name == "app" }) else {
        fatalError("app host parsed")
    }
    expectEqual(appHost.hostName, "app.internal", "ssh config parser reads hostname")
    expectEqual(appHost.user, "deploy", "ssh config parser reads user")
    expectEqual(appHost.port, "2201", "ssh config parser reads port")

    guard let quotedHost = hosts.first(where: { $0.name == "quoted" }) else {
        fatalError("quoted host parsed")
    }
    expectEqual(quotedHost.hostName, "host#with-comment-marker", "ssh config parser unquotes host value and preserves quoted hash")
    expectEqual(quotedHost.user, "deploy user", "ssh config parser unquotes values and strips comments outside quotes")
    expectEqual(quotedHost.port, "2222", "ssh config parser reads included port")
} catch {
    fatalError("ssh config parser test failed: \(error)")
}

let duplicateConfigTempRoot = FileManager.default.temporaryDirectory
    .appendingPathComponent("porter-ssh-config-duplicate-test-\(UUID().uuidString)", isDirectory: true)
do {
    try FileManager.default.createDirectory(at: duplicateConfigTempRoot, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: duplicateConfigTempRoot) }

    let configURL = duplicateConfigTempRoot.appendingPathComponent("config")
    try """
    Host duplicate
      HostName first.internal

    Host duplicate
      HostName second.internal
    """.write(to: configURL, atomically: true, encoding: .utf8)

    let hosts = SSHConfigParser.loadHosts(configURL: configURL)
    expectEqual(hosts.count, 1, "ssh config parser de-duplicates aliases")
    expectEqual(hosts.first?.name, "duplicate", "ssh config parser keeps duplicate alias name")
    expectEqual(hosts.first?.hostName, "first.internal", "ssh config parser keeps first duplicate host")
} catch {
    fatalError("ssh config duplicate parser test failed: \(error)")
}

print("Remote path validation passed")
