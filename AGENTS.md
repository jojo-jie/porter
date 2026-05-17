# AGENTS.md

<!-- AGENTS-MD-SYNC:START -->
## Agent 工作约定（自动维护）

- 最近生成时间（UTC）：`2026-05-17 13:49:18Z`
- 生成脚本：`agents-md-sync/scripts/sync_agents_md.py`
- 官方参考：`https://agents.md/`，`https://github.com/agentsmd/agents.md`

### 项目概览
- 项目名称：`porter`
- 检测到的技术栈：`Unknown/Custom`
- 检测到的工作区包数量：`0`
- 仓库结构提示：`Assets, Packaging, Scripts, Sources, Tests, design-package`

### 指令优先级
- 用户在对话中的明确指令优先于本文件。
- 处理局部目录时，优先遵循目录树中最近的 `AGENTS.md`。
- README 和贡献文档作为补充上下文；如有冲突，以更高优先级指令为准。

### 开发环境提示
- 除非下方命令另有说明，默认在当前适用范围根目录执行命令。
- Swift Package Manager 管理的 macOS SwiftUI 应用；入口 `Sources/PorterApp/PorterApp.swift`，共享逻辑在 `Sources/PorterCore/`。
- 远端浏览与 shell 操作用 `/usr/bin/ssh`（`PorterSSH.swift`）；上传/下载用 `/usr/bin/sftp -b` 批处理（`PorterSFTPBatch.swift`，`BatchMode=yes`）。
- 路径拼接、远端 `cd` 引号与 SFTP 转义：`Sources/PorterCore/RemotePath.swift`；快速回归 `swift run PorterPathValidation`。
- 改 UI 前阅读 `design-package/DESIGN.md`；连接问题用本机 `~/.ssh/config` 与同 Host 的 `ssh` / `sftp` 对照。
- 发布 DMG：`Scripts/package-dmg.sh`（release 构建 + `.app` + 磁盘映像，产物在 `dist/`）。

### 常用命令
- 除非特别说明，以下命令都在当前适用范围根目录执行。
- dev: `swift run Porter`
- build: `swift build`
- test: `swift run PorterPathValidation`

### 测试说明
- 针对本次修改的文件运行最相关的检查。
- 修复由本次修改引入的测试、类型、lint 和格式化失败。
- 行为发生变化时，补充或更新测试。

### 代码风格
- 遵循所编辑文件的既有代码风格。
- 修改范围保持聚焦，避免无关重写或大范围格式化噪音。
- 遵循现有 SwiftUI 与 `@MainActor` 状态管理写法，保持 UI 状态更新在主 actor 上。
- 修改 SSH 配置解析、远端路径、SFTP 批处理脚本、shell 转义或 AppleScript 拼接时，优先在 `PorterPathValidation` 补充边界断言。

### 安全注意事项
- 不提交密钥、令牌、凭据或本地环境文件。
- 在信任边界校验输入，并保留既有鉴权检查。
- 不要提交真实主机名、私钥路径、用户名、远程目录或其他个人 SSH 配置。
- 涉及 `ssh`/`sftp` 参数、`sftp -b` 脚本、远端路径、shell 引号或 AppleScript 拼接时，必须避免命令注入。

### 约束规则
- 优先遵循用户指令，其次遵循离当前目录最近的 AGENTS.md 规则。
- 修改范围保持聚焦，避免顺手做无关重构。
- 避免直接编辑生成物或依赖目录：`node_modules, dist, build, .git, .build, .swiftpm, DerivedData`
- 行为发生变化时，补充或更新测试。
- 当子目录工作流明显分化时，再补充嵌套的 AGENTS.md。

### PR / 交付说明
- 交付前说明行为变化、已执行验证和已知缺口。
- 说明行为变更、已知限制，以及是否已运行 `swift build` / `swift run PorterPathValidation` 与未运行原因。

### 验证清单
- 交付前运行最相关的 build/typecheck/test/lint/format 命令；如果没有标准命令，就执行最接近的可用验证步骤。
- 明确说明已验证和未验证的内容。
- 涉及上传、下载、远端浏览、重命名/删除或命令构造时，检查空格、引号、波浪线、通配符与 shell 元字符场景。
<!-- AGENTS-MD-SYNC:END -->

---

## 项目说明（手动维护）

- **README**：面向使用者与贡献者的产品说明；**本文**：面向自动化代理的任务约定与风险提示。
- **单一 Swift Package**：无嵌套子包时的默认约定以根目录为准。
- **个人数据**：文档、断言与示例中勿出现真实主机名、用户、密钥路径或个人远程路径。

### UI 设计与上下文（自动化代理）

- **规则注入范围**：工作区若将本文件设为「始终应用 / always applied」，只会把 **AGENTS.md 正文**注入对话上下文；`design-package/DESIGN.md` **不会**仅因文中链接而自动附带。人工在 Cursor 里做 UI 相关对话时，请用 **`@design-package/DESIGN.md`** 显式附加该文件；自动化代理在改 UI 前须用 `read_file` 读取该路径。
- **UI 改动前的必读步骤**：在编辑、新增或审阅 **`Sources/PorterApp/**/*.swift`**（及其他 SwiftUI 表现层）前，**必须先完整阅读** [design-package/DESIGN.md](design-package/DESIGN.md)（代理侧用 `read_file` 指向 `design-package/DESIGN.md`）；布局、间距、圆角节奏、组件细则、动效与禁忌以该全文为准，不得只凭本节摘录实现。
- **设计 token 快照（轻量摘录）**：下列色值用于在仅注入本文件时仍能对齐配色；与 `DESIGN.md` 冲突时以仓库内 `DESIGN.md` 为准。

| 角色 | 浅色 | 深色 |
| --- | --- | --- |
| Canvas | `#F8F7F2` | `#1E1E1E` |
| Surface | `#FFFEFB` | `#282828` |
| Sidebar | `#F3F1EB` | `#191919` |
| Accent | `#CC785C` | `#D47D60` |
| Border | `rgba(0,0,0,0.09)` | `rgba(255,255,255,0.10)` |
| Row Highlight | `rgba(0,0,0,0.055)` | `rgba(255,255,255,0.11)` |
| Primary Text | `#24211D` | `#F1ECE5` |
| Secondary Text | `#68625A` | `#B8B0A6` |
| Tertiary Text | `#9B948A` | `#817A72` |

- **一句话原则**：暖奶油画布、**单一暖橙强调色**（Accent）、系统字体 + **路径/技术字段等宽**、**1px 发丝边框**与连续圆角、克制层次；状态色沿用系统语义，避免与主 Accent 竞争。
