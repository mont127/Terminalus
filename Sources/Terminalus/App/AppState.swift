import AppKit
import Observation
import SwiftUI
import TerminalusCore

/// Global state: settings, themes, stats and windows. Applies settings changes everywhere and
/// executes AppActions.
@MainActor
@Observable
final class AppState {
    static let shared = AppState()

    let settingsStore: SettingsStore
    let themes = ThemeCatalog()
    let stats = StatsStore()
    let panels = PanelStore()
    private(set) var windowControllers: [MainWindowController] = []
    private(set) var systemIsDark = true
    /// The workspace of the key (or most recently key) main window.
    private(set) var activeWorkspace: Workspace?

    @ObservationIgnored private(set) var bindings: [AppAction: KeyCombo] = [:]
    @ObservationIgnored private var appearanceObservation: NSKeyValueObservation?
    @ObservationIgnored private var resolvedCache: [String: ResolvedTheme] = [:]
    @ObservationIgnored var settingsWindow: SettingsWindowController?

    var settings: AppSettings { settingsStore.settings }

    private init() {
        let safe = NSEvent.modifierFlags.contains(.option)
        settingsStore = SettingsStore(safeMode: safe)
    }

    func start() {
        bindings = AppAction.resolvedBindings(overrides: settings.keybindings)
        systemIsDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] app, _ in
            let dark = app.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            Task { @MainActor in
                guard let self, self.systemIsDark != dark else { return }
                self.systemIsDark = dark
                self.resolvedCache.removeAll()
                self.applyAppearanceEverywhere()
            }
        }
        settingsStore.onChange = { [weak self] old, new in self?.settingsDidChange(old: old, new: new) }
        stats.configure(settings: settings)
        MainMenu.install()
        newWindow()
    }

    // MARK: Themes & appearance

    var effectiveThemeID: String {
        let a = settings.appearance
        if a.followSystemAppearance { return systemIsDark ? a.darkThemeID : a.lightThemeID }
        return a.themeID
    }

    func resolvedTheme(id: String) -> ResolvedTheme {
        let key = id + "|" + (settings.appearance.accentOverride ?? "")
        if let cached = resolvedCache[key] { return cached }
        let r = ResolvedTheme(themes.theme(id: id), accentOverride: settings.appearance.accentOverride)
        resolvedCache[key] = r
        return r
    }

    /// Theme used for the UI chrome and the window background.
    var uiTheme: ResolvedTheme { resolvedTheme(id: effectiveThemeID) }

    func theme(for profile: Profile) -> ResolvedTheme {
        resolvedTheme(id: profile.themeID ?? effectiveThemeID)
    }

    func appearance(for profile: Profile) -> TerminalAppearance {
        let own = profile.themeID.map { $0 != effectiveThemeID } ?? false
        return TerminalAppearance(settings: settings, profile: profile, theme: theme(for: profile), ownBackground: own)
    }

    func themesChanged() {
        resolvedCache.removeAll()
        applyAppearanceEverywhere()
        for wc in windowControllers { wc.workspace.panelsThemeChanged() }
    }

    private func applyAppearanceEverywhere() {
        for wc in windowControllers {
            wc.workspace.applyAppearance()
            wc.applyWindowSettings()
        }
    }

    // MARK: Settings changes

    private func settingsDidChange(old: AppSettings, new: AppSettings) {
        if old.appearance.accentOverride != new.appearance.accentOverride { resolvedCache.removeAll() }
        if old.keybindings != new.keybindings {
            bindings = AppAction.resolvedBindings(overrides: new.keybindings)
        }
        let placement: (LayoutSettings) -> [String] = { l in l.leftPanels + ["|"] + l.rightPanels + [l.leftDockVisible ? "L" : "l", l.rightDockVisible ? "R" : "r", l.statsStrip ? "S" : "s"] }
        if old.keybindings != new.keybindings || placement(old.layout) != placement(new.layout) || old.profiles != new.profiles {
            MainMenu.install()
        }
        for wc in windowControllers {
            wc.workspace.applyAppearance()
            wc.applyWindowSettings()
            if old.tree != new.tree { wc.workspace.tree.apply(settings: new.tree) }
        }
        if old.stats != new.stats || old.layout.leftPanels != new.layout.leftPanels
            || old.layout.rightPanels != new.layout.rightPanels || old.layout.statsStrip != new.layout.statsStrip {
            stats.configure(settings: new)
        }
        if old.appearance != new.appearance || old.terminal.font != new.terminal.font {
            for wc in windowControllers { wc.workspace.panelsThemeChanged() }
        }
    }

    // MARK: Custom panels

    /// Panels that exist but are not placed in either dock.
    var hiddenPanelIDs: [String] {
        let l = settings.layout
        let all = [PanelID.files, PanelID.system, PanelID.outline] + panels.panels.map { PanelID.custom($0.id) }
        return all.filter { l.side(of: $0) == nil }
    }

    func panelChanged(_ p: CustomPanel) {
        for wc in windowControllers { wc.workspace.panelUpdated(p) }
        MainMenu.install()
    }

    func deletePanel(_ p: CustomPanel) {
        let alert = NSAlert()
        alert.messageText = "Delete the panel “\(p.name)”?"
        alert.informativeText = "Its code is removed. Use “Copy Panel Code” first if you want to keep it."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        settingsStore.update { $0.layout.remove(PanelID.custom(p.id)) }
        panels.delete(id: p.id)
        for wc in windowControllers { wc.workspace.panelDeleted(p.id) }
        MainMenu.install()
    }

    func statsTicked() {
        for wc in windowControllers { wc.workspace.panelsStatsTick() }
    }

    /// The code editor that has keyboard focus, if any.
    var focusedEditor: (EditorSession, EditorDocument)? {
        guard let tv = NSApp.keyWindow?.firstResponder as? CodeTextView, let doc = tv.controller?.document,
              let ws = activeWorkspace else { return nil }
        for t in ws.tabs {
            if let ed = t.editor, ed.documents.contains(where: { $0 === doc }) { return (ed, doc) }
        }
        return nil
    }

    // MARK: Windows

    @discardableResult
    func newWindow(cwd: String? = nil, profileID: String? = nil) -> MainWindowController {
        let ws = Workspace()
        let wc = MainWindowController(workspace: ws, cascadeFrom: windowControllers.last?.window)
        windowControllers.append(wc)
        ws.newTab(profileID: profileID, cwd: cwd ?? activeWorkspace?.focusedSession?.cwd)
        if Automation.directory != nil {
            wc.window?.orderBack(nil)
        } else {
            wc.showWindow(nil)
            wc.window?.makeKeyAndOrderFront(nil)
        }
        activeWorkspace = ws
        return wc
    }

    func windowBecameKey(_ wc: MainWindowController) {
        activeWorkspace = wc.workspace
    }

    func windowClosed(_ wc: MainWindowController) {
        windowControllers.removeAll { $0 === wc }
        if activeWorkspace === wc.workspace { activeWorkspace = windowControllers.last?.workspace }
    }

    var hasRunningCommands: Bool {
        windowControllers.contains { wc in wc.workspace.sessions.values.contains { $0.hasRunningCommand } }
    }

    // MARK: Actions

    func perform(_ action: AppAction) {
        let ws = activeWorkspace
        switch action {
        case .newWindow: newWindow()
        case .newTab:
            if let ws { ws.newTab() } else { newWindow() }
        case .closePane:
            // In IDE mode ⌘W closes the open file (the last one returns to the plain terminal).
            if let (ed, doc) = focusedEditor ?? activeEditorPair { ed.close(doc) } else { ws?.closePane() }
        case .closeTab: ws?.closeTab()
        case .closeWindow: ws?.window?.performClose(nil)
        case .splitRight: ws?.split(.horizontal)
        case .splitDown: ws?.split(.vertical)
        case .focusNextPane: ws?.focusNextPane(1)
        case .focusPreviousPane: ws?.focusNextPane(-1)
        case .focusPaneLeft: ws?.focusPane(.left)
        case .focusPaneRight: ws?.focusPane(.right)
        case .focusPaneUp: ws?.focusPane(.up)
        case .focusPaneDown: ws?.focusPane(.down)
        case .zoomPane: ws?.toggleZoom()
        case .equalizePanes: ws?.equalizePanes()
        case .nextTab: ws?.selectAdjacentTab(1)
        case .previousTab: ws?.selectAdjacentTab(-1)
        case .moveTabLeft: ws?.moveSelectedTab(-1)
        case .moveTabRight: ws?.moveSelectedTab(1)
        case .selectTab1, .selectTab2, .selectTab3, .selectTab4, .selectTab5, .selectTab6, .selectTab7, .selectTab8:
            ws?.selectTab(at: action.tabIndex!)
        case .selectTab9:
            if let ws { ws.selectTab(at: ws.tabs.count - 1) }
        case .toggleLeftDock: settingsStore.update { $0.layout.leftDockVisible.toggle() }
        case .toggleRightDock:
            settingsStore.update {
                if $0.layout.rightPanels.isEmpty && ws?.effectivePanels(.right).isEmpty ?? true {
                    // Nothing on the right yet: move the System panel over so the side shows something.
                    $0.layout.move(PanelID.system, to: .right)
                } else {
                    $0.layout.rightDockVisible.toggle()
                }
            }
        case .toggleStats:
            settingsStore.update {
                if $0.layout.side(of: PanelID.system) != nil {
                    lastSystemSide = $0.layout.side(of: PanelID.system) ?? .left
                    $0.layout.remove(PanelID.system)
                } else {
                    $0.layout.move(PanelID.system, to: lastSystemSide)
                }
            }
        case .cycleStatsPlacement:
            settingsStore.update {
                switch ($0.layout.side(of: PanelID.system), $0.layout.statsStrip) {
                case (.left?, _):
                    $0.layout.move(PanelID.system, to: .right)
                case (.right?, _):
                    $0.layout.remove(PanelID.system)
                    $0.layout.statsStrip = true
                default:
                    $0.layout.statsStrip = false
                    $0.layout.move(PanelID.system, to: .left)
                }
            }
        case .importPanel: PanelImportWindowController.show()
        case .toggleIDE: ws?.toggleEditor()
        case .openFileInEditor:
            let panel = NSOpenPanel()
            panel.allowsMultipleSelection = true
            panel.canChooseDirectories = false
            if let c = ws?.focusedSession?.cwd { panel.directoryURL = URL(fileURLWithPath: c) }
            if panel.runModal() == .OK { ws?.openInEditor(panel.urls.map(\.path)) }
        case .save:
            if let (ed, doc) = focusedEditor ?? activeEditorPair { ed.save(doc) }
        case .saveAs:
            if let (ed, doc) = focusedEditor ?? activeEditorPair { ed.save(doc, forceChooseLocation: true) }
        case .goToLine:
            if let (_, doc) = focusedEditor ?? activeEditorPair { doc.controller.promptGoToLine() }
        case .toggleComment:
            if let (_, doc) = focusedEditor { doc.controller.textView.toggleComment() }
        case .runFile:
            if let (ed, _) = focusedEditor ?? activeEditorPair { ed.runActive() }
        case .focusTree:
            settingsStore.update { s in
                if let side = s.layout.side(of: PanelID.files) {
                    if side == .left { s.layout.leftDockVisible = true } else { s.layout.rightDockVisible = true }
                    s.layout.collapsedPanels.removeAll { $0 == PanelID.files }
                } else {
                    s.layout.move(PanelID.files, to: .left, at: 0)
                }
            }
            DispatchQueue.main.async { ws?.tree.focusOutline() }
        case .focusTerminal: ws?.focusedSession?.focusTerminal()
        case .revealCwdInTree:
            if let ws, let s = ws.focusedSession { ws.tree.reveal(s.cwd, select: true, force: true) }
        case .toggleHiddenFiles: settingsStore.update { $0.tree.showHidden.toggle() }
        case .collapseTree: ws?.tree.collapseAll()
        case .cycleTreeRoot:
            settingsStore.update {
                let all = TreeRootMode.allCases
                let i = all.firstIndex(of: $0.tree.rootMode) ?? 0
                $0.tree.rootMode = all[(i + 1) % all.count]
            }
        case .commandPalette:
            if let ws { ws.paletteQuery = ""; ws.paletteVisible.toggle() }
        case .openSettings: openSettings()
        case .openSettingsJSON: openSettingsJSON()
        case .reloadSettings:
            settingsStore.loadFromDisk(initial: false)
            themes.reload()
            themesChanged()
        case .increaseFont: settingsStore.update { $0.terminal.font.size = min(72, $0.terminal.font.size + 1) }
        case .decreaseFont: settingsStore.update { $0.terminal.font.size = max(6, $0.terminal.font.size - 1) }
        case .resetFont: settingsStore.update { $0.terminal.font.size = FontSettings().size }
        case .nextTheme: cycleTheme(1)
        case .previousTheme: cycleTheme(-1)
        case .toggleEffects: settingsStore.update { $0.effects.enabled.toggle() }
        case .toggleGlow: settingsStore.update { $0.effects.glow.enabled.toggle() }
        case .toggleScanlines: settingsStore.update { $0.effects.scanlines.enabled.toggle() }
        case .toggleGradient: settingsStore.update { $0.background.gradient.enabled.toggle() }
        case .toggleTransparency:
            settingsStore.update {
                if $0.window.backgroundOpacity < 0.999 {
                    savedOpacity = $0.window.backgroundOpacity
                    $0.window.backgroundOpacity = 1
                } else {
                    $0.window.backgroundOpacity = savedOpacity < 0.999 ? savedOpacity : 0.82
                }
            }
        case .find: sendFinderAction(.showFindInterface)
        case .findNext: sendFinderAction(.nextMatch)
        case .findPrevious: sendFinderAction(.previousMatch)
        case .clearBuffer: ws?.clearBuffer()
        case .scrollToTop: ws?.focusedSession?.view.scrollTo(row: 0)
        case .scrollToBottom:
            ws?.focusedSession?.view.scrollTo(row: Int.max / 2)
        case .toggleFullScreen: ws?.window?.toggleFullScreen(nil)
        case .toggleAlwaysOnTop: settingsStore.update { $0.window.alwaysOnTop.toggle() }
        case .copyCwd:
            if let c = ws?.focusedSession?.cwd {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(c, forType: .string)
            }
        case .openCwdInFinder:
            if let c = ws?.focusedSession?.cwd { NSWorkspace.shared.open(URL(fileURLWithPath: c)) }
        }
    }

    @ObservationIgnored private var lastSystemSide: DockSide = .left

    /// The active document of the selected tab's editor (when the terminal below it has focus).
    private var activeEditorPair: (EditorSession, EditorDocument)? {
        guard let ed = activeWorkspace?.selectedTab?.editor, let doc = ed.active else { return nil }
        return (ed, doc)
    }
    @ObservationIgnored private var savedOpacity: Double = 0.82

    private func cycleTheme(_ delta: Int) {
        let all = themes.all
        guard !all.isEmpty else { return }
        let i = all.firstIndex { $0.id == settings.appearance.themeID } ?? 0
        let next = all[(i + delta + all.count) % all.count]
        settingsStore.update {
            $0.appearance.themeID = next.id
            $0.appearance.followSystemAppearance = false
        }
    }

    private func sendFinderAction(_ action: NSTextFinder.Action) {
        if let (_, doc) = focusedEditor {
            let item = NSMenuItem()
            item.tag = action.rawValue
            doc.controller.textView.performTextFinderAction(item)
            return
        }
        guard let v = activeWorkspace?.focusedSession?.view else { return }
        let item = NSMenuItem()
        item.tag = action.rawValue
        v.performTextFinderAction(item)
    }

    func openSettings() {
        if settingsWindow == nil { settingsWindow = SettingsWindowController() }
        settingsWindow?.showWindow(nil)
        settingsWindow?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func openSettingsJSON() {
        settingsStore.writeNow()
        NSWorkspace.shared.open(settingsStore.fileURL)
    }
}
