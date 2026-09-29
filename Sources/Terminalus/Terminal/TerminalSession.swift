import AppKit
import Observation
import SwiftTerm
import TerminalusCore

/// One shell in one pane: owns the terminal view, the process and everything we know about it
/// (working directory, running command, exit codes…).
@MainActor
@Observable
final class TerminalSession: Identifiable {
    let id: String
    var profileID: String
    @ObservationIgnored let view: TerminalusTerminalView
    @ObservationIgnored let container: TerminalContainerView
    @ObservationIgnored weak var workspace: Workspace?

    // Observable state
    private(set) var cwd: String
    private(set) var isRemote = false
    private(set) var remoteHost: String?
    var terminalTitle = ""
    private(set) var runningCommand: String?
    private(set) var commandStartedAt: Date?
    private(set) var lastCommand: String?
    private(set) var lastExitCode: Int32?
    private(set) var lastDuration: TimeInterval?
    private(set) var foregroundProcess: String?
    private(set) var shellName: String
    private(set) var integrationActive = false
    private(set) var exited = false
    private(set) var exitCode: Int32?
    private(set) var hasUnseenActivity = false
    private(set) var bellPending = false
    private(set) var cols = 80
    private(set) var rows = 24
    /// The shell is blocked in `nano file` (or another intercepted editor) until the IDE closes the file.
    private(set) var waitingForEditor = false
    /// PATH reported by the shell integration (after the user's startup files).
    private(set) var shellPATH: String?
    let startedAt = Date()
    var isFocused = false {
        didSet {
            guard isFocused != oldValue else { return }
            if isFocused {
                hasUnseenActivity = false
                bellPending = false
            }
            schedulePolling()
        }
    }

    @ObservationIgnored private var pollTimer: Timer?
    @ObservationIgnored private var lastOSC7At: Date?
    @ObservationIgnored private var killWork: DispatchWorkItem?
    @ObservationIgnored private var startupCommand: String = ""

    var shellPid: pid_t { view.shellPid }

