import AppKit
import SwiftTerm
import SwiftUI
import TerminalusCore
import WebKit

/// Serves a panel's HTML from `terminalus-panel://<id>/`, which also gives each panel its own origin
/// (so localStorage persists per panel).
private final class PanelSchemeHandler: NSObject, WKURLSchemeHandler {
    var html: () -> String = { "" }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else { return }
        let data = Data(html().utf8)
        let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                   headerFields: ["Content-Type": "text/html; charset=utf-8", "Content-Length": "\(data.count)"])!
        task.didReceive(resp)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}

/// Breaks the retain cycle between WKUserContentController and the controller.
private final class WeakReplyHandler: NSObject, WKScriptMessageHandlerWithReply {
    weak var target: WebPanelController?
    init(_ t: WebPanelController) { target = t }

    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage,
                               replyHandler: @escaping @MainActor @Sendable (Any?, String?) -> Void) {
        MainActor.assumeIsolated {
            guard let target else { return replyHandler(nil, "Panel closed") }
            target.handle(message.body, reply: replyHandler)
        }
    }
}

/// A web panel: pasted HTML/CSS/JS running in a WKWebView with the `terminalus` JavaScript API.
@MainActor
final class WebPanelController: NSObject, WKNavigationDelegate {
    private(set) var panel: CustomPanel
    let webView: WKWebView
    let status = PanelStatus()
    weak var workspace: Workspace?
    private let scheme = PanelSchemeHandler()
    private var subscriptions = Set<String>()

