import Foundation

// All settings structs have a default for every property. Loading merges the user's JSON over the
// encoded defaults (see JSONMerge), so any key may be omitted from settings.json.

public struct AppSettings: Codable, Equatable, Sendable {
    public static let currentVersion = 2
    public var version: Int = AppSettings.currentVersion
    public var appearance = AppearanceSettings()
    public var terminal = TerminalSettings()
    public var window = WindowSettings()
    public var background = BackgroundSettings()
    public var effects = EffectsSettings()
    public var layout = LayoutSettings()
    public var tree = TreeSettings()
    public var stats = StatsSettings()
    public var editor = EditorSettings()
    public var profiles: [Profile] = [Profile.defaultProfile]
    public var defaultProfileID: String = Profile.defaultProfile.id
    /// Overrides of the default key bindings: action id → combo such as "cmd+shift+t" ("" unbinds).
    public var keybindings: [String: String] = [:]

    public init() {}

    public var defaultProfile: Profile {
        profiles.first { $0.id == defaultProfileID } ?? profiles.first ?? .defaultProfile
    }

    /// Brings settings written by an older version up to date. Version 2 introduced the dock/panel
    /// layout and a quieter default look, so the visual sections are reset (everything else is kept).
    public func migrated() -> AppSettings {
        guard version < 2 else { return self }
        var m = self
        m.version = AppSettings.currentVersion
        m.appearance = AppearanceSettings()
        m.effects = EffectsSettings()
        m.background = BackgroundSettings()
        m.window.backgroundOpacity = WindowSettings().backgroundOpacity
        m.layout = LayoutSettings()
        if m.tree.doubleClickFile == .open { m.tree.doubleClickFile = .openInEditor }
        m.stats.widgets = StatsSettings.defaultWidgets
        return m
    }

    public func profile(id: String?) -> Profile {
        guard let id else { return defaultProfile }
        return profiles.first { $0.id == id } ?? defaultProfile
    }
}

public struct AppearanceSettings: Codable, Equatable, Sendable {
    public var themeID: String = "graphite"
    public var followSystemAppearance: Bool = false
    public var lightThemeID: String = "graphite-light"
    public var darkThemeID: String = "graphite"
    /// Optional hex color replacing the theme's accent everywhere in the UI.
    public var accentOverride: String? = nil
    public var uiFontDesign: UIFontDesign = .system
    public var uiFontSize: Double = 12
    public var density: UIDensity = .regular
    public var cornerRadius: Double = 8
    /// Opacity of the dock backgrounds over the window background.
    public var panelOpacity: Double = 0.45
    /// Flat sections separated by hairlines, or rounded cards.
    public var widgetChrome: WidgetChrome = .flat
    public var showPanelBorders: Bool = true
    public var glowingBorders: Bool = false
    public var animateUI: Bool = true
    public init() {}
}

public struct FontSettings: Codable, Equatable, Sendable {
    /// Empty means the system monospaced font (SF Mono).
    public var family: String = ""
    public var size: Double = 13
    public var weight: FontWeightOption = .regular
    public var lineSpacing: Double = 1.0
    public var useBrightColorsForBold: Bool = true
    public var fontSmoothing: Bool = true
    public var customBlockGlyphs: Bool = true
    public init() {}
}

public struct CursorSettings: Codable, Equatable, Sendable {
    public var shape: CursorShape = .bar
    public var blink: Bool = true
    /// Hex override; nil uses the theme cursor color.
    public var color: String? = nil
    public var textColor: String? = nil
    public var hollowWhenUnfocused: Bool = true
    public init() {}
}

public struct TerminalSettings: Codable, Equatable, Sendable {
    public var font = FontSettings()
    public var cursor = CursorSettings()
    public var scrollback: Int = 10_000
    public var optionAsMeta: Bool = true
    public var copyOnSelect: Bool = false
    public var mouseReporting: Bool = true
    public var linkMode: LinkMode = .hoverWithModifier
    public var bell: BellMode = .visual
    public var bellSound: String = "Tink"
    public var confirmClose: ConfirmCloseMode = .whenRunning
    public var onExit: OnExitBehavior = .close
    public var tabTitle: TabTitleMode = .smart
    public var useMetalRenderer: Bool = false
    public var scrollSensitivity: Double = 1.0
    public var scrollerStyle: ScrollerStyleOption = .overlay
    /// Post a notification when a command that ran longer than `longCommandSeconds` finishes while the app is inactive.
    public var notifyLongCommands: Bool = true
    public var longCommandSeconds: Double = 10
    public var shellIntegration: Bool = true
    public var termName: String = "xterm-256color"
    public init() {}
}

