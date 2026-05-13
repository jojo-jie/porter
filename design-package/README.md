# Porter Design Package

这是一套从当前 Porter macOS SwiftUI 项目中提取的设计规范包，可用于后续界面生成、重构讨论或保持 AI 产出的视觉一致性。

来源与可信度：本包主要依据 `Sources/PorterApp/Theme.swift`、共享 SwiftUI 组件、主界面、设置页、远端目录浏览器，以及项目 `README.md` 的产品说明生成。没有使用截图或外部参考 URL，因此它是「从代码推断并整理」的设计系统，而不是官方品牌手册。

| 文件 | 说明 |
| --- | --- |
| `DESIGN.md` | 可直接喂给 Agent 的完整设计语言、组件规范和提示词 |
| `README.md` | 本设计包的来源、用途与文件说明 |
| `preview.html` | 浅色模式的本地可视化预览 |
| `preview-dark.html` | 深色模式的同品牌暗色适配预览 |

使用方式：在后续 UI 任务中引用 `DESIGN.md`，要求 Agent 遵守其中的色板、排版、布局、组件和交互节奏。若要实现真实 SwiftUI 界面，应以代码中的当前 token 为准，并用本包作为视觉与文案方向的统一参考。
