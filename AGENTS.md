# AGENTS.md

<!-- AGENTS-MD-SYNC:START -->
## Agent 工作约定（自动维护）

- 最近生成时间（UTC）：`2026-05-11 08:06:50Z`
- 生成脚本：`agents-md-sync/scripts/sync_agents_md.py`
- 官方参考：`https://agents.md/`，`https://github.com/agentsmd/agents.md`

### 项目概览
- 项目名称：`porter`
- 检测到的技术栈：`Unknown/Custom`
- 检测到的工作区包数量：`0`
- 仓库结构提示：`Sources`

### 指令优先级
- 用户在对话中的明确指令优先于本文件。
- 处理局部目录时，优先遵循目录树中最近的 `AGENTS.md`。
- README 和贡献文档作为补充上下文；如有冲突，以更高优先级指令为准。

### 开发环境提示
- 除非下方命令另有说明，默认在当前适用范围根目录执行命令。
- 这是一个 Swift Package Manager 管理的 macOS SwiftUI 工具，入口在 `Sources/PorterApp/PorterApp.swift`。
- 本应用读取本机 `~/.ssh/config` 并调用系统 `/usr/bin/scp`，调试上传行为时优先使用本机 SSH 配置验证。

### 常用命令
- 除非特别说明，以下命令都在当前适用范围根目录执行。
- dev: `swift run Porter`
- build: `swift build`

### 测试说明
- 针对本次修改的文件运行最相关的检查。
- 修复由本次修改引入的测试、类型、lint 和格式化失败。
- 行为发生变化时，补充或更新测试。

### 代码风格
- 遵循所编辑文件的既有代码风格。
- 修改范围保持聚焦，避免无关重写或大范围格式化噪音。
- 遵循现有 SwiftUI 与 `@MainActor` 状态管理写法，保持 UI 状态更新在主 actor 上。
- 修改 SSH 配置解析、shell 转义或 AppleScript 拼接逻辑时，优先补充边界案例验证。

### 安全注意事项
- 不提交密钥、令牌、凭据或本地环境文件。
- 在信任边界校验输入，并保留既有鉴权检查。
- 不要提交真实主机名、私钥路径、用户名、远程目录或其他个人 SSH 配置。
- 涉及 `scp` 参数、远程路径、shell 转义、AppleScript 命令拼接时，必须避免引入命令注入风险。

### 约束规则
- 优先遵循用户指令，其次遵循离当前目录最近的 AGENTS.md 规则。
- 修改范围保持聚焦，避免顺手做无关重构。
- 避免直接编辑生成物或依赖目录：`node_modules, dist, build, .git, .build, .swiftpm, DerivedData`
- 行为发生变化时，补充或更新测试。
- 当子目录工作流明显分化时，再补充嵌套的 AGENTS.md。

### PR / 交付说明
- 交付前说明行为变化、已执行验证和已知缺口。
- 交接时说明是否运行了 `swift build`，以及未运行的验证项和原因。

### 验证清单
- 交付前运行最相关的 build/typecheck/test/lint/format 命令；如果没有标准命令，就执行最接近的可用验证步骤。
- 明确说明已验证和未验证的内容。
- 涉及上传路径或命令构造时，检查空格、引号、波浪线、通配符和 shell 元字符场景。
<!-- AGENTS-MD-SYNC:END -->

## 项目说明（手动维护）
- 在这里补充不会被同步脚本覆盖的项目特定说明。