    init(panel: CustomPanel, workspace: Workspace?) {
        self.panel = panel
        self.workspace = workspace
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(scheme, forURLScheme: "terminalus-panel")
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 280, height: 300), configuration: config)
        super.init()
        scheme.html = { [weak self] in self?.documentHTML() ?? "" }
        let ucc = config.userContentController
        ucc.addScriptMessageHandler(WeakReplyHandler(self), contentWorld: .page, name: "terminalus")
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsMagnification = false
        installBridge()
        load()
    }

    func update(_ p: CustomPanel) {
        let reload = p.code != panel.code
        panel = p
        if reload { load() } else { push(["panel": panelInfo]) }
    }

    func load() {
        status.error = nil
        installBridge()
        webView.load(URLRequest(url: URL(string: "terminalus-panel://\(panel.id.lowercased())/index.html")!))
    }

    /// The bridge script is regenerated on every load so it starts with the current state.
    private func installBridge() {
        let ucc = webView.configuration.userContentController
        ucc.removeAllUserScripts()
        ucc.addUserScript(WKUserScript(source: bridgeScript(), injectionTime: .atDocumentStart, forMainFrameOnly: true))
    }

    private func documentHTML() -> String {
        let code = panel.code
        if code.range(of: "<html", options: .caseInsensitive) != nil { return code }
        return """
        <!doctype html>
        <html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"></head>
        <body>
        \(code)
        </body></html>
        """
    }

    // MARK: State pushed to the page

    private var panelInfo: [String: Any] { ["id": panel.id, "name": panel.name, "allowCommands": panel.allowCommands] }

    func state(includeStats: Bool) -> [String: Any] {
        var s: [String: Any] = [
            "cwd": workspace?.focusedSession?.cwd ?? NSHomeDirectory(),
            "theme": PanelBridgeData.theme(AppState.shared.uiTheme, AppState.shared.settings),
            "panel": panelInfo,
            "git": PanelBridgeData.git(workspace?.tree.gitStatus),
        ]
        if includeStats { s["stats"] = PanelBridgeData.stats(AppState.shared.stats.snapshot) }
        return s
    }

    func push(_ partial: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: partial), let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.terminalus && window.terminalus.__update(\(json))", completionHandler: nil)
    }

    func cwdChanged() {
        push(["cwd": workspace?.focusedSession?.cwd ?? NSHomeDirectory(), "git": PanelBridgeData.git(workspace?.tree.gitStatus)])
    }

    func gitChanged() { push(["git": PanelBridgeData.git(workspace?.tree.gitStatus)]) }
    func themeChanged() { push(["theme": PanelBridgeData.theme(AppState.shared.uiTheme, AppState.shared.settings)]) }

    func statsTick() {
        guard subscriptions.contains("stats") else { return }
        push(["stats": PanelBridgeData.stats(AppState.shared.stats.snapshot)])
    }

    // MARK: Messages from the page

    func handle(_ body: Any, reply: @escaping @MainActor @Sendable (Any?, String?) -> Void) {
        guard let dict = body as? [String: Any], let method = dict["method"] as? String else { return reply(nil, "Malformed message") }
        let args = dict["args"] as? [String: Any] ?? [:]
        let session = workspace?.focusedSession
        switch method {
        case "subscribe":
            if let e = args["event"] as? String { subscriptions.insert(e) }
            reply(true, nil)
        case "run":
            guard panel.allowCommands else {
                let msg = "This panel isn't allowed to run commands. Enable it in the panel menu → Edit Code…"
                status.error = msg
                return reply(nil, msg)
            }
            guard let cmd = args["command"] as? String, !cmd.isEmpty else { return reply(nil, "run() needs a command string") }
            let cwd = (args["cwd"] as? String).map { ($0 as NSString).expandingTildeInPath } ?? session?.cwd ?? NSHomeDirectory()
            let timeout = (args["timeout"] as? NSNumber)?.doubleValue ?? 30
            PanelCommandRunner.run(cmd, cwd: cwd, path: session?.shellPATH, timeout: timeout) { r in
                DispatchQueue.main.async {
                    reply(["stdout": r.stdout, "stderr": r.stderr, "code": Int(r.code), "timedOut": r.timedOut], nil)
                }
            }
        case "send":
            guard panel.allowCommands else { return reply(nil, "This panel isn't allowed to type into the terminal.") }
            session?.send((args["text"] as? String) ?? "")
            reply(true, nil)
        case "cd":
            guard let p = args["path"] as? String else { return reply(nil, "cd() needs a path") }
            session?.cd((p as NSString).expandingTildeInPath)
            reply(true, nil)
        case "open":
            guard let t = args["target"] as? String else { return reply(nil, "open() needs a URL or path") }
            if let u = URL(string: t), let scheme = u.scheme, ["http", "https", "mailto"].contains(scheme) {
                NSWorkspace.shared.open(u)
            } else {
                let path = (t as NSString).expandingTildeInPath
                let abs = path.hasPrefix("/") ? path : ((session?.cwd ?? NSHomeDirectory()) as NSString).appendingPathComponent(path)
                NSWorkspace.shared.open(URL(fileURLWithPath: abs))
            }
            reply(true, nil)
        case "notify":
            NotificationHelper.post(title: (args["title"] as? String) ?? panel.name, body: (args["body"] as? String) ?? "")
            reply(true, nil)
        case "state":
            reply(state(includeStats: true), nil)
        case "error":
            status.error = (args["message"] as? String) ?? "Script error"
            reply(nil, nil)
        default:
            reply(nil, "Unknown method \(method)")
        }
    }

    // MARK: Navigation: links open in the browser, the panel itself never navigates away.

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { return decisionHandler(.cancel) }
        if url.scheme == "terminalus-panel" || url.scheme == "about" || url.scheme == "data" || url.scheme == "blob" {
            return decisionHandler(.allow)
        }
        if action.targetFrame?.isMainFrame == false { return decisionHandler(.allow) }
        NSWorkspace.shared.open(url)
        decisionHandler(.cancel)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        status.error = error.localizedDescription
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        status.error = "The panel crashed — reloaded."
        load()
    }

    // MARK: Bridge

    private func bridgeScript() -> String {
        let stateJSON = (try? JSONSerialization.data(withJSONObject: state(includeStats: true)))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        let cssJSON = (try? JSONSerialization.data(withJSONObject: [PanelBridgeData.baseCSS], options: [.fragmentsAllowed]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[\"\"]"
        return """
        (function () {
          if (window.terminalus) return;
          const handler = window.webkit.messageHandlers.terminalus;
          const state = \(stateJSON);
          const listeners = {};
          function applyTheme(t) {
            if (!t || !t.css) return;
            const r = document.documentElement.style;
            for (const k in t.css) r.setProperty(k, t.css[k]);
            document.documentElement.dataset.theme = t.dark ? 'dark' : 'light';
          }
          function call(method, args) { return handler.postMessage({ method: method, args: args || {} }); }
          function emit(k, v) { (listeners[k] || []).forEach(function (cb) { try { cb(v); } catch (e) { console.error(e); } }); }
          window.terminalus = {
            version: 1,
            get cwd() { return state.cwd; },
            get theme() { return state.theme; },
            get stats() { return state.stats; },
            get git() { return state.git; },
            get panel() { return state.panel; },
            on: function (event, cb) {
              (listeners[event] = listeners[event] || []).push(cb);
              if (event === 'stats') call('subscribe', { event: 'stats' });
              if (state[event] !== undefined && state[event] !== null) { try { cb(state[event]); } catch (e) { console.error(e); } }
              return function () { listeners[event] = (listeners[event] || []).filter(function (f) { return f !== cb; }); };
            },
            run: function (command, options) { return call('run', Object.assign({ command: command }, options || {})); },
            send: function (text) { return call('send', { text: text }); },
            cd: function (path) { return call('cd', { path: path }); },
            open: function (target) { return call('open', { target: target }); },
            notify: function (title, body) { return call('notify', { title: title, body: body || '' }); },
            __update: function (partial) {
              for (const k in partial) { state[k] = partial[k]; if (k === 'theme') applyTheme(partial[k]); emit(k, partial[k]); }
            }
          };
          const style = document.createElement('style');
          style.id = 'terminalus-base';
          style.textContent = \(cssJSON)[0];
          (document.head || document.documentElement).prepend(style);
          applyTheme(state.theme);
          window.addEventListener('error', function (e) { call('error', { message: String(e.message || e) }); });
          window.addEventListener('unhandledrejection', function (e) {
            call('error', { message: String((e.reason && e.reason.message) || e.reason) });
          });
        })();
        """
    }
}

/// JSON shapes handed to panels.
enum PanelBridgeData {
    static let baseCSS = """
    :where(html, body) { margin: 0; padding: 0; background: transparent; color: var(--fg);
      font: 12px/1.45 var(--font-ui); -webkit-font-smoothing: antialiased; }
    :where(body) { padding: 10px 12px; }
    :where(code, pre, kbd, samp) { font-family: var(--font-mono); }
    :where(a) { color: var(--accent); }
    :where(button) { font: inherit; color: var(--fg); background: var(--panel); border: 1px solid var(--border);
      border-radius: 5px; padding: 3px 9px; }
    :where(button:hover) { border-color: var(--muted); }
    :where(input, textarea, select) { font: inherit; color: var(--fg); background: var(--panel);
      border: 1px solid var(--border); border-radius: 5px; padding: 4px 6px; outline: none; }
    :where(input:focus, textarea:focus) { border-color: var(--accent); }
    ::-webkit-scrollbar { width: 8px; height: 8px; }
    ::-webkit-scrollbar-thumb { background: var(--border); border-radius: 4px; }
    """

    @MainActor
    static func theme(_ t: ResolvedTheme, _ s: AppSettings) -> [String: Any] {
        var css: [String: String] = [
            "--bg": t.background.hex, "--fg": t.foreground.hex, "--accent": t.accent.hex, "--accent2": t.accent2.hex,
            "--muted": t.secondaryText.hex, "--border": t.border.hex, "--panel": t.panelBackground.hex,
            "--sidebar": t.sidebarBackground.hex, "--success": t.success.hex, "--warning": t.warning.hex, "--danger": t.danger.hex,
            "--font-ui": "-apple-system, system-ui, sans-serif",
            "--font-mono": (s.terminal.font.family.isEmpty ? "ui-monospace, SF Mono" : "'\(s.terminal.font.family)', ui-monospace") + ", Menlo, monospace",
        ]
        for (i, c) in t.ansi.enumerated() { css["--ansi-\(i)"] = c.hex }
        return ["name": t.name, "dark": t.isDark, "css": css,
                "colors": ["background": t.background.hex, "foreground": t.foreground.hex, "accent": t.accent.hex,
                           "accent2": t.accent2.hex, "muted": t.secondaryText.hex, "ansi": t.ansi.map(\.hex)]]
    }

    static func git(_ g: GitStatus?) -> Any {
        guard let g else { return NSNull() }
        return ["root": g.root, "branch": g.branch ?? "", "ahead": g.ahead, "behind": g.behind, "dirty": g.isDirty,
                "staged": g.stagedCount, "unstaged": g.unstagedCount, "untracked": g.untrackedCount]
    }

    static func stats(_ s: SystemSnapshot) -> [String: Any] {
        var d: [String: Any] = [
            "uptime": s.info.uptime, "load": s.info.loadAverage, "thermal": s.info.thermal.rawValue,
            "model": s.info.modelName, "chip": s.info.chip, "processCount": s.info.processCount,
        ]
        if let c = s.cpu { d["cpu"] = ["total": c.total, "user": c.user, "system": c.system, "cores": c.perCore] }
        if let m = s.memory { d["memory"] = ["used": m.used, "total": m.total, "app": m.app, "wired": m.wired, "compressed": m.compressed, "pressure": m.pressure.rawValue] }
        if let g = s.gpu { d["gpu"] = ["utilization": g.utilization, "memoryUsed": g.memoryUsed, "name": g.name] }
        if let n = s.network { d["network"] = ["down": n.downRate, "up": n.upRate, "ip": n.localIPv4 ?? ""] }
        if let k = s.disk {
            d["disk"] = ["read": k.readRate, "write": k.writeRate,
                         "volumes": k.volumes.map { ["name": $0.name, "path": $0.path, "total": $0.total, "available": $0.available] }]
        }
        if let p = s.processes { d["processes"] = p.map { ["pid": Int($0.pid), "name": $0.name, "cpu": $0.cpu, "memory": $0.memory] } }
        if let b = s.battery { d["battery"] = ["percent": b.percent, "charging": b.isCharging] }
        return d
    }
}

/// A command panel: runs a shell command on an interval and shows its colored output.
@MainActor
final class CommandPanelController: NSObject {
    private(set) var panel: CustomPanel
    let terminal: TerminalView
    let status = PanelStatus()
    weak var workspace: Workspace?
    private var timer: Timer?
    private var lastCwd: String?
    private var appliedTheme: String?

    init(panel: CustomPanel, workspace: Workspace?) {
        self.panel = panel
        self.workspace = workspace
        terminal = TerminalView(frame: NSRect(x: 0, y: 0, width: 280, height: 200))
        super.init()
        terminal.allowMouseReporting = false
        applyTheme()
        schedule()
        DispatchQueue.main.async { [weak self] in self?.runNow() }
    }

    func update(_ p: CustomPanel) {
        let changed = p.code != panel.code || p.refreshSeconds != panel.refreshSeconds || p.followCwd != panel.followCwd
        panel = p
        if changed {
            schedule()
            runNow()
        }
    }

    func applyTheme() {
        let t = AppState.shared.uiTheme
        let s = AppState.shared.settings
        let key = t.id + t.accent.hex + s.terminal.font.family + "\(s.terminal.font.size)"
        guard key != appliedTheme else { return }
        appliedTheme = key
        terminal.font = FontResolver.terminalFont(family: s.terminal.font.family, size: max(9, s.terminal.font.size - 2), weight: s.terminal.font.weight)
        terminal.installColors(t.ansi.map(\.stColor))
        terminal.nativeForegroundColor = t.foreground.nsColor
        terminal.nativeBackgroundColor = t.sidebarBackground.nsColor
        terminal.backgroundOpacity = 0
        terminal.caretColor = .clear
        terminal.getTerminal().setCursorStyle(.steadyBar)
    }

    private func schedule() {
        timer?.invalidate()
        timer = nil
        guard panel.refreshSeconds > 0 else { return }
        let t = Timer(timeInterval: max(1, panel.refreshSeconds), repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        t.tolerance = 0.5
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        // Don't burn CPU for windows nobody can see.
        guard let w = workspace?.window, w.occlusionState.contains(.visible), !w.isMiniaturized else { return }
        runNow()
    }

    func cwdChanged() {
        guard panel.followCwd, let c = workspace?.focusedSession?.cwd, c != lastCwd else { return }
        runNow()
    }

    func runNow() {
        guard !status.running else { return }
        status.running = true
        let cwd = panel.followCwd ? (workspace?.focusedSession?.cwd ?? NSHomeDirectory()) : NSHomeDirectory()
        lastCwd = cwd
        let cols = max(20, terminal.getTerminal().cols)
        let started = Date()
        PanelCommandRunner.run(panel.code, cwd: cwd, path: workspace?.focusedSession?.shellPATH, columns: cols, timeout: 30) { [weak self] r in
            DispatchQueue.main.async {
                guard let self else { return }
                self.status.running = false
                self.status.lastRun = Date()
                self.status.lastExit = r.code
                self.status.detail = String(format: "%.1fs", Date().timeIntervalSince(started))
                self.status.error = r.timedOut ? "Timed out" : (r.code != 0 && r.stdout.isEmpty ? "Exit \(r.code)" : nil)
                var out = r.stdout
                if !r.stderr.isEmpty && (r.code != 0 || out.isEmpty) { out += (out.isEmpty ? "" : "\n") + "\u{1b}[2m" + r.stderr + "\u{1b}[0m" }
                if out.isEmpty { out = "\u{1b}[2m(no output)\u{1b}[0m" }
                self.terminal.feed(text: "\u{1b}[0m\u{1b}[H\u{1b}[2J\u{1b}[3J" + out.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\n", with: "\r\n"))
                self.terminal.scrollTo(row: 0)
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}

/// Re-parents a controller-owned NSView into SwiftUI.
struct ReparentingHost: NSViewRepresentable {
    let content: NSView

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        v.wantsLayer = true
        return v
    }

    func updateNSView(_ host: NSView, context: Context) {
        guard content.superview !== host else { return }
        host.subviews.forEach { $0.removeFromSuperview() }
        content.removeFromSuperview()
        content.frame = host.bounds.insetBy(dx: 0, dy: 0)
        content.autoresizingMask = [.width, .height]
        host.addSubview(content)
    }
}

struct CustomPanelContent: View {
    @Environment(\.ui) private var ui
    let panel: CustomPanel
    let workspace: Workspace

    var body: some View {
        switch panel.kind {
        case .web:
            ReparentingHost(content: workspace.webController(for: panel).webView)
        case .command:
            ReparentingHost(content: workspace.commandController(for: panel).terminal)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
        }
    }
}
