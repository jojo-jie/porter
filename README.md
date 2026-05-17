# Porter

Porter 是 macOS 上的 SwiftUI 小工具：从本机 SSH 配置读取 `Host` alias，用系统 **OpenSSH**（`ssh` 浏览与 shell 操作、`sftp` 传文件）完成远端目录浏览、上传、下载与简单文件管理，并复用密钥、代理跳板与 `Include` 等既有配置。

## 功能

- **SSH 配置**：默认读取 `~/.ssh/config`，可在设置中指定其他路径；支持 `Include`（含相对路径）。
- **主机列表**：侧边栏展示可用 `Host` alias（忽略 `*`、`?`、`!` 等通配）；过滤常见代码托管类主机。
- **连接信息**：查看 `User`、`HostName`、`Port` 等；每台主机可保存默认远程目录；支持连接预检。
- **远端浏览**：手写远程路径，或用目录浏览器逐层进入、选择目录；支持重命名、删除远端项。
- **传输**：点选或拖拽上传；在浏览器中下载文件或目录；可在设置中配置默认本地下载目录与上传同名冲突策略（覆盖 / 跳过）。
- **远端编辑**：在默认本机应用中打开远端文件，保存后自动回传。
- **终端**：从应用内打开 Terminal.app、iTerm2 或 Warp 并执行 `ssh`（Warp 需辅助功能/输入监控权限）。
- **外观**：浅色 / 深色 / 跟随系统。

传输与浏览均走系统二进制：远端列表与 shell 为 `/usr/bin/ssh`，上传/下载为 `/usr/bin/sftp`（批处理模式 `-b`，SFTP 子系统，`BatchMode=yes`）。

## 环境要求

- macOS 14+；Swift 6 / SwiftPM。
- 本机已配置可用的 SSH 配置（默认 `~/.ssh/config`，可在应用设置中更改）。
- 目标主机需能通过所选 Host **免交互** 登录；浏览与 SFTP 使用 `BatchMode=yes`，应用内不会提示输入密码。

## 运行与开发

```bash
swift run Porter                 # 启动应用
swift build
swift run PorterPathValidation   # 路径、引号、sftp 批处理等轻量回归
```

### 打包 DMG（可选）

```bash
./Scripts/package-dmg.sh   # release 构建、生成 Porter.app 与 dist/Porter.dmg
```

需要本机 Xcode 命令行工具；产物输出到 `dist/`（已在 `.gitignore` 中忽略）。

## SSH 配置示例

```sshconfig
Host prod
  HostName 10.0.0.10
  User deploy
  Port 22
  IdentityFile ~/.ssh/id_ed25519
```

选择 `prod`，将默认远程目录设为例如 `~/uploads`，即可上传；用目录浏览器选路径、下载或编辑远端文件。

## 项目结构

```text
Sources/
  PorterApp/              SwiftUI、SSH 解析、远端浏览、上传下载与设置
  PorterCore/             远端路径、SFTP 批处理、SSH 封装、文件名校验
  PorterPathValidation/   PorterCore 边界断言（无独立 XCTest 目标时的回归入口）
design-package/           UI 设计语言（DESIGN.md、预览 HTML）
Scripts/                  图标渲染、DMG 打包等
Packaging/                Info.plist 等打包元数据
Assets/                   应用图标源文件
```

## 实现要点

| 能力 | 说明 |
|------|------|
| Host 列表 | `SSHConfigParser.swift`：读配置、展开 `Include`、汇总可展示 alias |
| 配置路径 | `SSHConfigPathResolver.swift`、`SSHConfigPreferencesStore.swift`：自定义 config 路径 |
| 远端列表 | `RemoteDirectoryBrowser.swift`：`ssh` 执行 `pwd` + `ls -la`，解析后展示；重命名/删除走远端 shell |
| 上传 / 下载 | `Uploader.swift`、`RemoteDownloader.swift` → `PorterSFTPBatch.swift`（`/usr/bin/sftp -b`） |
| 远端编辑 | `RemoteFileEditCoordinator.swift`：暂存、默认应用打开、保存后自动上传 |
| 路径与 shell | `RemotePath.swift`：分段、拼接、远端 `cd` 单引号策略；交互式 `ssh` 用 base64 包装远端脚本 |
| 终端启动 | `ITermLaunchConfiguration.swift`、`WarpLaunchConfiguration.swift`、系统 Terminal |
| 设计系统 | `Theme.swift`、`Components.swift`；规范见 `design-package/DESIGN.md` |

面向编码代理的约定与 UI token 摘要见根目录 [`AGENTS.md`](AGENTS.md)。

## 安全与隐私

- 不设密码仓、不内置托管私钥；认证由系统 OpenSSH 与用户配置完成。
- 勿在仓库、文档示例或提交信息中写入真实主机名、用户名、私钥路径或私人远程路径。
- 调整 `ssh` / `sftp` 参数、远端路径、`sftp -b` 批处理转义，或 AppleScript 拼接时，需覆盖空格、引号、`~`、通配符与 shell 元字符等边界情况。

## 许可与免责声明

- 本项目以 MIT 许可证发布，见根目录 [`LICENSE`](LICENSE)。
- 软件按「原样」提供；用于重要数据或生产环境前请自行评估并做好备份与验证。
