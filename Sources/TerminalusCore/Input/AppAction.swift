import Foundation

/// Every user-invokable command. Used by menus, key bindings and the command palette.
public enum AppAction: String, CaseIterable, Codable, Sendable, Identifiable {
    case newWindow, newTab, closePane, closeTab, closeWindow
    case splitRight, splitDown, focusNextPane, focusPreviousPane
    case focusPaneLeft, focusPaneRight, focusPaneUp, focusPaneDown, zoomPane, equalizePanes
    case nextTab, previousTab, moveTabLeft, moveTabRight
    case selectTab1, selectTab2, selectTab3, selectTab4, selectTab5, selectTab6, selectTab7, selectTab8, selectTab9
    case toggleLeftDock, toggleRightDock, toggleStats, cycleStatsPlacement, importPanel
    case focusTree, focusTerminal, revealCwdInTree
    case toggleHiddenFiles, collapseTree, cycleTreeRoot
    case toggleIDE, openFileInEditor, save, saveAs, goToLine, toggleComment, runFile
    case commandPalette, openSettings, openSettingsJSON, reloadSettings
    case increaseFont, decreaseFont, resetFont
    case nextTheme, previousTheme, toggleEffects, toggleGlow, toggleScanlines, toggleTransparency, toggleGradient
    case find, findNext, findPrevious
    case clearBuffer, scrollToTop, scrollToBottom
    case toggleFullScreen, toggleAlwaysOnTop
    case copyCwd, openCwdInFinder

    public var id: String { rawValue }

    public enum Category: String, CaseIterable, Sendable {
        case shell = "Shell", editor = "Editor", view = "View", tree = "Files", appearance = "Appearance", window = "Window",
             edit = "Edit", app = "Terminalus"
    }

    public var category: Category {
        switch self {
        case .newWindow, .newTab, .closePane, .closeTab, .closeWindow, .splitRight, .splitDown, .copyCwd, .openCwdInFinder, .clearBuffer:
            .shell
        case .toggleIDE, .openFileInEditor, .save, .saveAs, .goToLine, .toggleComment, .runFile:
            .editor
        case .focusNextPane, .focusPreviousPane, .focusPaneLeft, .focusPaneRight, .focusPaneUp, .focusPaneDown, .zoomPane,
             .equalizePanes, .nextTab, .previousTab, .moveTabLeft, .moveTabRight, .selectTab1, .selectTab2, .selectTab3,
             .selectTab4, .selectTab5, .selectTab6, .selectTab7, .selectTab8, .selectTab9, .toggleFullScreen, .toggleAlwaysOnTop:
            .window
        case .toggleLeftDock, .toggleRightDock, .toggleStats, .cycleStatsPlacement, .importPanel, .focusTerminal,
             .scrollToTop, .scrollToBottom:
            .view
        case .focusTree, .revealCwdInTree, .toggleHiddenFiles, .collapseTree, .cycleTreeRoot:
            .tree
        case .increaseFont, .decreaseFont, .resetFont, .nextTheme, .previousTheme, .toggleEffects, .toggleGlow,
             .toggleScanlines, .toggleTransparency, .toggleGradient:
            .appearance
        case .find, .findNext, .findPrevious:
            .edit
        case .commandPalette, .openSettings, .openSettingsJSON, .reloadSettings:
            .app
        }
    }

    public var title: String {
        switch self {
        case .newWindow: "New Window"
        case .newTab: "New Tab"
        case .closePane: "Close Pane"
        case .closeTab: "Close Tab"
        case .closeWindow: "Close Window"
        case .splitRight: "Split Right"
        case .splitDown: "Split Down"
        case .focusNextPane: "Next Pane"
        case .focusPreviousPane: "Previous Pane"
        case .focusPaneLeft: "Focus Pane Left"
        case .focusPaneRight: "Focus Pane Right"
        case .focusPaneUp: "Focus Pane Above"
        case .focusPaneDown: "Focus Pane Below"
        case .zoomPane: "Zoom Pane"
        case .equalizePanes: "Equalize Pane Sizes"
        case .nextTab: "Next Tab"
        case .previousTab: "Previous Tab"
        case .moveTabLeft: "Move Tab Left"
        case .moveTabRight: "Move Tab Right"
        case .selectTab1, .selectTab2, .selectTab3, .selectTab4, .selectTab5, .selectTab6, .selectTab7, .selectTab8, .selectTab9:
            "Select Tab \(tabIndex! + 1)"
        case .toggleLeftDock: "Show/Hide Left Side"
        case .toggleRightDock: "Show/Hide Right Side"
        case .toggleStats: "Show/Hide System Panel"
        case .cycleStatsPlacement: "Move System Panel (Left → Right → Strip)"
        case .importPanel: "Import Panel Code…"
        case .focusTree: "Focus File Tree"
        case .focusTerminal: "Focus Terminal"
        case .revealCwdInTree: "Reveal Current Directory"
        case .toggleHiddenFiles: "Show/Hide Hidden Files"
        case .collapseTree: "Collapse Tree"
        case .cycleTreeRoot: "Cycle Tree Root"
        case .toggleIDE: "Open/Close Editor"
        case .openFileInEditor: "Open File in Editor…"
        case .save: "Save"
        case .saveAs: "Save As…"
        case .goToLine: "Go to Line…"
        case .toggleComment: "Toggle Comment"
        case .runFile: "Run File"
        case .commandPalette: "Command Palette…"
        case .openSettings: "Settings…"
        case .openSettingsJSON: "Open settings.json"
        case .reloadSettings: "Reload Settings"
        case .increaseFont: "Bigger Font"
        case .decreaseFont: "Smaller Font"
        case .resetFont: "Default Font Size"
        case .nextTheme: "Next Theme"
        case .previousTheme: "Previous Theme"
        case .toggleEffects: "Toggle All Effects"
        case .toggleGlow: "Toggle Glow"
        case .toggleScanlines: "Toggle Scanlines"
        case .toggleTransparency: "Toggle Transparency"
        case .toggleGradient: "Toggle Animated Gradient"
        case .find: "Find…"
        case .findNext: "Find Next"
        case .findPrevious: "Find Previous"
        case .clearBuffer: "Clear Buffer"
        case .scrollToTop: "Scroll to Top"
        case .scrollToBottom: "Scroll to Bottom"
        case .toggleFullScreen: "Toggle Full Screen"
        case .toggleAlwaysOnTop: "Toggle Always on Top"
        case .copyCwd: "Copy Current Directory Path"
        case .openCwdInFinder: "Open Current Directory in Finder"
        }
    }

