# PorterApp（SwiftUI 表现层）

本目录为 macOS SwiftUI 界面代码。编辑本目录下任何 `.swift` 前须落实设计规范。

## 设计规范来源（按优先级）

1. **`design-package/DESIGN.md`** — 布局、组件、动效、禁忌的唯一定稿。
2. **`.cursor/rules/porter-swiftui-design.mdc`** — 编辑本目录 `**/*.swift` 时由 Cursor 注入，内含 `@design-package/DESIGN.md`。
3. **根目录 [`AGENTS.md`](../../AGENTS.md)** — UI 工作流说明与 token 配色摘要。

## 代理工作流（顺序不可跳过）

1. 确认已命中 `porter-swiftui-design` 规则，或已用 `read_file` 完整读取 `design-package/DESIGN.md`。
2. 再编辑、新增或审阅本目录中的 Swift 文件。
3. 不得仅用根 `AGENTS.md` 中的 token 表代替 `DESIGN.md` 全文。

## 一句话原则

暖奶油画布、单一暖橙 Accent、路径/技术字段等宽、1px 发丝边框、克制层次；勿用系统默认 Accent 取代 Porter 暖橙。
