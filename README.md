# Porter

一个 macOS 原生小工具，用来读取本机 `~/.ssh/config` 中的 `Host` alias，并把文件上传到每个主机配置的默认远程目录。

## 功能

- 自动读取 `~/.ssh/config`，支持 `Include`。
- 展示具体 `Host` alias，忽略 `*`、`?`、`!` 等通配规则。
- 每个主机可保存一个默认远程目录。
- 支持点击选择文件上传，也支持拖拽文件上传。
- 上传使用系统 `/usr/bin/scp`，因此会复用本机 SSH 配置、密钥、代理跳板等设置。

## 运行

```bash
swift run Porter
```

## SSH 配置示例

```sshconfig
Host prod
  HostName 10.0.0.10
  User deploy
  Port 22
  IdentityFile ~/.ssh/id_ed25519
```

在应用中选择 `prod`，设置默认远程目录例如 `~/uploads`，然后点击或拖拽文件上传。
