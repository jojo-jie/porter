import AppKit
import SwiftUI

extension Color {
    /// 暖色奶油画布：浅色取近似 #F8F7F2，深色用沉静的炭灰，避免标准白带来的冷感。
    static let porterCanvas = Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil
        return isDark
            ? NSColor(red: 0.118, green: 0.118, blue: 0.118, alpha: 1)
            : NSColor(red: 0.972, green: 0.969, blue: 0.949, alpha: 1)
    })

    /// 卡片/输入框表面：仅比画布高半档，靠对比关系而非阴影区分层次。
    static let porterSurface = Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil
        return isDark
            ? NSColor(red: 0.157, green: 0.157, blue: 0.157, alpha: 1)
            : NSColor(red: 1.0, green: 0.996, blue: 0.984, alpha: 1)
    })

    /// 侧栏背景：比画布略深半档的暖奶油，让 sidebar 自然凹陷而不引入冷灰。
    static let porterSidebar = Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil
        return isDark
            ? NSColor(red: 0.098, green: 0.098, blue: 0.098, alpha: 1)
            : NSColor(red: 0.951, green: 0.945, blue: 0.921, alpha: 1)
    })

    /// 侧栏行 hover / selected 背景，贴近系统设置侧栏的柔和灰色反馈。
    static let porterSidebarRowHighlight = Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil
        return isDark
            ? NSColor(white: 1.0, alpha: 0.11)
            : NSColor(white: 0.0, alpha: 0.055)
    })

    /// 1pt 发丝线，永远不喧宾夺主。
    static let porterBorder = Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil
        return isDark
            ? NSColor(white: 1.0, alpha: 0.10)
            : NSColor(white: 0.0, alpha: 0.09)
    })

    /// 单一暖橙强调色，对齐 Claude 标识色。
    static let porterAccent = Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil
        return isDark
            ? NSColor(red: 0.831, green: 0.490, blue: 0.376, alpha: 1)
            : NSColor(red: 0.800, green: 0.471, blue: 0.361, alpha: 1)
    })
}
