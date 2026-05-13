# AGENTS.md

<!-- AGENTS-MD-SYNC:START -->
## Agent 工作约定（自动维护）

- 最近生成时间（UTC）：`2026-05-13 00:00:00Z`
- 生成脚本：`agents-md-sync/scripts/sync_agents_md.py`
- 官方参考：[agents.md](https://agents.md/)、[agentsmd/agents.md](https://github.com/agentsmd/agents.md)

### 项目概览

- 项目名称：`porter`
- 技术栈：SwiftPM，macOS SwiftUI 可执行目标 `Porter`，校验入口 `PorterPathValidation`
- 仓库布局：`Sources/`（`PorterApp`、`PorterCore`、`PorterPathValidation`），无顶层 `Tests` 目标时请依赖 `PorterPathValidation` 做快速回归

### 指令优先级

- 用户在对话中的明确指令优先于本文件。
- 就近的嵌套 `AGENTS.md`（若未来添加）优先于根级。
- 与 README 冲突时，以用户在对话中的指令为准；否则 README 可作产品面向的补充说明。

### 开发环境与调试

- 默认在仓库根目录执行命令。
- 入口：`Sources/PorterApp/PorterApp.swift`。
- 远端路径：`Sources/PorterCore/RemotePath.swift`。
- 上传下载：`Sources/PorterCore/PorterSFTPBatch.swift`（`/usr/bin/sftp -b`，`BatchMode`）；远端 shell 仍为 `/usr/bin/ssh`。
- 调试连接问题时优先用本机 `~/.ssh/config` 与终端里同 Host 的 `ssh` / `sftp` 对照。

### 常用命令

- dev：`swift run Porter`
- build：`swift build`
- regression：`swift run PorterPathValidation`

### 测试与变更

- 改动路径拼接、远端 `cd` 引号、SFTP batch 路径转义或 SSH 解析时，运行 `swift run PorterPathValidation` 并酌情补充断言。
- 修复本次改动引入的编译与校验失败。
- UI 保持在 `@MainActor` 上与现有 SwiftUI 状态风格一致。

### 代码与安全

- 不提交密钥、令牌、真实个人 SSH 片段或 `.env` 类机密。
- 信任边界校验用户与配置输入；不因「方便调试」绕过鉴权语义。
- 涉及 `ssh`/`sftp` 参数、`sftp -b` 脚本内容、远端路径、shell 引号或 AppleScript 拼接时，必须避免命令注入。

### 仓库约束

- 勿编辑生成产物目录：`node_modules`、`dist`、`build`、`.git`、`.build`、`.swiftpm`、`DerivedData`。
- 改动保持最小必要范围，避免无关大段格式化。
- 子目录若日后出现独立构建流程，再考虑嵌套 `AGENTS.md`。

### 交付（PR / 代理任务）

- 说明行为变更、已知限制与已执行的验证命令。
- 明确写出是否已运行 `swift build` / `PorterPathValidation` 以及未运行的原因。
<!-- AGENTS-MD-SYNC:END -->

---

## 项目说明（手动维护）

- **README**：面向使用者与贡献者的产品说明；**本文**：面向自动化代理的任务约定与风险提示。
- **单一 Swift Package**：无嵌套子包时的默认约定以根目录为准。
- **个人数据**：文档、断言与示例中勿出现真实主机名、用户、密钥路径或个人远程路径。
