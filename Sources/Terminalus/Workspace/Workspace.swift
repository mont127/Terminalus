import AppKit
import Observation
import TerminalusCore

@MainActor
@Observable
final class TabModel: Identifiable {
    let id = UUID().uuidString
    var root: PaneNode
    var focusedPaneID: String
    var zoomedPaneID: String?
    var customTitle: String?
    /// Non-nil while this tab is in IDE mode (editor above, terminals below).
    var editor: EditorSession?

    init(paneID: String) {
        root = .leaf(paneID)
        focusedPaneID = paneID
    }
}

/// The contents of one window: tabs, their split trees, the sessions and the file tree.
@MainActor
@Observable
final class Workspace {
    private(set) var tabs: [TabModel] = []
    private(set) var selectedTabID: String?
    private(set) var sessions: [String: TerminalSession] = [:]
    var paletteVisible = false {
        didSet { if paletteVisible && !oldValue { paletteSelection = 0 } }
    }
    var paletteQuery = "" {
        didSet { if paletteQuery != oldValue { paletteSelection = 0 } }
    }
    var paletteSelection = 0
    /// Recently visited directories, most recent first (for the command palette).
    private(set) var recentDirectories: [String] = []
    let tree = FileTreeModel()
    /// A side panel being dragged to the other dock.
    var panelDrag: PanelDrag?

    @ObservationIgnored weak var window: NSWindow?
    @ObservationIgnored var dockFrames: [DockSide: CGRect] = [:]
    @ObservationIgnored var panelFrames: [String: CGRect] = [:]
    @ObservationIgnored var layoutSize: CGSize = .zero
    @ObservationIgnored private var webControllers: [String: WebPanelController] = [:]
    @ObservationIgnored private var commandControllers: [String: CommandPanelController] = [:]
    @ObservationIgnored private var appliedAppearance: [String: TerminalAppearance] = [:]
    @ObservationIgnored var onEmpty: (() -> Void)?

    var windowIsActive = true

    init() {
        tree.workspace = self
    }

    // MARK: Accessors

    var selectedTab: TabModel? { tabs.first { $0.id == selectedTabID } ?? tabs.first }

    var focusedSession: TerminalSession? {
        guard let t = selectedTab else { return nil }
        return sessions[t.focusedPaneID]
    }

    func tab(containing sessionID: String) -> TabModel? {
        tabs.first { $0.root.contains(sessionID) }
    }

    func sessions(in tab: TabModel) -> [TerminalSession] {
        tab.root.leaves.compactMap { sessions[$0] }
    }

    // MARK: Creating

    private func makeSession(profileID: String?, cwd: String?, command: String? = nil) -> TerminalSession {
        let app = AppState.shared
        let settings = app.settings
        let profile = settings.profile(id: profileID)
        let dir = resolveWorkingDirectory(profile: profile, requested: cwd)
        let appearance = app.appearance(for: profile)
        let s = TerminalSession(profile: profile, cwd: dir, appearance: appearance, command: command)
        s.workspace = self
        appliedAppearance[s.id] = appearance
        sessions[s.id] = s
        s.start(profile: profile, terminalSettings: settings.terminal)
        return s
    }

    private func resolveWorkingDirectory(profile: Profile, requested: String?) -> String {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        if let r = requested, fm.fileExists(atPath: r, isDirectory: &isDir), isDir.boolValue { return r }
        switch profile.workingDirectory {
        case .home:
            return NSHomeDirectory()
        case .inherit:
            if let c = focusedSession?.cwd, fm.fileExists(atPath: c) { return c }
            return NSHomeDirectory()
        case .custom:
            let p = (profile.customDirectory as NSString).expandingTildeInPath
            if fm.fileExists(atPath: p, isDirectory: &isDir), isDir.boolValue { return p }
            return NSHomeDirectory()
        }
    }

    @discardableResult
    func newTab(profileID: String? = nil, cwd: String? = nil) -> TerminalSession {
        let s = makeSession(profileID: profileID, cwd: cwd)
        let t = TabModel(paneID: s.id)
        if let sel = selectedTab, let idx = tabs.firstIndex(where: { $0.id == sel.id }) {
            tabs.insert(t, at: idx + 1)
        } else {
            tabs.append(t)
        }
        select(tab: t)
        return s
    }

