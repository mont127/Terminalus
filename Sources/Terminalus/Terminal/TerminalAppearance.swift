import AppKit
import SwiftTerm
import TerminalusCore

/// Everything that decides how a terminal pane looks and behaves, resolved from global settings,
/// the pane's profile and the active theme. Applying it is idempotent.
struct TerminalAppearance: Equatable {
    var theme: ResolvedTheme
    var fontFamily: String
    var fontSize: Double
    var fontWeight: FontWeightOption
    var lineSpacing: Double
    var useBrightColors: Bool
    var fontSmoothing: Bool
    var customBlockGlyphs: Bool
    var cursorShape: CursorShape
    var cursorBlink: Bool
    var cursorColor: RGBA
    var cursorTextColor: RGBA
    var hollowWhenUnfocused: Bool
    var scrollback: Int
    var optionAsMeta: Bool
    var mouseReporting: Bool
    var linkMode: LinkMode
    var bell: BellMode
    var bellSound: String
    var copyOnSelect: Bool
    var useMetal: Bool
    var scrollSensitivity: Double
    var scrollerStyle: ScrollerStyleOption
    var termName: String
    var padding: Double
    var glow: GlowSettings
    var glowColor: RGBA
    var effectsEnabled: Bool
    /// Set when the pane's profile uses a different theme than the window, so the pane paints its own background.
    var paneBackground: RGBA?

    init(settings: AppSettings, profile: Profile, theme: ResolvedTheme, ownBackground: Bool = false) {
        let t = settings.terminal
        self.theme = theme
        fontFamily = profile.fontFamily ?? t.font.family
        fontSize = profile.fontSize ?? t.font.size
        fontWeight = t.font.weight
        lineSpacing = t.font.lineSpacing
        useBrightColors = t.font.useBrightColorsForBold
        fontSmoothing = t.font.fontSmoothing
        customBlockGlyphs = t.font.customBlockGlyphs
        cursorShape = profile.cursorShape ?? t.cursor.shape
        cursorBlink = t.cursor.blink
        cursorColor = t.cursor.color.flatMap(RGBA.init(hex:)) ?? theme.cursor
        cursorTextColor = t.cursor.textColor.flatMap(RGBA.init(hex:)) ?? theme.cursorText
        hollowWhenUnfocused = t.cursor.hollowWhenUnfocused
        scrollback = max(100, t.scrollback)
        optionAsMeta = t.optionAsMeta
        mouseReporting = t.mouseReporting
        linkMode = t.linkMode
        bell = t.bell
        bellSound = t.bellSound
        copyOnSelect = t.copyOnSelect
        useMetal = t.useMetalRenderer
        scrollSensitivity = t.scrollSensitivity
        scrollerStyle = t.scrollerStyle
        termName = t.termName.isEmpty ? "xterm-256color" : t.termName
        padding = settings.window.padding
        glow = settings.effects.glow
        glowColor = settings.effects.glow.color.flatMap(RGBA.init(hex:)) ?? theme.glow
        effectsEnabled = settings.effects.enabled
        paneBackground = ownBackground ? theme.background.withAlpha(settings.window.backgroundOpacity) : nil
    }

    var cursorStyle: CursorStyle {
        switch (cursorShape, cursorBlink) {
        case (.block, true): .blinkBlock
        case (.block, false): .steadyBlock
        case (.underline, true): .blinkUnderline
        case (.underline, false): .steadyUnderline
        case (.bar, true): .blinkBar
        case (.bar, false): .steadyBar
        }
    }

    var font: NSFont { FontResolver.terminalFont(family: fontFamily, size: fontSize, weight: fontWeight) }

    func apply(to view: TerminalusTerminalView, container: TerminalContainerView, previous: TerminalAppearance? = nil) {
        let p = previous
        if p?.fontFamily != fontFamily || p?.fontSize != fontSize || p?.fontWeight != fontWeight {
            view.font = font
        }
        if p?.lineSpacing != lineSpacing { view.lineSpacing = CGFloat(lineSpacing) }
        if p?.theme != theme || p?.cursorColor != cursorColor || p?.cursorTextColor != cursorTextColor {
            view.installColors(theme.ansi.map(\.stColor))
            view.nativeForegroundColor = theme.foreground.nsColor
            // The window paints the background (with opacity, blur, images…); the terminal stays clear.
            view.nativeBackgroundColor = theme.background.nsColor
            view.caretColor = cursorColor.nsColor
            view.caretTextColor = cursorTextColor.nsColor
            view.selectedTextBackgroundColor = theme.selection.nsColor
            if let st = theme.selectionText { view.selectedTextForegroundColor = st.nsColor }
        }
        view.backgroundOpacity = 0
        if p?.useBrightColors != useBrightColors { view.useBrightColors = useBrightColors }
        if p?.fontSmoothing != fontSmoothing { view.fontSmoothing = fontSmoothing }
        if p?.customBlockGlyphs != customBlockGlyphs { view.customBlockGlyphs = customBlockGlyphs }
        if p?.cursorStyle != cursorStyle { view.getTerminal().setCursorStyle(cursorStyle) }
        view.caretViewTracksFocus = hollowWhenUnfocused
        if p?.scrollback != scrollback, p != nil { view.changeScrollback(scrollback) }
        view.optionAsMetaKey = optionAsMeta
        view.allowMouseReporting = mouseReporting
        switch linkMode {
        case .hoverWithModifier:
            view.linkReporting = .implicit
            view.linkHighlightMode = .hoverWithModifier
        case .always:
            view.linkReporting = .implicit
            view.linkHighlightMode = .always
        case .never:
            view.linkReporting = .none
        }
        view.bellMode = bell
        view.bellSoundName = bellSound
        view.copyOnSelect = copyOnSelect
        view.scrollSensitivity = CGFloat(scrollSensitivity)
        let style: NSScroller.Style = scrollerStyle == .overlay ? .overlay : .legacy
        if view.scrollerStyle != style { view.scrollerStyle = style }
        if p?.useMetal != useMetal || (p == nil && useMetal) {
            if (try? view.setUseMetal(useMetal)) == nil, useMetal {
                NSLog("Terminalus: Metal renderer unavailable, keeping the CoreGraphics renderer")
            }
        }
        container.padding = CGFloat(padding)
        container.layer?.backgroundColor = paneBackground?.cgColor
        container.applyGlow(enabled: glow.enabled && effectsEnabled, color: glowColor, radius: glow.radius, opacity: glow.opacity)
    }
}