public struct WindowSettings: Codable, Equatable, Sendable {
    public var titlebar: TitlebarStyle = .transparent
    /// Opacity of the theme background painted behind the terminal (0 = fully see-through).
    public var backgroundOpacity: Double = 0.72
    public var blur: Bool = true
    public var blurMaterial: BlurMaterial = .hudWindow
    public var padding: Double = 10
    public var alwaysOnTop: Bool = false
    public var showTitleText: Bool = false
    public var initialWidth: Double = 1360
    public var initialHeight: Double = 820
    public init() {}
}

public struct BackgroundImageSettings: Codable, Equatable, Sendable {
    public var path: String = ""
    public var mode: ImageFillMode = .fill
    public var opacity: Double = 0.25
    public var blur: Double = 0
    public var saturation: Double = 1
    public init() {}
}

public struct GradientSettings: Codable, Equatable, Sendable {
    public var enabled: Bool = false
    public var style: GradientStyle = .aurora
    /// Hex colors; empty uses the theme gradient.
    public var colors: [String] = []
    public var speed: Double = 0.12
    public var opacity: Double = 0.22
    public var animated: Bool = true
    public init() {}
}

public struct BackgroundSettings: Codable, Equatable, Sendable {
    public var image = BackgroundImageSettings()
    public var gradient = GradientSettings()
    public init() {}
}

public struct GlowSettings: Codable, Equatable, Sendable {
    public var enabled: Bool = false
    /// Hex override; nil uses the theme glow color.
    public var color: String? = nil
    public var radius: Double = 5
    public var opacity: Double = 0.55
    public init() {}
}

public struct ScanlineSettings: Codable, Equatable, Sendable {
    public var enabled: Bool = false
    public var opacity: Double = 0.14
    public var spacing: Double = 3
    public var thickness: Double = 1
    public var animated: Bool = true
    public init() {}
}

public struct VignetteSettings: Codable, Equatable, Sendable {
    public var enabled: Bool = false
    public var intensity: Double = 0.28
    public init() {}
}

public struct FlickerSettings: Codable, Equatable, Sendable {
    public var enabled: Bool = false
    public var intensity: Double = 0.04
    public init() {}
}

public struct NoiseSettings: Codable, Equatable, Sendable {
    public var enabled: Bool = false
    public var opacity: Double = 0.05
    public init() {}
}

public struct EffectsSettings: Codable, Equatable, Sendable {
    public var glow = GlowSettings()
    public var scanlines = ScanlineSettings()
    public var vignette = VignetteSettings()
    public var flicker = FlickerSettings()
    public var noise = NoiseSettings()
    /// Dim unfocused split panes by this amount (0 = off).
    public var inactivePaneDim: Double = 0.15
    public var pauseWhenInactive: Bool = true
    /// Master switch; when false every effect above is off regardless of its own flag.
    public var enabled: Bool = true
    public init() {}
}

public struct LayoutSettings: Codable, Equatable, Sendable {
    /// Panel ids shown in each dock, top to bottom: "files", "system", "outline" or "custom.<id>".
    public var leftPanels: [String] = [PanelID.files, PanelID.system]
    public var rightPanels: [String] = []
    public var leftDockVisible: Bool = true
    public var rightDockVisible: Bool = true
    public var leftDockWidth: Double = 290
    public var rightDockWidth: Double = 300
    /// Relative height of each panel inside its dock.
    public var panelWeights: [String: Double] = [PanelID.files: 1.1, PanelID.system: 1]
    /// Panels collapsed to their header.
    public var collapsedPanels: [String] = []
    /// Compact stats strip under the terminal (independent of the System panel).
    public var statsStrip: Bool = false
    public var statsStripHeight: Double = 92
    public var tabBarPosition: TabBarPosition = .top
    public var tabBarStyle: TabBarStyle = .underline
    public var showTabBarWithOneTab: Bool = true
    public var showTabShortcuts: Bool = false
    public var showBreadcrumb: Bool = true
    public var showStatusBar: Bool = true
    public var splitDividerWidth: Double = 1
    public init() {}

