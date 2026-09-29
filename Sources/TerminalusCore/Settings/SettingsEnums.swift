import Foundation

/// Every settings enum is a String raw-value enum so settings.json stays human-editable.
public protocol SettingsEnum: RawRepresentable, Codable, CaseIterable, Identifiable, Sendable, Hashable where RawValue == String, AllCases == [Self] {
    var label: String { get }
}

extension SettingsEnum {
    public var id: String { rawValue }
}

public enum CursorShape: String, SettingsEnum {
    case block, underline, bar
    public var label: String { rawValue.capitalized }
}

public enum FontWeightOption: String, SettingsEnum {
    case ultraLight, thin, light, regular, medium, semibold, bold, heavy
    public var label: String {
        switch self {
        case .ultraLight: "Ultra Light"
        default: rawValue.capitalized
        }
    }
}

public enum BellMode: String, SettingsEnum {
    case none, sound, visual, soundAndVisual, notification
    public var label: String {
        switch self {
        case .none: "None"
        case .sound: "Sound"
        case .visual: "Visual flash"
        case .soundAndVisual: "Sound + flash"
        case .notification: "Notification (when inactive)"
        }
    }
}

public enum ConfirmCloseMode: String, SettingsEnum {
    case never, whenRunning, always
    public var label: String {
        switch self {
        case .never: "Never"
        case .whenRunning: "When a command is running"
        case .always: "Always"
        }
    }
}

public enum OnExitBehavior: String, SettingsEnum {
    case close, keepOpen
    public var label: String { self == .close ? "Close the pane" : "Keep it open" }
}

public enum TabTitleMode: String, SettingsEnum {
    case smart, directory, process, terminalTitle, profile
    public var label: String {
        switch self {
        case .smart: "Command or directory"
        case .directory: "Directory"
        case .process: "Running process"
        case .terminalTitle: "Title set by the program"
        case .profile: "Profile name"
        }
    }
}

public enum LinkMode: String, SettingsEnum {
    case hoverWithModifier, always, never
    public var label: String {
        switch self {
        case .hoverWithModifier: "Highlight while holding ⌘"
        case .always: "Always underline"
        case .never: "Never"
        }
    }
}

public enum TitlebarStyle: String, SettingsEnum {
    case standard, transparent, hidden
    public var label: String {
        switch self {
        case .standard: "Standard"
        case .transparent: "Transparent (unified)"
        case .hidden: "Hidden (no traffic lights)"
        }
    }
}

public enum BlurMaterial: String, SettingsEnum {
    case hudWindow, underWindowBackground, sidebar, fullScreenUI, popover, menu, titlebar, headerView, sheet, windowBackground, contentBackground
    public var label: String {
        switch self {
        case .hudWindow: "HUD (dark glass)"
        case .underWindowBackground: "Under-window"
        case .sidebar: "Sidebar"
        case .fullScreenUI: "Full-screen UI"
        case .popover: "Popover"
        case .menu: "Menu"
        case .titlebar: "Titlebar"
        case .headerView: "Header"
        case .sheet: "Sheet"
        case .windowBackground: "Window background"
        case .contentBackground: "Content background"
        }
    }
}

public enum ImageFillMode: String, SettingsEnum {
    case fill, fit, stretch, tile, center
    public var label: String { rawValue.capitalized }
}

public enum GradientStyle: String, SettingsEnum {
    case aurora, linear, radial, conic, waves
    public var label: String { rawValue.capitalized }
}

public enum UIDensity: String, SettingsEnum {
    case compact, regular, spacious
    public var label: String { rawValue.capitalized }
    public var scale: Double {
        switch self {
        case .compact: 0.82
        case .regular: 1
        case .spacious: 1.2
        }
    }
}

public enum UIFontDesign: String, SettingsEnum {
    case system, rounded, monospaced, serif
    public var label: String { rawValue.capitalized }
}

public enum DockSide: String, SettingsEnum {
    case left, right
    public var label: String { rawValue.capitalized }
    public var opposite: DockSide { self == .left ? .right : .left }
}

public enum WidgetChrome: String, SettingsEnum {
    case flat, cards
    public var label: String { self == .flat ? "Flat sections" : "Cards" }
}

public enum TabBarPosition: String, SettingsEnum {
    case top, bottom, hidden
    public var label: String { rawValue.capitalized }
}

public enum TabBarStyle: String, SettingsEnum {
    case underline, pills, blocks, minimal
    public var label: String { rawValue.capitalized }
}

