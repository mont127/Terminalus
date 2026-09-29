import AppKit
import SwiftUI
import UniformTypeIdentifiers
import TerminalusCore

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 940, height: 680),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "Terminalus Settings"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 760, height: 480)
        let host = NSHostingView(rootView: SettingsRoot())
        host.sizingOptions = []
        window.contentView = host
        window.center()
        window.setFrameAutosaveName("TerminalusSettings")
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func windowWillClose(_ notification: Notification) {
        KeybindingManager.shared.suspended = false
    }
}

enum SettingsPane: String, CaseIterable, Identifiable {
    case general = "General"
    case appearance = "Appearance"
    case themes = "Themes"
    case terminal = "Terminal"
    case window = "Window & Background"
    case effects = "Effects"
    case layout = "Layout"
    case tree = "File Tree"
    case stats = "Stats & Widgets"
    case editor = "Editor"
    case panels = "Panels"
    case profiles = "Profiles"
    case keys = "Key Bindings"
    case advanced = "Advanced"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "paintbrush"
        case .themes: "swatchpalette"
        case .terminal: "terminal"
        case .window: "macwindow"
        case .effects: "sparkles"
        case .layout: "rectangle.3.group"
        case .tree: "folder"
        case .stats: "chart.xyaxis.line"
        case .editor: "chevron.left.forwardslash.chevron.right"
        case .panels: "rectangle.split.3x1"
        case .profiles: "person.2"
        case .keys: "keyboard"
        case .advanced: "wrench.and.screwdriver"
        }
    }
}

struct SettingsRoot: View {
    @State private var pane: SettingsPane = .appearance
    @State private var search = ""

    var body: some View {
        let app = AppState.shared
        let ui = UIContext(theme: app.uiTheme, appearance: app.settings.appearance)
        NavigationSplitView {
            List(SettingsPane.allCases, selection: $pane) { p in
                Label(p.rawValue, systemImage: p.symbol).tag(p)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
        } detail: {
            Group {
                switch pane {
                case .general: GeneralPane()
                case .appearance: AppearancePane()
                case .themes: ThemesPane()
                case .terminal: TerminalPane()
                case .window: WindowPane()
                case .effects: EffectsPane()
                case .layout: LayoutPane()
                case .tree: TreePane()
                case .stats: StatsPane()
                case .editor: EditorPane()
                case .panels: PanelsPane()
                case .profiles: ProfilesPane()
                case .keys: KeyBindingsPane()
                case .advanced: AdvancedPane()
                }
            }
            .navigationTitle(pane.rawValue)
        }
        .environment(\.ui, ui)
        .tint(ui.accent)
        .onReceive(NotificationCenter.default.publisher(for: .terminalusSettingsPane)) { note in
            if let n = note.object as? String, let p = SettingsPane.allCases.first(where: { $0.rawValue == n || "\($0)" == n }) { pane = p }
        }
    }
}

// MARK: - Shared controls

/// Slider with a label and a live value readout.
struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double? = nil
    var format: (Double) -> String = { String(format: "%.2f", $0) }

    var body: some View {
        LabeledContent(title) {
            HStack {
                if let step {
                    Slider(value: $value, in: range, step: step)
                } else {
                    Slider(value: $value, in: range)
                }
                Text(format(value)).monospacedDigit().frame(width: 64, alignment: .trailing).foregroundStyle(.secondary)
            }
        }
    }
}

/// A hex color edited with the system color picker.
struct HexColorPicker: View {
    let title: String
    @Binding var hex: String
    var supportsOpacity = true

    var body: some View {
        ColorPicker(title, selection: Binding(
            get: { RGBA(hex: hex)?.color ?? .black },
            set: { hex = $0.rgba.hex }
        ), supportsOpacity: supportsOpacity)
    }
}

/// An optional hex override: off = use the theme's color.
struct OptionalColorRow: View {
    let title: String
    @Binding var hex: String?
    var fallback: RGBA

    var body: some View {
        LabeledContent(title) {
            HStack {
                Toggle("Custom", isOn: Binding(get: { hex != nil }, set: { hex = $0 ? fallback.hex : nil }))
                    .toggleStyle(.checkbox)
                if hex != nil {
                    ColorPicker("", selection: Binding(
                        get: { RGBA(hex: hex ?? "")?.color ?? fallback.color },
                        set: { hex = $0.rgba.hex }
                    ))
                    .labelsHidden()
                } else {
                    RoundedRectangle(cornerRadius: 4).fill(fallback.color).frame(width: 36, height: 18)
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.secondary.opacity(0.4)))
                    Text("from theme").foregroundStyle(.secondary).font(.caption)
                }
            }
        }
    }
}