    init(id: String = UUID().uuidString, profile: Profile, cwd: String, appearance: TerminalAppearance, command: String? = nil) {
        self.id = id
        self.profileID = profile.id
        self.cwd = cwd
        let shellPath = profile.shellPath.isEmpty ? ShellLauncher.userShell : profile.shellPath
        self.shellName = (shellPath as NSString).lastPathComponent
        let options = TerminalOptions(termName: appearance.termName, cursorStyle: appearance.cursorStyle, scrollback: appearance.scrollback)
        let v = TerminalusTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 500), options: options)
        self.view = v
        self.container = TerminalContainerView(terminal: v)
        v.session = self
        appearance.apply(to: v, container: container)
        startupCommand = command ?? profile.startupCommand
    }

    @ObservationIgnored private var launched = false

    /// Starts the shell once the pane has its real size (so the shell never sees a resize right after
    /// drawing its first prompt), or after a short timeout for panes that are not visible yet.
    func start(profile: Profile, terminalSettings: TerminalSettings) {
        let editor = AppState.shared.settings.editor
        let spec = ShellLauncher.makeSpec(profile: profile, terminal: terminalSettings, sessionID: id, workingDirectory: cwd,
                                          editCommands: editor.openEditorsInIDE ? editor.interceptedCommands : [])
        container.onFirstLayout = { [weak self] in self?.launch(spec) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.launch(spec) }
    }

    private func launch(_ spec: ShellLaunchSpec) {
        guard !launched else { return }
        launched = true
        container.onFirstLayout = nil
        view.start(spec)
        let t = view.getTerminal()
        sizeChanged(cols: t.cols, rows: t.rows)
        schedulePolling()
        if !startupCommand.isEmpty {
            let cmd = startupCommand
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.send(cmd + "\r")
            }
        }
    }

    // MARK: Derived

    var displayTitle: String {
        let mode = AppState.shared.settings.terminal.tabTitle
        let dirName = cwd == "/" ? "/" : ((cwd as NSString).lastPathComponent.isEmpty ? cwd : (cwd as NSString).lastPathComponent)
        let dir = cwd == NSHomeDirectory() ? "~" : dirName
        switch mode {
        case .smart:
            if exited { return "\(dir) — exited" }
            if let cmd = runningCommand { return String(cmd.prefix(40)) }
            if let fg = foregroundProcess { return fg }
            return dir
        case .directory:
            return dir
        case .process:
            return foregroundProcess ?? shellName
        case .terminalTitle:
            return terminalTitle.isEmpty ? dir : terminalTitle
        case .profile:
            return AppState.shared.settings.profile(id: profileID).name
        }
    }

    /// True when the shell itself is in the foreground (no command running).
    var isAtPrompt: Bool {
        guard view.isRunning, !waitingForEditor else { return false }
        guard let pg = ProcessInspector.foregroundProcessGroup(ptyMaster: view.ptyFD) else { return true }
        return pg == shellPid
    }

    var hasRunningCommand: Bool { view.isRunning && (waitingForEditor || !isAtPrompt) }

    // MARK: Input helpers

    func send(_ text: String) {
        guard view.isRunning else { return }
        view.send(txt: text)
    }

    func insertPath(_ path: String) {
        send(ShellLauncher.shellEscape(path) + " ")
        focusTerminal()
    }

    /// cd into `path` if the shell is idle at its prompt; otherwise just beep.
    func cd(_ path: String) {
        guard isAtPrompt else {
            NSSound.beep()
            return
        }
        // ^E^U clears whatever is typed at the prompt first.
        send("\u{05}\u{15}cd -- \(ShellLauncher.shellEscape(path))\r")
        focusTerminal()
    }

    func focusTerminal() {
        view.window?.makeFirstResponder(view)
    }

    // MARK: Events from the terminal view

    func handleOSC7(_ raw: String) {
        guard let loc = OSC7Location(raw) else { return }
        lastOSC7At = Date()
        if loc.isLocal {
            if isRemote { isRemote = false; remoteHost = nil }
            setCwd(loc.path)
        } else {
            isRemote = true
            remoteHost = loc.host
        }
    }

    func handleIntegration(_ payload: String) {
        guard let msg = IntegrationMessage(payload: payload) else { return }
        switch msg {
        case .hello:
            integrationActive = true
            schedulePolling()
        case .commandStarted(let cmd):
            runningCommand = cmd.trimmingCharacters(in: .whitespaces)
            commandStartedAt = Date()
        case .path(let p):
            shellPATH = p
        case .edit(let command, let fifo, let files):
            // Only the shell itself (in the foreground) can ask; a program printing a look-alike sequence can't.
            let fg = ProcessInspector.foregroundProcessGroup(ptyMaster: view.ptyFD)
            let settings = AppState.shared.settings.editor
            guard fg == nil || fg == shellPid, EditReply.isSafeFIFO(fifo) else { return }
            guard settings.openEditorsInIDE, settings.interceptedCommands.contains(command), let ws = workspace else {
                EditReply.send("fallback", to: fifo)
                return
            }
            waitingForEditor = true
            ws.handleEditRequest(from: self, command: command, fifo: fifo, files: files)
        case .commandFinished(let code):
            let duration = commandStartedAt.map { Date().timeIntervalSince($0) }
            if let cmd = runningCommand {
                lastCommand = cmd
                lastExitCode = code
                lastDuration = duration
                notifyIfLongCommand(cmd, code: code, duration: duration ?? 0)
            }
            runningCommand = nil
            commandStartedAt = nil
            if waitingForEditor {
                // The editor function returned without us (Ctrl-C); stop tracking its request.
                waitingForEditor = false
                workspace?.editorWaitEnded(self)
            }
            workspace?.sessionCommandFinished(self)
        }
    }

    func editorRequestFinished() {
        waitingForEditor = false
    }

    func sizeChanged(cols: Int, rows: Int) {
        if self.cols != cols { self.cols = cols }
        if self.rows != rows { self.rows = rows }
    }

    func didReceiveOutput() {
        if !isFocused && !hasUnseenActivity { hasUnseenActivity = true }
    }

    func didRingBell() {
        if !isFocused || !NSApp.isActive { bellPending = true }
    }

    func postNotification(title: String, body: String) {
        NotificationHelper.post(title: title, body: body)
    }

    func processExited(_ code: Int32?) {
        exited = true
        exitCode = code
        runningCommand = nil
        pollTimer?.invalidate()
        pollTimer = nil
        workspace?.sessionExited(self)
    }

    // MARK: Working directory tracking

    private func setCwd(_ path: String) {
        guard !path.isEmpty, path != cwd else { return }
        cwd = path
        workspace?.sessionCwdChanged(self)
    }

    private func schedulePolling() {
        pollTimer?.invalidate()
        guard !exited else { return }
        let interval: TimeInterval = isFocused ? (integrationActive ? 3 : 1) : 5
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        t.tolerance = interval * 0.2
        RunLoop.main.add(t, forMode: .common)
        pollTimer = t
        poll()
    }

    /// Polls the kernel for the shell's cwd and foreground job. Covers shells without integration,
    /// nested shells (bash inside zsh) and commands that change directory without a prompt.
    func poll() {
        guard view.isRunning else { return }
        let pid = shellPid, fd = view.ptyFD
        let fg = ProcessInspector.foregroundCommand(shellPid: pid, ptyMaster: fd)
        let fgName = fg.map { $0.name }
        if fgName != foregroundProcess { foregroundProcess = fgName }
        // OSC 7 is authoritative for a couple of seconds after it arrives (it keeps logical paths
        // like /tmp instead of /private/tmp).
        if let last = lastOSC7At, Date().timeIntervalSince(last) < 2.5, fg == nil { return }
        guard !isRemote else { return }
        let nestedShell = fg.map { ProcessInspector.knownShells.contains($0.name.trimmingCharacters(in: CharacterSet(charactersIn: "-"))) } ?? false
        // With integration active and no nested shell, only OSC 7 moves the cwd; polling would
        // replace logical paths with physical ones.
        if integrationActive && !nestedShell && fg == nil { return }
        if let dir = ProcessInspector.trackedDirectory(shellPid: pid, ptyMaster: fd) {
            if integrationActive && !nestedShell, Self.samePhysicalPath(dir, cwd) { return }
            setCwd(dir)
        }
    }

    private static func samePhysicalPath(_ a: String, _ b: String) -> Bool {
        (a as NSString).resolvingSymlinksInPath == (b as NSString).resolvingSymlinksInPath
    }

    private func notifyIfLongCommand(_ cmd: String, code: Int32, duration: TimeInterval) {
        let t = AppState.shared.settings.terminal
        guard t.notifyLongCommands, duration >= t.longCommandSeconds, !NSApp.isActive || !isFocused else { return }
        let status = code == 0 ? "✓ finished" : "✗ failed (exit \(code))"
        postNotification(title: "\(status) in \(Fmt.duration(duration))", body: cmd)
    }

    // MARK: Teardown

    /// Closes the PTY (the kernel sends SIGHUP) and SIGKILLs the shell if it is still alive after 3 s.
    func terminate() {
        launched = true // a pane closed before its shell started must never start it
        container.onFirstLayout = nil
        pollTimer?.invalidate()
        pollTimer = nil
        let pid = shellPid
        guard view.isRunning else { return }
        view.process.terminate()
        guard pid > 0 else { return }
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
            if kill(pid, 0) == 0 { kill(pid, SIGKILL) }
        }
    }
}