    public func panels(on side: DockSide) -> [String] { side == .left ? leftPanels : rightPanels }

    public func side(of panel: String) -> DockSide? {
        if leftPanels.contains(panel) { return .left }
        if rightPanels.contains(panel) { return .right }
        return nil
    }

    /// Moves (or adds) `panel` to `side` at `index`; removes it from wherever it was.
    public mutating func move(_ panel: String, to side: DockSide, at index: Int? = nil) {
        leftPanels.removeAll { $0 == panel }
        rightPanels.removeAll { $0 == panel }
        var list = side == .left ? leftPanels : rightPanels
        list.insert(panel, at: min(max(0, index ?? list.count), list.count))
        if side == .left {
            leftPanels = list
            leftDockVisible = true
        } else {
            rightPanels = list
            rightDockVisible = true
        }
    }

    public mutating func remove(_ panel: String) {
        leftPanels.removeAll { $0 == panel }
        rightPanels.removeAll { $0 == panel }
    }
}

public enum PanelID {
    public static let files = "files"
    public static let system = "system"
    public static let outline = "outline"
    public static let customPrefix = "custom."

    public static func custom(_ id: String) -> String { customPrefix + id }

    public static func customID(_ panel: String) -> String? {
        panel.hasPrefix(customPrefix) ? String(panel.dropFirst(customPrefix.count)) : nil
    }
}

public struct TreeSettings: Codable, Equatable, Sendable {
    public var rootMode: TreeRootMode = .filesystemRoot
    public var followCwd: Bool = true
    /// When following the cwd, collapse folders that were only opened to reveal the previous cwd.
    public var collapseOnFollow: Bool = true
    public var showHidden: Bool = false
    public var foldersFirst: Bool = true
    public var sortBy: TreeSortKey = .name
    public var sortAscending: Bool = true
    /// fnmatch-style globs matched against file names.
    public var ignore: [String] = [".DS_Store", ".Trash", ".git"]
    public var iconStyle: TreeIconStyle = .symbols
    public var showSizes: Bool = false
    public var showDates: Bool = false
    public var gitBadges: Bool = true
    public var singleClick: TreeAction = .select
    public var doubleClickFolder: TreeAction = .cd
    public var doubleClickFile: TreeAction = .openInEditor
    /// Tint file and folder icons by type; off keeps them neutral.
    public var coloredIcons: Bool = false
    public var fontSize: Double = 12
    public var rowHeight: Double = 21
    public var indentation: Double = 14
    public var maxChildren: Int = 2000
    public var showItemCounts: Bool = false
    public init() {}
}

public struct WidgetConfig: Codable, Equatable, Identifiable, Sendable {
    public var kind: WidgetKind
    public var enabled: Bool = true
    public var style: ChartStyle
    /// Hex override; nil uses the theme chart palette.
    public var color: String? = nil
    /// Number of samples kept for history charts.
    public var history: Int = 60
    public var size: WidgetSize = .regular
    public var id: String { kind.rawValue }

    public init(kind: WidgetKind, enabled: Bool = true, style: ChartStyle? = nil, color: String? = nil,
                history: Int = 60, size: WidgetSize = .regular) {
        self.kind = kind; self.enabled = enabled; self.style = style ?? kind.supportedStyles[0]
        self.color = color; self.history = history; self.size = size
    }

    private enum CodingKeys: String, CodingKey { case kind, enabled, style, color, history, size }

    // Hand-written so a widget entry in settings.json may be as short as {"kind": "cpu"}.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(WidgetKind.self, forKey: .kind)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        style = try c.decodeIfPresent(ChartStyle.self, forKey: .style) ?? kind.supportedStyles[0]
        color = try c.decodeIfPresent(String.self, forKey: .color)
        history = try c.decodeIfPresent(Int.self, forKey: .history) ?? 60
        size = try c.decodeIfPresent(WidgetSize.self, forKey: .size) ?? .regular
    }
}