    func split(_ axis: SplitAxis, profileID: String? = nil, cwd: String? = nil, command: String? = nil) {
        guard let t = selectedTab else {
            newTab(profileID: profileID, cwd: cwd)
            return
        }
        let current = sessions[t.focusedPaneID]
        let s = makeSession(profileID: profileID ?? current?.profileID, cwd: cwd ?? current?.cwd, command: command)
        t.zoomedPaneID = nil
        t.root = t.root.splitting(t.focusedPaneID, with: s.id, axis: axis)
        focus(sessionID: s.id)
    }

    // MARK: Focus & selection

    func select(tab: TabModel) {
        selectedTabID = tab.id
        focus(sessionID: tab.focusedPaneID, makeFirstResponder: tab.editor == nil)
        tab.editor?.focusActive()
    }

    func selectTab(at index: Int) {
        guard tabs.indices.contains(index) else { return }
        select(tab: tabs[index])
    }

    func selectAdjacentTab(_ delta: Int) {
        guard let t = selectedTab, let i = tabs.firstIndex(where: { $0.id == t.id }), !tabs.isEmpty else { return }
        select(tab: tabs[(i + delta + tabs.count) % tabs.count])
    }

    func moveSelectedTab(_ delta: Int) {
        guard let t = selectedTab, let i = tabs.firstIndex(where: { $0.id == t.id }) else { return }
        let j = i + delta
        guard tabs.indices.contains(j) else { return }
        tabs.swapAt(i, j)
    }

    func moveTab(id: String, to index: Int) {
        guard let i = tabs.firstIndex(where: { $0.id == id }) else { return }
        let t = tabs.remove(at: i)
        tabs.insert(t, at: min(max(0, index), tabs.count))
    }

    func focus(sessionID: String, makeFirstResponder: Bool = true) {
        guard let t = tab(containing: sessionID) else { return }
        if selectedTabID != t.id { selectedTabID = t.id }
        if t.focusedPaneID != sessionID { t.focusedPaneID = sessionID }
        for (id, s) in sessions { s.isFocused = (id == sessionID) }
        guard let s = sessions[sessionID] else { return }
        if makeFirstResponder {
            // Deferred so the pane is in the window hierarchy after SwiftUI's update pass.
            DispatchQueue.main.async { [weak self, weak s] in
                guard let self, let s, self.focusedSession === s, let w = self.window else { return }
                if w.firstResponder !== s.view { w.makeFirstResponder(s.view) }
            }
        }
        tree.follow(cwd: s.cwd, remote: s.isRemote)
        noteRecent(s.cwd)
        panelsCwdChanged()
    }

    /// Called when the window's first responder becomes a terminal view (e.g. the user clicked it).
    func terminalBecameFirstResponder(_ view: TerminalusTerminalView) {
        guard let s = view.session, focusedSession !== s || !s.isFocused else { return }
        focus(sessionID: s.id, makeFirstResponder: false)
    }

    func focusNextPane(_ delta: Int) {
        guard let t = selectedTab else { return }
        let leaves = t.root.leaves
        guard let i = leaves.firstIndex(of: t.focusedPaneID), leaves.count > 1 else { return }
        t.zoomedPaneID = nil
        focus(sessionID: leaves[(i + delta + leaves.count) % leaves.count])
    }

    func focusPane(_ dir: PaneDirection) {
        guard let t = selectedTab, let n = t.root.neighbor(of: t.focusedPaneID, dir) else { return }
        t.zoomedPaneID = nil
        focus(sessionID: n)
    }

    func toggleZoom() {
        guard let t = selectedTab, t.root.leaves.count > 1 else { return }
        t.zoomedPaneID = t.zoomedPaneID == nil ? t.focusedPaneID : nil
        focus(sessionID: t.focusedPaneID)
    }

