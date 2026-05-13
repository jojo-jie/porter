# Porter

Porter 是 macOS 上的 SwiftUI 小工具：从本机 `~/.ssh/config` 读取 SSH `Host` alias，用系统 **OpenSSH**（`ssh` 浏览、`sftp` 传文件）完成远端目录浏览、上传与下载，并复用密钥、代理跳板与 `Include` 等配置。

## 功能

- 解析 `~/.ssh/config`，支持 `Include`（含相对路径）。
- 侧边栏展示可用 `Host` alias（忽略 `*`、`?`、`!` 等通配）；过滤常见代码托管类主机。
- 查看 `User`、`HostName`、`Port` 等连接信息；每台主机可保存默认远程目录（`UserDefaults`）。
- 手写远程路径，或用远端目录浏览器逐层进入、选择目录。
- 支持点选与拖拽上传；在浏览器中可对文件或目录一键下载到本地。
- 可从应用内打开 Terminal 并执行 `ssh` 命令，便于自检连接。

传输与浏览均走系统二进制：远端列表为 `/usr/bin/ssh`，上传/下载为 `/usr/bin/sftp`（批处理模式，SFTP 子系统，与常见 SFTP 客户端同协议路径）。

## 环境要求

- macOS 14+；Swift 6 / SwiftPM。
- 本机已配置可用的 `~/.ssh/config`。
- 目标主机需能通过所选 Host **免交互** 登录；浏览与 SFTP 会使用 `BatchMode=yes`，不会在本应用内提示密码。

## 运行与开发

```bash
swift run Porter              # 启动应用
swift build
swift run PorterPathValidation # 路径与 sftp 批处理引号等的轻量回归
```

## SSH 配置示例

```sshconfig
Host prod
  HostName 10.0.0.10
  User deploy
  Port 22
  IdentityFile ~/.ssh/id_ed25519
```

选择 `prod`，将默认远程目录设为例如 `~/uploads`，即可上传；用目录浏览器选路径或下载远端文件/目录。

## 项目结构

```text
Sources/
  PorterApp/              SwiftUI、配置解析、远端浏览、上传下载编排
  PorterCore/             远端路径、`sftp -b` 批处理与引号等可复用逻辑
  PorterPathValidation/   上述逻辑的校验入口
```

## 实现要点

| 能力 | 说明 |
|------|------|
| Host 列表 | `SSHConfigParser.swift`：读配置、展开 `Include`、汇总可展示 alias |
| 远端列表 | `RemoteDirectoryBrowser.swift`：`ssh` 执行 `pwd` + `ls -la`，解析后展示 |
| 上传 / 下载 | `Uploader.swift`、`RemoteDownloader.swift`：调用 `PorterCore` 中的 SFTP 批处理（`PorterSFTPBatch.swift`），底层为 `/usr/bin/sftp` |
| 路径与 shell | `RemotePath.swift`：分段、拼接、远端 `cd` 的单引号策略（给 `ssh` 远端脚本用） |

## 安全与隐私

- 不设密码仓、不内置托管私钥；认证由系统 OpenSSH 与用户配置完成。
- 勿在仓库、文档示例或提交信息中写入真实主机名、用户名、私钥路径或私人路径。
- 调整 `ssh` / `sftp` 参数、远端路径、`sftp -b` 批处理中的路径转义，或 AppleScript 拼接时，需覆盖空格、引号、`~`、通配符与 shell 元字符等边界情况。

## 许可与免责声明

- 本项目以 MIT 许可证发布，见根目录 [`LICENSE`](LICENSE)。
- 软件按「原样」提供；用于重要数据或生产环境前请自行评估并做好备份与验证。
