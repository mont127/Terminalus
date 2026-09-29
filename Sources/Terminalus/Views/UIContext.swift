import SwiftUI
import TerminalusCore

/// Theme + UI settings handed down the SwiftUI tree.
struct UIContext {
    var theme: ResolvedTheme
    var appearance: AppearanceSettings
    var stats = StatsSettings()

    var scale: CGFloat { CGFloat(appearance.density.scale) }
    var fontSize: CGFloat { CGFloat(appearance.uiFontSize) }
    var design: Font.Design { appearance.uiFontDesign.swiftUI }
    var radius: CGFloat { CGFloat(appearance.cornerRadius) }

    func font(_ delta: CGFloat = 0, weight: Font.Weight = .regular) -> Font {
        .system(size: max(7, fontSize + delta), weight: weight, design: design)
    }

    /// Numbers, paths and other data: always monospaced with tabular digits.
    func mono(_ delta: CGFloat = 0, weight: Font.Weight = .regular) -> Font {
        .system(size: max(7, fontSize + delta), weight: weight, design: .monospaced)
    }

    /// Panel and section titles.
    var sectionFont: Font { font(-1, weight: .semibold) }

    var dockFill: Color { theme.sidebarBackground.withAlpha(appearance.panelOpacity).color }
    var panelFill: Color { theme.panelBackground.withAlpha(appearance.panelOpacity).color }
    var hairline: Color { appearance.showPanelBorders ? theme.border.color : .clear }
    var border: Color { hairline }
    var text: Color { theme.text.color }
    var secondary: Color { theme.secondaryText.color }
    var tertiary: Color { theme.secondaryText.withAlpha(0.6).color }
    var accent: Color { theme.accent.color }
    var accent2: Color { theme.accent2.color }
    var track: Color { theme.text.withAlpha(0.07).color }
    var hover: Color { theme.text.withAlpha(0.06).color }
    var selection: Color { theme.text.withAlpha(0.09).color }
}

private struct UIContextKey: EnvironmentKey {
    static let defaultValue = UIContext(theme: ResolvedTheme(Theme.builtins[0]), appearance: AppearanceSettings())
}

extension EnvironmentValues {
    var ui: UIContext {
        get { self[UIContextKey.self] }
        set { self[UIContextKey.self] = newValue }
    }
}

/// A widget container: a flat section with a hairline under it, or a rounded card.
struct Card<Content: View>: View {
    @Environment(\.ui) private var ui
    var padding: CGFloat = 10
    @ViewBuilder var content: Content

    var body: some View {
        switch ui.appearance.widgetChrome {
        case .flat:
            VStack(spacing: 0) {
                content
                    .padding(.horizontal, 12 * ui.scale)
                    .padding(.vertical, padding * ui.scale)
                Rectangle().fill(ui.hairline).frame(height: 1)
            }
        case .cards:
            content
                .padding(padding * ui.scale)
                .background(RoundedRectangle(cornerRadius: ui.radius, style: .continuous).fill(ui.panelFill))
                .overlay(
                    RoundedRectangle(cornerRadius: ui.radius, style: .continuous)
                        .strokeBorder(ui.appearance.glowingBorders ? ui.accent.opacity(0.3) : ui.hairline, lineWidth: 1)
                )
                .shadow(color: ui.appearance.glowingBorders ? ui.accent.opacity(0.18) : .clear, radius: 6)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
        }
    }
}

/// Small borderless icon button used in panel headers.
struct HeaderIconButton: View {
    @Environment(\.ui) private var ui
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .regular))
                .frame(width: 20, height: 18)
                .background(RoundedRectangle(cornerRadius: 4).fill(hovering ? ui.hover : .clear))
        }
        .buttonStyle(.plain)
        .foregroundStyle(hovering ? ui.text : ui.secondary)
        .onHover { hovering = $0 }
        .help(help)
    }
}