    func equalizePanes() {
        guard let t = selectedTab else { return }
        t.root = t.root.equalized()
    }

    func resizeSplit(path: [Bool], fraction: Double) {
        guard let t = selectedTab else { return }
        t.root = t.root.settingFraction(at: path, to: fraction)
    }

    // MARK: Closing

    private func needsConfirmation(_ list: [TerminalSession]) -> Bool {
        switch AppState.shared.settings.terminal.confirmClose {
        case .never: false
        case .always: !list.isEmpty
        case .whenRunning: list.contains { $0.hasRunningCommand }
        }
    }

    private func confirm(_ list: [TerminalSession], what: String) -> Bool {
        guard needsConfirmation(list) else { return true }
        let running = list.filter(\.hasRunningCommand).compactMap { $0.runningCommand ?? $0.foregroundProcess }
        let alert = NSAlert()
        alert.messageText = "Close \(what)?"
        alert.informativeText = running.isEmpty
            ? "The shell will be terminated."
            : "Still running: \(running.prefix(4).joined(separator: ", ")). Closing will terminate it."
        alert.addButton(withTitle: "Close")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        return alert.runModal() == .alertFirstButtonReturn
    }

    func closePane(_ sessionID: String? = nil, force: Bool = false) {
        guard let id = sessionID ?? selectedTab?.focusedPaneID, let s = sessions[id], let t = tab(containing: id) else { return }
        if !force && !s.exited && !confirm([s], what: "this pane") { return }
        removeSession(s, from: t)
    }

    private func removeSession(_ s: TerminalSession, from t: TabModel) {
        s.terminate()
        s.container.removeFromSuperview()
        sessions[s.id] = nil
        appliedAppearance[s.id] = nil
        if let newRoot = t.root.removing(s.id) {
            t.root = newRoot
            if t.zoomedPaneID == s.id { t.zoomedPaneID = nil }
            if t.focusedPaneID == s.id { t.focusedPaneID = newRoot.leaves.first ?? "" }
            if selectedTabID == t.id { focus(sessionID: t.focusedPaneID) }
        } else {
            removeTab(t)
        }
    }

    func closeTab(_ tabID: String? = nil) {
        guard let t = tabs.first(where: { $0.id == (tabID ?? selectedTab?.id) }) else { return }
        if let ed = t.editor, !ed.closeAll() { return }
        let list = sessions(in: t).filter { !$0.exited }
        if !confirm(list, what: "this tab") { return }
        for s in sessions(in: t) {
            s.terminate()
            s.container.removeFromSuperview()
            sessions[s.id] = nil
            appliedAppearance[s.id] = nil
        }
        removeTab(t)
    }

    private func removeTab(_ t: TabModel) {
        guard let i = tabs.firstIndex(where: { $0.id == t.id }) else { return }
        t.editor?.releaseAll()
        t.editor = nil
        tabs.remove(at: i)
        if tabs.isEmpty {
            selectedTabID = nil
            onEmpty?()
            return
        }
        if selectedTabID == t.id {
            select(tab: tabs[min(i, tabs.count - 1)])
        }
    }

    /// Asks for confirmation (if configured) before the whole window closes.
    func confirmCloseAll() -> Bool {
        for t in tabs {
            if let ed = t.editor, ed.documents.contains(where: \.isDirty) {
                select(tab: t)
                if !ed.closeAll() { return false }
            }
        }
        return confirm(Array(sessions.values.filter { !$0.exited }), what: "this window")
    }

    func teardown() {
        for t in tabs { t.editor?.releaseAll() }
        commandControllers.values.forEach { $0.stop() }
        commandControllers.removeAll()
        webControllers.removeAll()
        for s in sessions.values { s.terminate() }
        sessions.removeAll()
        tabs.removeAll()
        tree.stop()
    }

    // MARK: Session callbacks

    func sessionCwdChanged(_ s: TerminalSession) {
        guard s === focusedSession else { return }
        tree.follow(cwd: s.cwd, remote: s.isRemote)
        noteRecent(s.cwd)
        panelsCwdChanged()
    }

