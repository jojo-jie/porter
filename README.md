# Porter

Porter 是一个 macOS 原生 SwiftUI 小工具，用来从本机 `~/.ssh/config` 读取可用的 SSH `Host` alias，并通过系统 `ssh` / `scp` 浏览远端目录、上传文件和下载文件。

## 功能

- 自动读取 `~/.ssh/config`，支持 `Include` 和相对路径 include。
- 展示具体 `Host` alias，忽略 `*`、`?`、`!` 等通配规则，并过滤常见代码托管服务主机。
- 在侧边栏搜索、选择主机，查看 `User`、`HostName`、`Port` 等连接信息。
- 每个主机可保存一个默认远程目录，数据保存在本机 `UserDefaults`。
- 可直接输入远程路径，也可通过远端目录浏览器按层级选择目录。
- 支持点击选择文件上传，也支持拖拽文件上传。
- 支持在远端目录浏览器中选择远端文件或目录下载到本地目录。
- 可一键打开 Terminal 并执行对应 `ssh` 命令，方便验证连接。
- 上传和下载使用系统 `/usr/bin/scp`，远端浏览使用系统 `/usr/bin/ssh`，因此会复用本机 SSH 配置、密钥、代理跳板等设置。

## 环境要求

- macOS 14 或更新版本。
- Swift Package Manager / Swift 6 工具链。
- 本机已有可用的 `~/.ssh/config`。
- 目标主机需要能通过对应 Host alias 免交互连接；远端目录浏览会使用 `BatchMode=yes`，不会弹出密码交互。

## 运行

```bash
swift run Porter
```

## 开发命令

```bash
swift build
swift run Porter
swift run PorterPathValidation
```

`PorterPathValidation` 是一个轻量校验入口，用来验证远端路径拼接、分割和 shell 引号处理的边界行为。

## SSH 配置示例

```sshconfig
Host prod
  HostName 10.0.0.10
  User deploy
  Port 22
  IdentityFile ~/.ssh/id_ed25519
```

在应用中选择 `prod`，设置默认远程目录例如 `~/uploads`，然后点击或拖拽文件上传。也可以点击目录按钮连接远端，浏览并选择目录。

## 项目结构

```text
Sources/
  PorterApp/              SwiftUI 应用入口、界面、SSH 配置解析、上传/下载逻辑
  PorterCore/             可复用远端路径与 shell 转义逻辑
  PorterPathValidation/   路径处理校验入口
```

## 实现说明

- `Sources/PorterApp/SSHConfigParser.swift` 负责读取 `~/.ssh/config`、展开 `Include` 并提取可展示的 Host alias。
- `Sources/PorterApp/Uploader.swift` 和 `Sources/PorterApp/RemoteDownloader.swift` 通过 `/usr/bin/scp -r` 执行上传和下载。
- `Sources/PorterApp/RemoteDirectoryBrowser.swift` 通过 `/usr/bin/ssh` 执行远端 `pwd` 与 `ls -la`，解析结果后展示目录列表。
- `Sources/PorterCore/RemotePath.swift` 集中处理远端路径拆分、拼接和 shell 引号。

## 安全与隐私

- Porter 不内置或保存 SSH 密钥，也不管理密码；连接行为交给系统 SSH 配置处理。
- 请不要把真实主机名、用户名、私钥路径或个人远程目录提交到仓库。
- 修改 `ssh` / `scp` 参数、远端路径拼接或 AppleScript 命令拼接时，需要特别检查空格、引号、波浪线、通配符和 shell 元字符场景。

## 许可与免责声明

- 本项目以 MIT 许可证发布，完整条款见仓库根目录的 [`LICENSE`](LICENSE)。
- 软件按「原样」提供，不作任何明示或暗示的担保；因使用或无法使用本软件而产生的任何直接或间接损失，由使用者自行承担。在用于重要数据、生产环境或合规场景前，请自行评估风险并做好备份与验证。