public enum TreeRootMode: String, SettingsEnum {
    case filesystemRoot, currentDirectory, home, gitRoot
    public var label: String {
        switch self {
        case .filesystemRoot: "Whole disk (/)"
        case .currentDirectory: "Current directory"
        case .home: "Home folder"
        case .gitRoot: "Git repository root"
        }
    }
}

public enum TreeSortKey: String, SettingsEnum {
    case name, modified, size, kind
    public var label: String { rawValue.capitalized }
}

public enum TreeIconStyle: String, SettingsEnum {
    case symbols, system, emoji, none
    public var label: String {
        switch self {
        case .symbols: "Colored symbols"
        case .system: "Finder icons"
        case .emoji: "Emoji"
        case .none: "None"
        }
    }
}

public enum TreeAction: String, SettingsEnum {
    case none, select, toggleExpand, insertPath, cd, open, openInEditor, quickLook, revealInFinder, newTab
    public var label: String {
        switch self {
        case .none: "Do nothing"
        case .select: "Select only"
        case .toggleExpand: "Expand / collapse (folders)"
        case .insertPath: "Insert path into terminal"
        case .cd: "cd into it (folders) / cd to parent (files)"
        case .open: "Open with default app"
        case .openInEditor: "Open in the built-in editor"
        case .quickLook: "Quick Look"
        case .revealInFinder: "Reveal in Finder"
        case .newTab: "Open a new tab there"
        }
    }
}

public enum WidgetKind: String, SettingsEnum {
    case session, cpu, cores, memory, gpu, network, disk, processes, system, thermal, clock, battery, temperatures
    public var label: String {
        switch self {
        case .session: "Session"
        case .cpu: "CPU"
        case .cores: "CPU cores"
        case .memory: "Memory"
        case .gpu: "GPU"
        case .network: "Network"
        case .disk: "Disk"
        case .processes: "Top processes"
        case .system: "System"
        case .thermal: "Thermal state"
        case .clock: "Clock"
        case .battery: "Battery"
        case .temperatures: "Temperatures (experimental)"
        }
    }
    public var symbol: String {
        switch self {
        case .session: "terminal"
        case .cpu: "cpu"
        case .cores: "square.grid.3x3.fill"
        case .memory: "memorychip"
        case .gpu: "sparkles.tv"
        case .network: "network"
        case .disk: "internaldrive"
        case .processes: "list.bullet.rectangle"
        case .system: "desktopcomputer"
        case .thermal: "thermometer.medium"
        case .clock: "clock"
        case .battery: "battery.75percent"
        case .temperatures: "thermometer.sun"
        }
    }
    /// Styles that make sense for this widget; the first is the default.
    public var supportedStyles: [ChartStyle] {
        switch self {
        case .cpu, .memory, .gpu: [.ring, .area, .sparkline, .bar, .number]
        case .cores: [.heatmap, .bar]
        case .network: [.area, .sparkline, .number]
        case .disk: [.bar, .ring, .number]
        case .battery: [.ring, .bar, .number]
        case .processes, .system, .session, .thermal, .clock, .temperatures: [.list]
        }
    }
}

public enum ChartStyle: String, SettingsEnum {
    case ring, bar, sparkline, area, heatmap, number, list
    public var label: String { rawValue.capitalized }
}

public enum WidgetSize: String, SettingsEnum {
    case compact, regular, large
    public var label: String { rawValue.capitalized }
}

public enum ProcessBackend: String, SettingsEnum {
    case ps, libproc
    public var label: String { self == .ps ? "ps (sees every process)" : "libproc (own processes only, no subprocess)" }
}

public enum ProcessSortKey: String, SettingsEnum {
    case cpu, memory
    public var label: String { self == .cpu ? "CPU" : "Memory" }
}

public enum TemperatureUnit: String, SettingsEnum {
    case celsius, fahrenheit
    public var label: String { self == .celsius ? "°C" : "°F" }
}

public enum NetworkUnit: String, SettingsEnum {
    case bytes, bits
    public var label: String { self == .bytes ? "Bytes/s" : "Bits/s" }
}

public enum WorkingDirectoryMode: String, SettingsEnum {
    case home, inherit, custom
    public var label: String {
        switch self {
        case .home: "Home folder"
        case .inherit: "Same as the current tab"
        case .custom: "Custom folder"
        }
    }
}

public enum ScrollerStyleOption: String, SettingsEnum {
    case overlay, legacy
    public var label: String { self == .overlay ? "Overlay" : "Always visible" }
}
