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

expectEqual(RemotePathCodec.split(""), ["~"], "empty input splits to home")
expectEqual(RemotePathCodec.split("~"), ["~"], "tilde splits to home")
expectEqual(RemotePathCodec.split("~/uploads"), ["~", "uploads"], "home-relative input splits into components")
expectEqual(RemotePathCodec.split("/var/www/app"), ["/", "var", "www", "app"], "absolute input splits into components")
expectEqual(RemotePathCodec.join(["~", "two words", "it's"]), "~/two words/it's", "home-relative components join")
expectEqual(RemotePathCodec.join(["/", "var", "www", "app"]), "/var/www/app", "absolute components join")

expectEqual(PorterSFTPBatch.batchQuotedPath("/tmp/a"), "\"/tmp/a\"", "sftp batch quotes plain path")
expectEqual(PorterSFTPBatch.batchQuotedPath("/tmp/a\\\"b"), "\"/tmp/a\\\\\\\"b\"", "sftp batch escapes quotes and backslashes")

print("Remote path validation passed")
