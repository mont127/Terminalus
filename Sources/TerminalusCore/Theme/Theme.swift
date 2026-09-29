import Foundation

/// Optional UI ("chrome") colors. Anything left nil is derived from the terminal palette.
public struct ThemeChrome: Codable, Equatable, Sendable {
    public var accent: String?
    public var accent2: String?
    public var sidebarBackground: String?
    public var panelBackground: String?
    public var border: String?
    public var text: String?
    public var secondaryText: String?
    public var glow: String?
    public var gradient: [String]?
    public var success: String?
    public var warning: String?
    public var danger: String?

    public init(accent: String? = nil, accent2: String? = nil, sidebarBackground: String? = nil,
                panelBackground: String? = nil, border: String? = nil, text: String? = nil,
                secondaryText: String? = nil, glow: String? = nil, gradient: [String]? = nil,
                success: String? = nil, warning: String? = nil, danger: String? = nil) {
        self.accent = accent; self.accent2 = accent2; self.sidebarBackground = sidebarBackground
        self.panelBackground = panelBackground; self.border = border; self.text = text
        self.secondaryText = secondaryText; self.glow = glow; self.gradient = gradient
        self.success = success; self.warning = warning; self.danger = danger
    }
}

/// A terminal color scheme. Colors are hex strings (`#rrggbb` or `#rrggbbaa`).
public struct Theme: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var foreground: String
    public var background: String
    public var cursor: String
    public var cursorText: String?
    public var selection: String
    public var selectionText: String?
    public var bold: String?
    public var link: String?
    /// Exactly 16 entries: black, red, green, yellow, blue, magenta, cyan, white, then the bright variants.
    public var ansi: [String]
    public var chrome: ThemeChrome?

    public init(id: String, name: String, foreground: String, background: String, cursor: String,
                cursorText: String? = nil, selection: String, selectionText: String? = nil,
                bold: String? = nil, link: String? = nil, ansi: [String], chrome: ThemeChrome? = nil) {
        self.id = id; self.name = name; self.foreground = foreground; self.background = background
        self.cursor = cursor; self.cursorText = cursorText; self.selection = selection
        self.selectionText = selectionText; self.bold = bold; self.link = link; self.ansi = ansi
        self.chrome = chrome
    }

    public var isDark: Bool { (RGBA(hex: background) ?? .black).isDark }
}

/// A theme with every color parsed and every optional chrome color derived.
public struct ResolvedTheme: Equatable, Sendable {
    public let id: String
    public let name: String
    public let isDark: Bool
    public let foreground: RGBA
    public let background: RGBA
    public let cursor: RGBA
    public let cursorText: RGBA
    public let selection: RGBA
    public let selectionText: RGBA?
    public let bold: RGBA?
    public let link: RGBA
    public let ansi: [RGBA]
    public let accent: RGBA
    public let accent2: RGBA
    public let sidebarBackground: RGBA
    public let panelBackground: RGBA
    public let border: RGBA
    public let text: RGBA
    public let secondaryText: RGBA
    public let glow: RGBA
    public let gradient: [RGBA]
    public let success: RGBA
    public let warning: RGBA
    public let danger: RGBA
    /// Categorical colors for charts, in a stable order.
    public let chartPalette: [RGBA]

    public init(_ t: Theme, accentOverride: String? = nil) {
        func c(_ s: String?, _ fallback: RGBA) -> RGBA { s.flatMap(RGBA.init(hex:)) ?? fallback }
        let fg = c(t.foreground, .white)
        let bg = c(t.background, .black)
        var ansi = t.ansi.map { RGBA(hex: $0) ?? fg }
        if ansi.count < 16 {
            let defaults = Theme.xtermDefaultANSI.map { RGBA(hex: $0)! }
            ansi += defaults[ansi.count..<16]
        }
        ansi = Array(ansi.prefix(16))
        let ch = t.chrome ?? ThemeChrome()
        self.ansi = ansi
        id = t.id
        name = t.name
        isDark = bg.isDark
        foreground = fg
        background = bg
        cursor = c(t.cursor, fg)
        cursorText = c(t.cursorText, bg)
        selection = c(t.selection, fg.withAlpha(0.3))
        selectionText = t.selectionText.flatMap(RGBA.init(hex:))
        bold = t.bold.flatMap(RGBA.init(hex:))
        link = c(t.link, ansi[12])
        accent = c(accentOverride ?? ch.accent, ansi[13])
        accent2 = c(ch.accent2, ansi[14])
        sidebarBackground = c(ch.sidebarBackground, bg.raised(0.04))
        panelBackground = c(ch.panelBackground, bg.raised(0.08))
        border = c(ch.border, fg.withAlpha(0.14))
        text = c(ch.text, fg)
        secondaryText = c(ch.secondaryText, fg.mix(bg, 0.42))
        glow = c(ch.glow, accent)
        let grad = (ch.gradient ?? []).compactMap(RGBA.init(hex:))
        gradient = grad.count >= 2 ? grad : [accent, accent2, ansi[12]]
        success = c(ch.success, ansi[10])
        warning = c(ch.warning, ansi[11])
        danger = c(ch.danger, ansi[9])
        chartPalette = [accent, accent2, ansi[10], ansi[11], ansi[12], ansi[9], ansi[13], ansi[14]]
    }
}

extension Theme {
    /// Standard xterm palette, used to pad incomplete themes.
    public static let xtermDefaultANSI = [
        "#000000", "#cd0000", "#00cd00", "#cdcd00", "#0000ee", "#cd00cd", "#00cdcd", "#e5e5e5",
        "#7f7f7f", "#ff0000", "#00ff00", "#ffff00", "#5c5cff", "#ff00ff", "#00ffff", "#ffffff",
    ]

    /// Returns a copy with a new id/name, suitable for "duplicate & edit".
    public func duplicated(id newID: String, name newName: String) -> Theme {
        var t = self
        t.id = newID
        t.name = newName
        return t
    }
}