    public var symbol: String {
        switch category {
        case .shell: "terminal"
        case .editor: "doc.text"
        case .window: "macwindow"
        case .view: "sidebar.left"
        case .tree: "folder"
        case .appearance: "paintpalette"
        case .edit: "magnifyingglass"
        case .app: "gearshape"
        }
    }

    public var tabIndex: Int? {
        switch self {
        case .selectTab1: 0
        case .selectTab2: 1
        case .selectTab3: 2
        case .selectTab4: 3
        case .selectTab5: 4
        case .selectTab6: 5
        case .selectTab7: 6
        case .selectTab8: 7
        case .selectTab9: 8
        default: nil
        }
    }

    public var defaultBinding: String {
        switch self {
        case .newWindow: "cmd+n"
        case .newTab: "cmd+t"
        case .closePane: "cmd+w"
        case .closeTab: "cmd+alt+w"
        case .closeWindow: "cmd+shift+w"
        case .splitRight: "cmd+d"
        case .splitDown: "cmd+shift+d"
        case .focusNextPane: "cmd+]"
        case .focusPreviousPane: "cmd+["
        case .focusPaneLeft: "cmd+alt+left"
        case .focusPaneRight: "cmd+alt+right"
        case .focusPaneUp: "cmd+alt+up"
        case .focusPaneDown: "cmd+alt+down"
        case .zoomPane: "cmd+shift+return"
        case .equalizePanes: "cmd+ctrl+="
        case .nextTab: "cmd+shift+]"
        case .previousTab: "cmd+shift+["
        case .moveTabLeft: "cmd+shift+left"
        case .moveTabRight: "cmd+shift+right"
        case .selectTab1, .selectTab2, .selectTab3, .selectTab4, .selectTab5, .selectTab6, .selectTab7, .selectTab8, .selectTab9:
            "cmd+\(tabIndex! + 1)"
        case .toggleLeftDock: "cmd+b"
        case .toggleRightDock: "cmd+alt+b"
        case .toggleStats: "cmd+alt+s"
        case .cycleStatsPlacement: ""
        case .importPanel: "cmd+alt+i"
        case .focusTree: "cmd+shift+e"
        case .focusTerminal: "cmd+alt+t"
        case .revealCwdInTree: "cmd+shift+r"
        case .toggleHiddenFiles: "cmd+shift+."
        case .collapseTree: "cmd+alt+c"
        case .cycleTreeRoot: "cmd+alt+r"
        case .toggleIDE: "cmd+shift+i"
        case .openFileInEditor: "cmd+o"
        case .save: "cmd+s"
        case .saveAs: "cmd+shift+s"
        case .goToLine: "cmd+l"
        case .toggleComment: "cmd+/"
        case .runFile: "cmd+r"
        case .commandPalette: "cmd+shift+p"
        case .openSettings: "cmd+,"
        case .openSettingsJSON: "cmd+alt+,"
        case .reloadSettings: ""
        case .increaseFont: "cmd+="
        case .decreaseFont: "cmd+-"
        case .resetFont: "cmd+0"
        case .nextTheme: "cmd+alt+]"
        case .previousTheme: "cmd+alt+["
        case .toggleEffects: "cmd+alt+e"
        case .toggleGlow: "cmd+alt+g"
        case .toggleScanlines: ""
        case .toggleTransparency: "cmd+u"
        case .toggleGradient: ""
        case .find: "cmd+f"
        case .findNext: "cmd+g"
        case .findPrevious: "cmd+shift+g"
        case .clearBuffer: "cmd+k"
        case .scrollToTop: "cmd+home"
        case .scrollToBottom: "cmd+end"
        case .toggleFullScreen: "cmd+ctrl+f"
        case .toggleAlwaysOnTop: ""
        case .copyCwd: "cmd+shift+c"
        case .openCwdInFinder: "cmd+shift+o"
        }
    }

    /// Actions that only make sense while the code editor has keyboard focus. Their keys fall through
    /// to the terminal/menus otherwise.
    public var isEditorOnly: Bool {
        switch self {
        case .save, .saveAs, .goToLine, .toggleComment: true
        default: false
        }
    }

    /// Effective bindings: defaults with the user's overrides applied ("" unbinds).
    public static func resolvedBindings(overrides: [String: String]) -> [AppAction: KeyCombo] {
        var out: [AppAction: KeyCombo] = [:]
        for action in AppAction.allCases {
            let s = overrides[action.rawValue] ?? action.defaultBinding
            if let combo = KeyCombo(s) { out[action] = combo }
        }
        return out
    }
}
