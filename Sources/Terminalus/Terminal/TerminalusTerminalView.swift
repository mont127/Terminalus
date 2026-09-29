import AppKit
import SwiftTerm
import TerminalusCore

/// SwiftTerm's TerminalView hosting a local shell. Subclasses TerminalView directly (rather than
/// LocalProcessTerminalView) so bell, clipboard and link handling can be customized.
final class TerminalusTerminalView: TerminalView, TerminalViewDelegate, LocalProcessDelegate {
    private(set) var process: LocalProcess!
    weak var session: TerminalSession?

    var copyOnSelect = false
    var bellMode: BellMode = .visual {
        didSet {
            switch bellMode {
            case .none: bellStyle = .none
            case .sound: bellStyle = .sound
            case .visual, .notification: bellStyle = .visual
            case .soundAndVisual: bellStyle = .soundAndVisual
            }
        }
    }
    var bellSoundName = "Tink"

    init(frame: CGRect, options: TerminalOptions) {
        super.init(frame: frame, font: nil, options: options)
        terminalDelegate = self
        process = LocalProcess(delegate: self)
        registerForDraggedTypes([.fileURL, .URL, .string])

        let term = getTerminal()
        term.registerOscHandler(code: ShellIntegration.oscCode) { [weak self] data in
            let payload = String(decoding: data, as: UTF8.self)
            self?.session?.handleIntegration(payload)
        }
        // OSC 777;notify;title;body (urxvt / many CLIs) and OSC 9;message (iTerm2 growl).
        term.registerOscHandler(code: 777) { [weak self] data in
            let parts = String(decoding: data, as: UTF8.self).split(separator: ";", maxSplits: 2).map(String.init)
            guard parts.first == "notify" else { return }
            self?.session?.postNotification(title: parts.count > 1 ? parts[1] : "Terminalus", body: parts.count > 2 ? parts[2] : "")
        }
        term.registerOscHandler(code: 9) { [weak self] data in
            let s = String(decoding: data, as: UTF8.self)
            // OSC 9;4;… is ConEmu progress reporting, not a notification.
            guard !s.hasPrefix("4;"), !s.isEmpty else { return }
            self?.session?.postNotification(title: "Terminalus", body: s)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func start(_ spec: ShellLaunchSpec) {
        process.startProcess(executable: spec.executable, args: spec.args, environment: spec.environment,
                             execName: spec.execName, currentDirectory: spec.currentDirectory)
    }

    var isRunning: Bool { process?.running ?? false }
    var shellPid: pid_t { process?.shellPid ?? 0 }
    var ptyFD: Int32 { process?.childfd ?? -1 }

    // MARK: Bell & selection

    override func bell(source: Terminal) {
        session?.didRingBell()
        if bellMode == .notification, !NSApp.isActive {
            session?.postNotification(title: "Bell", body: session?.displayTitle ?? "Terminalus")
            return
        }
        super.bell(source: source)
    }

    override func selectionChanged(source: Terminal) {
        super.selectionChanged(source: source)
        guard copyOnSelect, let text = getSelection(), !text.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    // MARK: Drag & drop — dropping files inserts their shell-escaped paths.

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pb = sender.draggingPasteboard
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            send(txt: urls.map { ShellLauncher.shellEscape($0.path) }.joined(separator: " ") + " ")
            window?.makeFirstResponder(self)
            return true
        }
        if let s = pb.string(forType: .string) {
            send(txt: s)
            window?.makeFirstResponder(self)
            return true
        }
        return false
    }

    // MARK: TerminalViewDelegate

    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        session?.sizeChanged(cols: newCols, rows: newRows)
        guard process.running else { return }
        var size = getWindowSize()
        _ = PseudoTerminalHelpers.setWinSize(masterPtyDescriptor: process.childfd, windowSize: &size)
    }

    func setTerminalTitle(source: TerminalView, title: String) {
        session?.terminalTitle = title
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        guard let directory else { return }
        session?.handleOSC7(directory)
    }

    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        process.send(data: data)
    }

    func scrolled(source: TerminalView, position: Double) {}
    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}

    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        if let url = URL(string: link), url.scheme != nil {
            NSWorkspace.shared.open(url)
        } else {
            let path = (link as NSString).expandingTildeInPath
            let abs = path.hasPrefix("/") ? path : ((session?.cwd ?? NSHomeDirectory()) as NSString).appendingPathComponent(path)
            NSWorkspace.shared.open(URL(fileURLWithPath: abs))
        }
    }

    func bell(source: TerminalView) {
        if let s = NSSound(named: NSSound.Name(bellSoundName)) {
            s.stop()
            s.play()
        } else {
            NSSound.beep()
        }
    }

    func clipboardCopy(source: TerminalView, content: Data) {
        guard let str = String(data: content, encoding: .utf8) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([str as NSString])
    }

    func clipboardRead(source: TerminalView) -> Data? {
        NSPasteboard.general.string(forType: .string)?.data(using: .utf8)
    }

    func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}

    // MARK: LocalProcessDelegate

    func processTerminated(_ source: LocalProcess, exitCode: Int32?) {
        session?.processExited(exitCode)
    }

    func dataReceived(slice: ArraySlice<UInt8>) {
        feed(byteArray: slice)
        session?.didReceiveOutput()
    }

    func getWindowSize() -> winsize {
        let t = getTerminal()
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let w = Int(bounds.width * scale), h = Int(bounds.height * scale)
        return winsize(ws_row: UInt16(max(1, t.rows)), ws_col: UInt16(max(1, t.cols)),
                       ws_xpixel: UInt16(clamping: w), ws_ypixel: UInt16(clamping: h))
    }
}