public struct StatsSettings: Codable, Equatable, Sendable {
    public var refreshInterval: Double = 1.0
    public var processBackend: ProcessBackend = .ps
    public var processCount: Int = 6
    public var processSort: ProcessSortKey = .cpu
    public var temperatureUnit: TemperatureUnit = .celsius
    public var networkUnit: NetworkUnit = .bytes
    public var animateCharts: Bool = true
    public var showWidgetHeaders: Bool = true
    public var showWidgetIcons: Bool = false
    /// Give every widget its own color; off draws everything in the theme accent.
    public var colorfulCharts: Bool = false
    public var chartGlow: Bool = false
    public var clock24h: Bool = true
    public var widgets: [WidgetConfig] = StatsSettings.defaultWidgets
    public init() {}

    public static let defaultWidgets: [WidgetConfig] = [
        WidgetConfig(kind: .session),
        WidgetConfig(kind: .cpu, style: .area),
        WidgetConfig(kind: .cores),
        WidgetConfig(kind: .memory, style: .bar),
        WidgetConfig(kind: .gpu, style: .sparkline),
        WidgetConfig(kind: .network),
        WidgetConfig(kind: .disk),
        WidgetConfig(kind: .processes),
        WidgetConfig(kind: .system),
        WidgetConfig(kind: .thermal, size: .compact),
        WidgetConfig(kind: .battery),
        WidgetConfig(kind: .clock, enabled: false),
        WidgetConfig(kind: .temperatures, enabled: false),
    ]

    /// The configured widgets plus any kinds missing from the user's list (appended disabled), so new
    /// widget kinds show up in the editor after an upgrade.
    public var normalizedWidgets: [WidgetConfig] {
        var seen = Set<WidgetKind>()
        var out: [WidgetConfig] = []
        for w in widgets where !seen.contains(w.kind) {
            seen.insert(w.kind)
            var w = w
            if !w.kind.supportedStyles.contains(w.style) { w.style = w.kind.supportedStyles[0] }
            out.append(w)
        }
        for kind in WidgetKind.allCases where !seen.contains(kind) {
            out.append(WidgetConfig(kind: kind, enabled: false))
        }
        return out
    }
}

public struct EditorSettings: Codable, Equatable, Sendable {
    /// Running one of `interceptedCommands` in a shell with integration opens the file in the built-in editor.
    public var openEditorsInIDE: Bool = true
    public var interceptedCommands: [String] = ["nano", "pico", "micro", "vim", "vi", "nvim", "emacs"]
    public var tabWidth: Int = 4
    public var insertSpaces: Bool = true
    public var wordWrap: Bool = false
    public var showLineNumbers: Bool = true
    public var highlightCurrentLine: Bool = true
    public var autoIndent: Bool = true
    public var autoCloseBrackets: Bool = true
    public var syntaxHighlighting: Bool = true
    public var trimTrailingWhitespace: Bool = false
    public var ensureTrailingNewline: Bool = true
    /// nil uses the terminal font size.
    public var fontSize: Double? = nil
    /// Show the Outline panel while the IDE is open (added to the right dock if it isn't placed).
    public var showOutline: Bool = true
    /// Hide the System panel while the IDE is open.
    public var hideSystemPanel: Bool = true
    /// Fraction of the editor area given to the terminal below it.
    public var terminalHeight: Double = 0.3
    /// Command used by Run (⌘R) per file extension; {file} is replaced by the quoted path.
    public var runCommands: [String: String] = EditorSettings.defaultRunCommands
    public init() {}

    public static let defaultRunCommands: [String: String] = [
        "py": "python3 {file}", "js": "node {file}", "mjs": "node {file}", "cjs": "node {file}", "ts": "npx tsx {file}",
        "swift": "swift {file}", "sh": "bash {file}", "bash": "bash {file}", "zsh": "zsh {file}", "rb": "ruby {file}",
        "go": "go run {file}", "pl": "perl {file}", "php": "php {file}", "lua": "lua {file}", "java": "java {file}",
        "c": "cc {file} -o /tmp/terminalus-run && /tmp/terminalus-run",
        "cpp": "c++ -std=c++17 {file} -o /tmp/terminalus-run && /tmp/terminalus-run",
        "rs": "rustc {file} -o /tmp/terminalus-run && /tmp/terminalus-run",
        "html": "open {file}", "htm": "open {file}",
    ]
}