    func sessionCommandFinished(_ s: TerminalSession) {
        if s === focusedSession { tree.scheduleGitRefresh() }
    }

    func sessionExited(_ s: TerminalSession) {
        guard AppState.shared.settings.terminal.onExit == .close, let t = tab(containing: s.id) else { return }
        // Let the final output flush before the pane disappears.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self, self.sessions[s.id] != nil else { return }
            self.removeSession(s, from: t)
        }
    }

    private func noteRecent(_ dir: String) {
        guard recentDirectories.first != dir else { return }
        recentDirectories.removeAll { $0 == dir }
        recentDirectories.insert(dir, at: 0)
        if recentDirectories.count > 40 { recentDirectories.removeLast(recentDirectories.count - 40) }
    }

    // MARK: Appearance

    func applyAppearance() {
        let app = AppState.shared
        for (id, s) in sessions {
            let profile = app.settings.profile(id: s.profileID)
            let a = app.appearance(for: profile)
            let prev = appliedAppearance[id]
            if prev != a {
                a.apply(to: s.view, container: s.container, previous: prev)
                appliedAppearance[id] = a
            }
        }
    }

    // MARK: Actions on the focused session

    /// Like Terminal.app's ⌘K: drops the scrollback and asks the shell to redraw its prompt.
    func clearBuffer() {
        guard let s = focusedSession else { return }
        s.view.clearScrollback()
        if s.isAtPrompt { s.send("\u{0C}") }
    }

    // MARK: Docks & panels

    /// Panels shown on a side right now (IDE mode hides System and adds Outline).
    func effectivePanels(_ side: DockSide) -> [String] {
        let app = AppState.shared
        let s = app.settings
        let ide = selectedTab?.editor != nil
        var ids = s.layout.panels(on: side).filter { id in
            switch id {
            case PanelID.files: return true
            case PanelID.system: return !(ide && s.editor.hideSystemPanel)
            case PanelID.outline: return ide
            default: return PanelID.customID(id).flatMap { app.panels.panel(id: $0) } != nil
            }
        }
        if ide, s.editor.showOutline, side == .right, s.layout.side(of: PanelID.outline) == nil {
            ids.append(PanelID.outline)
        }
        return ids
    }

    func isDockVisible(_ side: DockSide) -> Bool {
        let l = AppState.shared.settings.layout
        return (side == .left ? l.leftDockVisible : l.rightDockVisible) && !effectivePanels(side).isEmpty
    }

    /// Where a dragged panel would land: inside a visible dock, or near the window edge for a hidden one.
    func dropZone(for side: DockSide) -> CGRect {
        if isDockVisible(side), let f = dockFrames[side] { return f }
        let w: CGFloat = 110
        return side == .left
            ? CGRect(x: 0, y: 0, width: w, height: layoutSize.height)
            : CGRect(x: layoutSize.width - w, y: 0, width: w, height: layoutSize.height)
    }

    func dropTarget(at p: CGPoint, dragging id: String) -> PanelDropTarget? {
        for side in [DockSide.left, .right] where dropZone(for: side).insetBy(dx: -8, dy: 0).contains(p) {
            let others = effectivePanels(side).filter { $0 != id }
            let index = others.filter { (panelFrames[$0]?.midY ?? .infinity) < p.y }.count
            return PanelDropTarget(side: side, index: index)
        }
        return nil
    }

    func insertionY(for drag: PanelDrag) -> CGFloat? {
        guard let t = drag.target else { return nil }
        let zone = dropZone(for: t.side)
        let others = effectivePanels(t.side).filter { $0 != drag.id }
        if others.isEmpty || !isDockVisible(t.side) { return zone.minY + 40 }
        if t.index < others.count, let f = panelFrames[others[t.index]] { return f.minY }
        if let last = others.last, let f = panelFrames[last] { return min(f.maxY, zone.maxY - 6) }
        return zone.minY + 40
    }

    func webController(for p: CustomPanel) -> WebPanelController {
        if let c = webControllers[p.id] { return c }
        let c = WebPanelController(panel: p, workspace: self)
        webControllers[p.id] = c
        return c
    }

    func commandController(for p: CustomPanel) -> CommandPanelController {
        if let c = commandControllers[p.id] { return c }
        let c = CommandPanelController(panel: p, workspace: self)
        commandControllers[p.id] = c
        return c
    }

    func panelUpdated(_ p: CustomPanel) {
        webControllers[p.id]?.update(p)
        commandControllers[p.id]?.update(p)
    }

    func panelDeleted(_ id: String) {
        commandControllers[id]?.stop()
        commandControllers[id] = nil
        webControllers[id]?.webView.removeFromSuperview()
        webControllers[id] = nil
    }

    private func panelsCwdChanged() {
        webControllers.values.forEach { $0.cwdChanged() }
        commandControllers.values.forEach { $0.cwdChanged() }
    }

    func panelsGitChanged() { webControllers.values.forEach { $0.gitChanged() } }

    func panelsThemeChanged() {
        webControllers.values.forEach { $0.themeChanged() }
        commandControllers.values.forEach { $0.applyTheme() }
    }

    func panelsStatsTick() { webControllers.values.forEach { $0.statsTick() } }

    // MARK: IDE

    /// `nano file` (or vim, micro…) in a shell with integration lands here.
    func handleEditRequest(from s: TerminalSession, command: String, fifo: String, files: [EditTarget]) {
        guard let t = tab(containing: s.id) else {
            EditReply.send("fallback", to: fifo)
            s.editorRequestFinished()
            return
        }
        if selectedTabID != t.id { select(tab: t) }
        let editor = ensureEditor(t)
        var ids = Set<String>()
        for f in files.isEmpty ? [nil] : files.map(Optional.some) {
            if let doc = editor.open(f) { ids.insert(doc.id) }
        }
        if ids.isEmpty {
            // Nothing could be opened here (binary file…): let the real editor handle it.
            if editor.documents.isEmpty { closeEditor(for: t) }
            EditReply.send("fallback", to: fifo)
            s.editorRequestFinished()
            return
        }
        editor.addRequest(fifo: fifo, command: command, sessionID: s.id, documentIDs: ids)
        editor.focusActive()
    }

    func editorWaitEnded(_ s: TerminalSession) {
        for t in tabs { t.editor?.dropRequests(for: s.id) }
    }

    @discardableResult
    func ensureEditor(_ t: TabModel) -> EditorSession {
        if let e = t.editor { return e }
        let e = EditorSession(workspace: self, tab: t)
        t.editor = e
        return e
    }

    /// Opens files in the IDE of the selected tab (tree double-click, ⌘O, palette).
    func openInEditor(_ paths: [String], line: Int = 0) {
        guard let t = selectedTab else { return }
        let editor = ensureEditor(t)
        if paths.isEmpty { editor.open(nil) }
        for p in paths { editor.open(EditTarget(path: p, line: line)) }
        if editor.documents.isEmpty { closeEditor(for: t) }
    }

    func closeEditor(for tab: TabModel?) {
        guard let tab, let ed = tab.editor else { return }
        ed.releaseAll()
        tab.editor = nil
        if selectedTabID == tab.id { focus(sessionID: tab.focusedPaneID) }
    }

    func toggleEditor() {
        guard let t = selectedTab else { return }
        if let ed = t.editor {
            _ = ed.closeAll()
            if t.editor != nil && ed.documents.isEmpty { closeEditor(for: t) }
        } else {
            openInEditor([])
        }
    }

    /// Runs a command in the tab: in an idle shell if there is one, otherwise in a new pane below.
    func runInTab(_ t: TabModel, command: String, cwd: String) {
        let idle = sessions(in: t).first { $0.isAtPrompt && !$0.isRemote }
        if let s = idle {
            if s.cwd != cwd {
                s.send("\u{05}\u{15}cd -- \(ShellLauncher.shellEscape(cwd)) && \(command)\r")
            } else {
                s.send("\u{05}\u{15}\(command)\r")
            }
            return
        }
        if selectedTabID != t.id { select(tab: t) }
        split(.vertical, cwd: cwd, command: command)
    }
}