struct EnumPicker<E: SettingsEnum>: View {
    let title: String
    @Binding var value: E

    var body: some View {
        Picker(title, selection: $value) {
            ForEach(E.allCases) { e in Text(e.label).tag(e) }
        }
    }
}

extension SettingsStore {
    /// Binding into the settings struct by key path.
    func binding<T>(_ kp: WritableKeyPath<AppSettings, T>) -> Binding<T> {
        Binding(get: { self.settings[keyPath: kp] }, set: { v in self.update { $0[keyPath: kp] = v } })
    }
}

private var store: SettingsStore { AppState.shared.settingsStore }

// MARK: - General

struct GeneralPane: View {
    var body: some View {
        let s = store.settings
        Form {
            Section("Startup") {
                Picker("Default profile", selection: store.binding(\.defaultProfileID)) {
                    ForEach(s.profiles) { p in Text(p.name).tag(p.id) }
                }
                Toggle("Shell integration (reports directory and commands; zsh and bash)", isOn: store.binding(\.terminal.shellIntegration))
                TextField("TERM", text: store.binding(\.terminal.termName))
            }
            Section("Closing") {
                EnumPicker(title: "Confirm before closing", value: store.binding(\.terminal.confirmClose))
                EnumPicker(title: "When the shell exits", value: store.binding(\.terminal.onExit))
            }
            Section("Tabs") {
                EnumPicker(title: "Tab title shows", value: store.binding(\.terminal.tabTitle))
            }
            Section("Notifications") {
                Toggle("Notify when a long command finishes in the background", isOn: store.binding(\.terminal.notifyLongCommands))
                SliderRow(title: "Long command threshold", value: store.binding(\.terminal.longCommandSeconds), range: 2...300, step: 1) { "\(Int($0)) s" }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Appearance

struct AppearancePane: View {
    @Environment(\.ui) private var ui

    var body: some View {
        let s = store.settings
        Form {
            Section("Theme") {
                ThemeGrid(selected: s.appearance.themeID) { id in
                    store.update {
                        $0.appearance.themeID = id
                        $0.appearance.followSystemAppearance = false
                    }
                }
                Toggle("Follow system light/dark mode", isOn: store.binding(\.appearance.followSystemAppearance))
                if s.appearance.followSystemAppearance {
                    themePicker("Light theme", store.binding(\.appearance.lightThemeID))
                    themePicker("Dark theme", store.binding(\.appearance.darkThemeID))
                }
                OptionalColorRow(title: "Accent color", hex: store.binding(\.appearance.accentOverride),
                                 fallback: ResolvedTheme(AppState.shared.themes.theme(id: s.appearance.themeID)).accent)
            }
            Section("Interface") {
                EnumPicker(title: "UI font", value: store.binding(\.appearance.uiFontDesign))
                SliderRow(title: "UI font size", value: store.binding(\.appearance.uiFontSize), range: 9...18, step: 0.5) { String(format: "%.1f pt", $0) }
                EnumPicker(title: "Density", value: store.binding(\.appearance.density))
                SliderRow(title: "Corner radius", value: store.binding(\.appearance.cornerRadius), range: 0...24, step: 1) { "\(Int($0)) pt" }
                SliderRow(title: "Side panel opacity", value: store.binding(\.appearance.panelOpacity), range: 0...1) { Fmt.percent($0) }
                EnumPicker(title: "Stats widgets", value: store.binding(\.appearance.widgetChrome))
                Toggle("Panel borders", isOn: store.binding(\.appearance.showPanelBorders))
                Toggle("Glowing borders", isOn: store.binding(\.appearance.glowingBorders))
                Toggle("Animations", isOn: store.binding(\.appearance.animateUI))
            }
        }
        .formStyle(.grouped)
    }

    private func themePicker(_ title: String, _ b: Binding<String>) -> some View {
        Picker(title, selection: b) {
            ForEach(AppState.shared.themes.all) { t in Text(t.name).tag(t.id) }
        }
    }
}

/// Clickable swatches of every theme.
struct ThemeGrid: View {
    let selected: String
    let onSelect: (String) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
            ForEach(AppState.shared.themes.all) { t in
                ThemeSwatch(theme: t, selected: t.id == selected)
                    .onTapGesture { onSelect(t.id) }
            }
        }
        .padding(.vertical, 4)
    }
}

struct ThemeSwatch: View {
    let theme: Theme
    let selected: Bool

    var body: some View {
        let r = ResolvedTheme(theme)
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 0) {
                Text("❯ ").foregroundStyle(r.ansi[10].color)
                Text("ls ").foregroundStyle(r.foreground.color)
                Text("~/src").foregroundStyle(r.ansi[12].color)
            }
            .font(.system(size: 11, design: .monospaced))
            HStack(spacing: 2) {
                ForEach(0..<8, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2).fill(r.ansi[i + 8].color).frame(height: 8)
                }
            }
            Text(theme.name).font(.system(size: 10, weight: .semibold)).foregroundStyle(r.foreground.color.opacity(0.8)).lineLimit(1)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(r.background.color))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(selected ? r.accent.color : Color.secondary.opacity(0.25), lineWidth: selected ? 2.5 : 1))
        .shadow(color: selected ? r.accent.color.opacity(0.6) : .clear, radius: 6)
        .contentShape(Rectangle())
    }
}

// MARK: - Terminal

struct TerminalPane: View {
    var body: some View {
        let s = store.settings
        Form {
            Section("Font") {
                Picker("Family", selection: store.binding(\.terminal.font.family)) {
                    Text("System Monospaced (SF Mono)").tag("")
                    Divider()
                    ForEach(FontResolver.monospacedFamilies, id: \.self) { f in Text(f).tag(f) }
                }
                SliderRow(title: "Size", value: store.binding(\.terminal.font.size), range: 8...36, step: 0.5) { String(format: "%.1f pt", $0) }
                EnumPicker(title: "Weight", value: store.binding(\.terminal.font.weight))
                SliderRow(title: "Line spacing", value: store.binding(\.terminal.font.lineSpacing), range: 0.8...2, step: 0.05) { String(format: "%.2f×", $0) }
                Toggle("Use bright colors for bold text", isOn: store.binding(\.terminal.font.useBrightColorsForBold))
                Toggle("Font smoothing", isOn: store.binding(\.terminal.font.fontSmoothing))
                Toggle("Custom box-drawing and block glyphs", isOn: store.binding(\.terminal.font.customBlockGlyphs))
            }
            Section("Cursor") {
                EnumPicker(title: "Shape", value: store.binding(\.terminal.cursor.shape))
                Toggle("Blink", isOn: store.binding(\.terminal.cursor.blink))
                OptionalColorRow(title: "Color", hex: store.binding(\.terminal.cursor.color), fallback: AppState.shared.uiTheme.cursor)
                OptionalColorRow(title: "Text under cursor", hex: store.binding(\.terminal.cursor.textColor), fallback: AppState.shared.uiTheme.cursorText)
                Toggle("Hollow cursor when the pane is not focused", isOn: store.binding(\.terminal.cursor.hollowWhenUnfocused))
            }
            Section("Behavior") {
                Stepper("Scrollback: \(s.terminal.scrollback) lines", value: store.binding(\.terminal.scrollback), in: 500...1_000_000, step: 5000)
                Toggle("Use ⌥ as Meta key", isOn: store.binding(\.terminal.optionAsMeta))
                Toggle("Copy on select", isOn: store.binding(\.terminal.copyOnSelect))
                Toggle("Allow mouse reporting (vim, htop, tmux…)", isOn: store.binding(\.terminal.mouseReporting))
                EnumPicker(title: "Links", value: store.binding(\.terminal.linkMode))
                SliderRow(title: "Scroll sensitivity", value: store.binding(\.terminal.scrollSensitivity), range: 0.2...4) { String(format: "%.1f×", $0) }
                EnumPicker(title: "Scroller", value: store.binding(\.terminal.scrollerStyle))
            }
            Section("Bell") {
                EnumPicker(title: "Bell", value: store.binding(\.terminal.bell))
                Picker("Sound", selection: store.binding(\.terminal.bellSound)) {
                    ForEach(["Tink", "Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero", "Morse", "Ping", "Pop", "Purr", "Sosumi", "Submarine"], id: \.self) {
                        Text($0).tag($0)
                    }
                }
                Button("Play") { NSSound(named: NSSound.Name(s.terminal.bellSound))?.play() }
            }
            Section("Rendering") {
                Toggle("Metal renderer (experimental)", isOn: store.binding(\.terminal.useMetalRenderer))
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Window & background

struct WindowPane: View {
    @State private var gradientColorIndex = 0

    var body: some View {
        let s = store.settings
        Form {
            Section("Window") {
                EnumPicker(title: "Title bar", value: store.binding(\.window.titlebar))
                Toggle("Show window title", isOn: store.binding(\.window.showTitleText))
                SliderRow(title: "Background opacity", value: store.binding(\.window.backgroundOpacity), range: 0...1) { Fmt.percent($0) }
                Toggle("Blur what's behind the window", isOn: store.binding(\.window.blur))
                EnumPicker(title: "Blur material", value: store.binding(\.window.blurMaterial))
                SliderRow(title: "Terminal padding", value: store.binding(\.window.padding), range: 0...40, step: 1) { "\(Int($0)) pt" }
                Toggle("Always on top", isOn: store.binding(\.window.alwaysOnTop))
            }
            Section("Background image") {
                LabeledContent("Image") {
                    HStack {
                        Text(s.background.image.path.isEmpty ? "None" : Paths.abbreviate(s.background.image.path))
                            .lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                        Button("Choose…") { chooseImage() }
                        if !s.background.image.path.isEmpty { Button("Remove") { store.update { $0.background.image.path = "" } } }
                    }
                }
                EnumPicker(title: "Fit", value: store.binding(\.background.image.mode))
                SliderRow(title: "Opacity", value: store.binding(\.background.image.opacity), range: 0...1) { Fmt.percent($0) }
                SliderRow(title: "Blur", value: store.binding(\.background.image.blur), range: 0...40, step: 1) { "\(Int($0))" }
                SliderRow(title: "Saturation", value: store.binding(\.background.image.saturation), range: 0...2) { String(format: "%.2f", $0) }
            }
            Section("Animated gradient") {
                Toggle("Enabled", isOn: store.binding(\.background.gradient.enabled))
                EnumPicker(title: "Style", value: store.binding(\.background.gradient.style))
                Toggle("Animate", isOn: store.binding(\.background.gradient.animated))
                SliderRow(title: "Speed", value: store.binding(\.background.gradient.speed), range: 0...1) { String(format: "%.2f", $0) }
                SliderRow(title: "Opacity", value: store.binding(\.background.gradient.opacity), range: 0...1) { Fmt.percent($0) }
                LabeledContent("Colors") {
                    HStack {
                        if s.background.gradient.colors.isEmpty {
                            Text("From theme").foregroundStyle(.secondary)
                            Button("Customize") { store.update { $0.background.gradient.colors = AppState.shared.uiTheme.gradient.map(\.hex) } }
                        } else {
                            ForEach(s.background.gradient.colors.indices, id: \.self) { i in
                                ColorPicker("", selection: Binding(
                                    get: { RGBA(hex: store.settings.background.gradient.colors[safe: i] ?? "")?.color ?? .black },
                                    set: { c in store.update { if $0.background.gradient.colors.indices.contains(i) { $0.background.gradient.colors[i] = c.rgba.hex } } }
                                )).labelsHidden()
                            }
                            Button { store.update { $0.background.gradient.colors.append("#ffffff") } } label: { Image(systemName: "plus") }
                            Button { store.update { if $0.background.gradient.colors.count > 2 { $0.background.gradient.colors.removeLast() } } } label: { Image(systemName: "minus") }
                            Button("Use theme") { store.update { $0.background.gradient.colors = [] } }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            store.update { $0.background.image.path = url.path }
        }
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

// MARK: - Effects

struct EffectsPane: View {
    var body: some View {
        Form {
            Section {
                Toggle("Enable effects", isOn: store.binding(\.effects.enabled))
                Toggle("Pause animations when the window is inactive", isOn: store.binding(\.effects.pauseWhenInactive))
                SliderRow(title: "Dim unfocused panes", value: store.binding(\.effects.inactivePaneDim), range: 0...0.7) { Fmt.percent($0) }
            }
            Section("Text glow") {
                Toggle("Glow", isOn: store.binding(\.effects.glow.enabled))
                OptionalColorRow(title: "Glow color", hex: store.binding(\.effects.glow.color), fallback: AppState.shared.uiTheme.glow)
                SliderRow(title: "Radius", value: store.binding(\.effects.glow.radius), range: 0...20, step: 0.5) { String(format: "%.1f", $0) }
                SliderRow(title: "Intensity", value: store.binding(\.effects.glow.opacity), range: 0...1) { Fmt.percent($0) }
            }
            Section("CRT scanlines") {
                Toggle("Scanlines", isOn: store.binding(\.effects.scanlines.enabled))
                SliderRow(title: "Opacity", value: store.binding(\.effects.scanlines.opacity), range: 0...0.6) { Fmt.percent($0) }
                SliderRow(title: "Spacing", value: store.binding(\.effects.scanlines.spacing), range: 2...8, step: 0.5) { String(format: "%.1f pt", $0) }
                SliderRow(title: "Thickness", value: store.binding(\.effects.scanlines.thickness), range: 0.5...4, step: 0.5) { String(format: "%.1f pt", $0) }
                Toggle("Rolling refresh band", isOn: store.binding(\.effects.scanlines.animated))
            }
            Section("Vignette") {
                Toggle("Vignette", isOn: store.binding(\.effects.vignette.enabled))
                SliderRow(title: "Intensity", value: store.binding(\.effects.vignette.intensity), range: 0...0.9) { Fmt.percent($0) }
            }
            Section("Film grain & flicker") {
                Toggle("Grain", isOn: store.binding(\.effects.noise.enabled))
                SliderRow(title: "Grain amount", value: store.binding(\.effects.noise.opacity), range: 0...0.3) { Fmt.percent($0) }
                Toggle("Flicker", isOn: store.binding(\.effects.flicker.enabled))
                SliderRow(title: "Flicker intensity", value: store.binding(\.effects.flicker.intensity), range: 0...0.3) { Fmt.percent($0) }
            }
            Section("Presets") {
                HStack {
                    Button("Neon") { applyPreset(.neon) }
                    Button("Retro CRT") { applyPreset(.crt) }
                    Button("Glass") { applyPreset(.glass) }
                    Button("Minimal") { applyPreset(.minimal) }
                }
            }
        }
        .formStyle(.grouped)
    }

    enum Preset { case neon, crt, glass, minimal }

    private func applyPreset(_ p: Preset) {
        store.update { s in
            s.effects.enabled = true
            switch p {
            case .neon:
                s.appearance.themeID = "terminalus-neon"
                s.effects.glow = GlowSettings()
                s.effects.glow.enabled = true
                s.effects.vignette.enabled = true
                s.effects.scanlines.enabled = false
                s.effects.vignette.enabled = true
                s.effects.noise.enabled = false
                s.effects.flicker.enabled = false
                s.background.gradient.enabled = true
                s.background.gradient.style = .aurora
                s.window.backgroundOpacity = 0.82
                s.window.blur = true
            case .crt:
                s.appearance.themeID = "retro-green"
                s.effects.glow.enabled = true
                s.effects.glow.radius = 7
                s.effects.glow.opacity = 0.8
                s.effects.scanlines.enabled = true
                s.effects.scanlines.opacity = 0.22
                s.effects.vignette.enabled = true
                s.effects.vignette.intensity = 0.5
                s.effects.noise.enabled = true
                s.effects.flicker.enabled = true
                s.background.gradient.enabled = false
                s.window.backgroundOpacity = 0.97
            case .glass:
                s.appearance.themeID = "tokyo-night"
                s.effects.glow.enabled = false
                s.effects.scanlines.enabled = false
                s.effects.vignette.enabled = false
                s.effects.noise.enabled = false
                s.effects.flicker.enabled = false
                s.background.gradient.enabled = false
                s.window.backgroundOpacity = 0.55
                s.window.blur = true
                s.window.blurMaterial = .hudWindow
            case .minimal:
                s.appearance.themeID = "graphite"
                s.effects.enabled = false
                s.window.backgroundOpacity = 1
                s.window.blur = false
            }
        }
    }
}

// MARK: - Layout

struct LayoutPane: View {
    var body: some View {
        let l = store.settings.layout
        Form {
            Section {
                HStack(alignment: .top, spacing: 16) {
                    DockColumnEditor(side: .left)
                    DockColumnEditor(side: .right)
                }
                Text("Drag a panel's title bar to the other side of the window, or use its ••• menu. Custom panels come from View → Panels → Import Window Code.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: {
                Text("Side panels")
            }
            Section("Sides") {
                Toggle("Show left side", isOn: store.binding(\.layout.leftDockVisible))
                SliderRow(title: "Left width", value: store.binding(\.layout.leftDockWidth), range: 180...700, step: 1) { "\(Int($0)) pt" }
                Toggle("Show right side", isOn: store.binding(\.layout.rightDockVisible))
                SliderRow(title: "Right width", value: store.binding(\.layout.rightDockWidth), range: 180...700, step: 1) { "\(Int($0)) pt" }
                Toggle("Path above the file tree", isOn: store.binding(\.layout.showBreadcrumb))
            }
            Section("Stats strip") {
                Toggle("Compact stats under the terminal", isOn: store.binding(\.layout.statsStrip))
                if l.statsStrip {
                    SliderRow(title: "Height", value: store.binding(\.layout.statsStripHeight), range: 50...300, step: 1) { "\(Int($0)) pt" }
                }
            }
            Section("Tabs & panes") {
                EnumPicker(title: "Tab bar", value: store.binding(\.layout.tabBarPosition))
                EnumPicker(title: "Tab style", value: store.binding(\.layout.tabBarStyle))
                Toggle("Show the tab bar with a single tab", isOn: store.binding(\.layout.showTabBarWithOneTab))
                Toggle("Show ⌘-number hints on tabs", isOn: store.binding(\.layout.showTabShortcuts))
                SliderRow(title: "Split divider", value: store.binding(\.layout.splitDividerWidth), range: 1...10, step: 1) { "\(Int($0)) pt" }
                Toggle("Status bar", isOn: store.binding(\.layout.showStatusBar))
            }
        }
        .formStyle(.grouped)
    }
}

/// Lists the panels of one side with move/hide controls.
private struct DockColumnEditor: View {
    let side: DockSide

    var body: some View {
        let l = store.settings.layout
        let ids = l.panels(on: side)
        VStack(alignment: .leading, spacing: 6) {
            Text("\(side.label) side").font(.headline)
            if ids.isEmpty {
                Text("Empty").foregroundStyle(.secondary).font(.callout)
            }
            ForEach(Array(ids.enumerated()), id: \.element) { i, id in
                HStack(spacing: 6) {
                    Text(PanelInfo.title(id))
                    Spacer()
                    Button { store.update { $0.layout.move(id, to: side, at: i - 1) } } label: { Image(systemName: "arrow.up") }
                        .disabled(i == 0)
                    Button { store.update { $0.layout.move(id, to: side, at: i + 1) } } label: { Image(systemName: "arrow.down") }
                        .disabled(i == ids.count - 1)
                    Button { store.update { $0.layout.move(id, to: side.opposite) } } label: {
                        Image(systemName: side == .left ? "arrow.right" : "arrow.left")
                    }
                    .help("Move to the \(side.opposite.label.lowercased()) side")
                    Button { store.update { $0.layout.remove(id) } } label: { Image(systemName: "eye.slash") }
                        .help("Hide")
                }
                .buttonStyle(.borderless)
                .padding(.vertical, 3)
                .padding(.horizontal, 8)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.secondary.opacity(0.08)))
            }
            Menu("Add Panel") {
                ForEach(AppState.shared.hiddenPanelIDs, id: \.self) { id in
                    Button(PanelInfo.title(id)) { store.update { $0.layout.move(id, to: side) } }
                }
                Divider()
                Button("Import Window Code…") { PanelImportWindowController.show(side: side) }
            }
            .fixedSize()
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

// MARK: - Editor

struct EditorPane: View {
    @State private var newCommand = ""

    var body: some View {
        let e = store.settings.editor
        Form {
            Section {
                Toggle("Open files in the built-in editor when these commands run", isOn: store.binding(\.editor.openEditorsInIDE))
                LabeledContent("Commands") {
                    VStack(alignment: .leading, spacing: 6) {
                        FlowCommands(commands: e.interceptedCommands)
                        HStack {
                            TextField("add, e.g. hx", text: $newCommand).frame(width: 140)
                                .onSubmit(addCommand)
                            Button("Add", action: addCommand).disabled(newCommand.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                }
                Text("Typing `nano notes.md` (or vim, micro…) opens the file here with the terminal underneath; the shell waits until you close it, like the real editor. `command nano` always runs the real one, and the editor has an “Open in nano” button. New terminal tabs pick up changes to this list.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: {
                Text("IDE mode")
            }
            Section("Editing") {
                Stepper("Tab width: \(e.tabWidth)", value: store.binding(\.editor.tabWidth), in: 1...12)
                Toggle("Insert spaces instead of tabs", isOn: store.binding(\.editor.insertSpaces))
                Toggle("Auto-indent", isOn: store.binding(\.editor.autoIndent))
                Toggle("Close brackets and quotes automatically", isOn: store.binding(\.editor.autoCloseBrackets))
                Toggle("Wrap long lines", isOn: store.binding(\.editor.wordWrap))
                Toggle("Trim trailing whitespace on save", isOn: store.binding(\.editor.trimTrailingWhitespace))
                Toggle("End files with a newline", isOn: store.binding(\.editor.ensureTrailingNewline))
            }
            Section("Display") {
                Toggle("Syntax highlighting", isOn: store.binding(\.editor.syntaxHighlighting))
                Toggle("Line numbers", isOn: store.binding(\.editor.showLineNumbers))
                Toggle("Highlight the current line", isOn: store.binding(\.editor.highlightCurrentLine))
                LabeledContent("Font size") {
                    HStack {
                        Toggle("Same as the terminal", isOn: Binding(get: { e.fontSize == nil },
                                                                   set: { v in store.update { $0.editor.fontSize = v ? nil : $0.terminal.font.size } }))
                            .toggleStyle(.checkbox)
                        if let size = e.fontSize {
                            Stepper(String(format: "%.1f pt", size), value: Binding(get: { size }, set: { v in store.update { $0.editor.fontSize = v } }), in: 8...36, step: 0.5)
                        }
                    }
                }
            }
            Section("While the editor is open") {
                Toggle("Show the Outline panel", isOn: store.binding(\.editor.showOutline))
                Toggle("Hide the System panel", isOn: store.binding(\.editor.hideSystemPanel))
                SliderRow(title: "Terminal height", value: store.binding(\.editor.terminalHeight), range: 0.1...0.85) { Fmt.percent($0) }
            }
            Section("Run (⌘R)") {
                ForEach(e.runCommands.keys.sorted(), id: \.self) { ext in
                    HStack {
                        Text(".\(ext)").font(.system(.body, design: .monospaced)).frame(width: 60, alignment: .leading)
                        TextField("", text: Binding(get: { store.settings.editor.runCommands[ext] ?? "" },
                                                    set: { v in store.update { $0.editor.runCommands[ext] = v } }))
                            .font(.system(.body, design: .monospaced))
                        Button { store.update { $0.editor.runCommands[ext] = nil } } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                    }
                }
                Button("Reset Run Commands") { store.update { $0.editor.runCommands = EditorSettings.defaultRunCommands } }
            }
        }
        .formStyle(.grouped)
    }

    private func addCommand() {
        let c = newCommand.trimmingCharacters(in: .whitespaces)
        guard !c.isEmpty, c.range(of: "^[A-Za-z0-9._+-]+$", options: .regularExpression) != nil else { return }
        store.update { if !$0.editor.interceptedCommands.contains(c) { $0.editor.interceptedCommands.append(c) } }
        newCommand = ""
    }
}

private struct FlowCommands: View {
    let commands: [String]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(commands, id: \.self) { c in
                HStack(spacing: 4) {
                    Text(c).font(.system(.callout, design: .monospaced))
                    Button { store.update { $0.editor.interceptedCommands.removeAll { $0 == c } } } label: {
                        Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.secondary.opacity(0.12)))
            }
        }
    }
}

// MARK: - Panels

struct PanelsPane: View {
    var body: some View {
        let app = AppState.shared
        Form {
            Section {
                Button("Import Window Code…") { PanelImportWindowController.show() }
                Text("Paste HTML/JavaScript, a JSON manifest or a shell command and it becomes a side panel that works like the built-in ones. Templates are in the import window.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Your panels") {
                if app.panels.panels.isEmpty {
                    Text("None yet.").foregroundStyle(.secondary)
                }
                ForEach(app.panels.panels) { p in
                    let id = PanelID.custom(p.id)
                    HStack {
                        VStack(alignment: .leading) {
                            Text(p.name)
                            Text(p.kind == .web ? "Web panel\(p.allowCommands ? " · can run commands" : "")" : "Command · \(p.code)")
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Picker("", selection: Binding(get: { app.settings.layout.side(of: id)?.rawValue ?? "hidden" }, set: { v in
                            store.update { s in
                                if let side = DockSide(rawValue: v) { s.layout.move(id, to: side) } else { s.layout.remove(id) }
                            }
                        })) {
                            Text("Left").tag("left")
                            Text("Right").tag("right")
                            Text("Hidden").tag("hidden")
                        }
                        .labelsHidden()
                        .frame(width: 110)
                        Button("Edit…") { PanelImportWindowController.show(editing: p, side: app.settings.layout.side(of: id) ?? .right) }
                        Button("Copy Code") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(PanelCodeParser.manifest(for: p, side: app.settings.layout.side(of: id)), forType: .string)
                        }
                        Button(role: .destructive) { app.deletePanel(p) } label: { Image(systemName: "trash") }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Tree

struct TreePane: View {
    var body: some View {
        let s = store.settings
        Form {
            Section("Root") {
                EnumPicker(title: "Tree starts at", value: store.binding(\.tree.rootMode))
                Toggle("Follow the terminal's current directory", isOn: store.binding(\.tree.followCwd))
                Toggle("Collapse folders opened only to follow the directory", isOn: store.binding(\.tree.collapseOnFollow))
            }
            Section("Filtering & sorting") {
                Toggle("Show hidden files", isOn: store.binding(\.tree.showHidden))
                Toggle("Folders first", isOn: store.binding(\.tree.foldersFirst))
                EnumPicker(title: "Sort by", value: store.binding(\.tree.sortBy))
                Toggle("Ascending", isOn: store.binding(\.tree.sortAscending))
                LabeledContent("Ignore (one glob per line)") {
                    TextEditor(text: Binding(get: { s.tree.ignore.joined(separator: "\n") },
                                             set: { v in store.update { $0.tree.ignore = v.split(separator: "\n").map(String.init) } }))
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 80)
                }
                Stepper("Max items per folder: \(s.tree.maxChildren)", value: store.binding(\.tree.maxChildren), in: 100...20000, step: 100)
            }
            Section("Display") {
                EnumPicker(title: "Icons", value: store.binding(\.tree.iconStyle))
                Toggle("Color icons by file type", isOn: store.binding(\.tree.coloredIcons))
                Toggle("File sizes", isOn: store.binding(\.tree.showSizes))
                Toggle("Modification dates", isOn: store.binding(\.tree.showDates))
                Toggle("Item counts", isOn: store.binding(\.tree.showItemCounts))
                Toggle("Git status badges", isOn: store.binding(\.tree.gitBadges))
                SliderRow(title: "Font size", value: store.binding(\.tree.fontSize), range: 9...18, step: 0.5) { String(format: "%.1f pt", $0) }
                SliderRow(title: "Row height", value: store.binding(\.tree.rowHeight), range: 14...36, step: 1) { "\(Int($0)) pt" }
                SliderRow(title: "Indentation", value: store.binding(\.tree.indentation), range: 6...32, step: 1) { "\(Int($0)) pt" }
            }
            Section("Mouse") {
                EnumPicker(title: "Single click", value: store.binding(\.tree.singleClick))
                EnumPicker(title: "Double-click a folder", value: store.binding(\.tree.doubleClickFolder))
                EnumPicker(title: "Double-click a file", value: store.binding(\.tree.doubleClickFile))
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Advanced

struct AdvancedPane: View {
    @State private var message: String?

    var body: some View {
        Form {
            Section("settings.json") {
                LabeledContent("Location") { Text(Paths.abbreviate(Paths.settingsFile.path)).textSelection(.enabled).foregroundStyle(.secondary) }
                HStack {
                    Button("Open in Editor") { AppState.shared.openSettingsJSON() }
                    Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([Paths.settingsFile]) }
                    Button("Reload") { AppState.shared.perform(.reloadSettings) }
                }
                Text("Every option here is also a key in settings.json. Edits made in any editor apply live; a file with an error is never overwritten.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Import / export") {
                HStack {
                    Button("Export Settings…") { exportSettings() }
                    Button("Import Settings…") { importSettings() }
                    Button("Reset to Defaults…", role: .destructive) { reset() }
                }
                if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
            }
            Section("Folders") {
                HStack {
                    Button("Open Themes Folder") {
                        Paths.ensureDirectories()
                        NSWorkspace.shared.open(Paths.themesDirectory)
                    }
                    Button("Open Shell Integration Folder") {
                        ShellIntegration.install()
                        NSWorkspace.shared.open(ShellIntegration.directory)
                    }
                }
            }
            Section("Safe mode") {
                Text("Hold ⌥ while launching Terminalus to start with default settings without reading or writing settings.json.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func exportSettings() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "terminalus-settings.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.export(to: url)
            message = "Exported to \(url.lastPathComponent)"
        } catch {
            message = error.localizedDescription
        }
    }

    private func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.importSettings(from: url)
            message = "Imported \(url.lastPathComponent)"
        } catch {
            message = "Import failed: \(error.localizedDescription)"
        }
    }

    private func reset() {
        let alert = NSAlert()
        alert.messageText = "Reset all settings to their defaults?"
        alert.informativeText = "Your current settings.json is replaced. Export first if you want to keep it."
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            store.resetToDefaults()
            message = "Settings reset"
        }
    }
}
