import AppKit
import SwiftUI
import TerminalusCore

struct PanelTemplate: Identifiable {
    let id: String
    let name: String
    let summary: String
    let code: String
}

enum PanelTemplates {
    static let all: [PanelTemplate] = [
        PanelTemplate(id: "gitlog", name: "Git log", summary: "Command · recent commits of the current repo",
                      code: #"{"name": "Git log", "command": "git log --graph --oneline --decorate --color=always -30 2>/dev/null || echo 'not a git repository'", "refresh": 10}"#),
        PanelTemplate(id: "gitstatus", name: "Git status", summary: "Command · short status, refreshed every 5 s",
                      code: #"{"name": "Changes", "command": "git -c color.status=always status -sb 2>/dev/null || echo 'not a git repository'", "refresh": 5}"#),
        PanelTemplate(id: "docker", name: "Docker containers", summary: "Command · running containers",
                      code: #"{"name": "Containers", "command": "docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' 2>&1", "refresh": 5}"#),
        PanelTemplate(id: "ports", name: "Listening ports", summary: "Command · who is listening on which port",
                      code: #"{"name": "Ports", "command": "lsof -nP -iTCP -sTCP:LISTEN | awk 'NR>1 {print $9, $1}' | sort -u", "refresh": 15}"#),
        PanelTemplate(id: "notes", name: "Scratch notes", summary: "Web · a notepad saved per panel", code: """
        <title>Notes</title>
        <style>
          body { padding: 0; height: 100vh; }
          textarea { width: 100%; height: 100%; box-sizing: border-box; border: 0; border-radius: 0;
                     background: transparent; resize: none; padding: 10px 12px; font: 12px/1.5 var(--font-mono); }
        </style>
        <textarea id="n" placeholder="Notes…" spellcheck="false"></textarea>
        <script>
          const n = document.getElementById('n');
          n.value = localStorage.getItem('notes') || '';
          n.addEventListener('input', () => localStorage.setItem('notes', n.value));
        </script>
        """),
        PanelTemplate(id: "quick", name: "Quick commands", summary: "Web · buttons that type commands (needs command access)", code: """
        <title>Quick commands</title>
        <style>
          .grid { display: grid; grid-template-columns: 1fr 1fr; gap: 6px; }
          button { text-align: left; font-family: var(--font-mono); font-size: 11px; }
          p { color: var(--muted); margin: 0 0 8px; }
        </style>
        <p id="cwd"></p>
        <div class="grid" id="g"></div>
        <script>
          const cmds = ['git status', 'git pull', 'ls -la', 'make', 'npm test', 'clear'];
          const g = document.getElementById('g');
          for (const c of cmds) {
            const b = document.createElement('button');
            b.textContent = c;
            b.onclick = () => terminalus.send(c + '\\r');
            g.appendChild(b);
          }
          terminalus.on('cwd', d => document.getElementById('cwd').textContent = d);
        </script>
        """),
        PanelTemplate(id: "cpu", name: "CPU graph", summary: "Web · live per-core bars from terminalus.on('stats')", code: """
        <title>Cores</title>
        <style>
          #bars { display: flex; gap: 3px; align-items: flex-end; height: 70px; }
          .b { flex: 1; background: var(--accent); border-radius: 2px; min-height: 1px; transition: height .4s; }
          .t { color: var(--muted); margin-top: 6px; font-family: var(--font-mono); font-size: 11px; }
        </style>
        <div id="bars"></div><div class="t" id="t"></div>
        <script>
          terminalus.on('stats', s => {
            if (!s.cpu) return;
            const bars = document.getElementById('bars');
            bars.innerHTML = s.cpu.cores.map(v => `<div class="b" style="height:${Math.max(1, v * 100)}%"></div>`).join('');
            document.getElementById('t').textContent = `total ${(s.cpu.total * 100).toFixed(0)}% · load ${s.load[0].toFixed(2)}`;
          });
        </script>
        """),
        PanelTemplate(id: "timer", name: "Focus timer", summary: "Web · a 25-minute timer with a notification", code: """
        <title>Timer</title>
        <style>
          #t { font: 300 34px var(--font-mono); letter-spacing: 1px; }
          .row { display: flex; gap: 6px; margin-top: 8px; }
        </style>
        <div id="t">25:00</div>
        <div class="row"><button id="s">Start</button><button id="r">Reset</button></div>
        <script>
          let left = 1500, timer = null;
          const t = document.getElementById('t'), s = document.getElementById('s');
          const draw = () => t.textContent = `${String(Math.floor(left / 60)).padStart(2, '0')}:${String(left % 60).padStart(2, '0')}`;
          s.onclick = () => {
            if (timer) { clearInterval(timer); timer = null; s.textContent = 'Start'; return; }
            s.textContent = 'Pause';
            timer = setInterval(() => {
              left--; draw();
              if (left <= 0) { clearInterval(timer); timer = null; s.textContent = 'Start'; left = 1500; draw(); terminalus.notify('Time is up', 'Take a break.'); }
            }, 1000);
          };
          document.getElementById('r').onclick = () => { left = 1500; draw(); };
        </script>
        """),
    ]
}

/// Paste code → preview → add as a side panel. Also used to edit an existing panel.
struct PanelImportView: View {
    let editing: CustomPanel?
    let onDone: () -> Void

    @State private var code: String
    @State private var name: String
    @State private var kind: CustomPanel.Kind
    @State private var side: DockSide
    @State private var allowCommands: Bool
    @State private var refresh: Double
    @State private var followCwd: Bool
    @State private var detectedName: String?
    @State private var preview: CustomPanel?
    @State private var previewTask: DispatchWorkItem?
    @State private var showAPI = false

    init(editing: CustomPanel?, side: DockSide, onDone: @escaping () -> Void) {
        self.editing = editing
        self.onDone = onDone
        _code = State(initialValue: editing?.code ?? "")
        _name = State(initialValue: editing?.name ?? "")
        _kind = State(initialValue: editing?.kind ?? .web)
        _side = State(initialValue: side)
        _allowCommands = State(initialValue: editing?.allowCommands ?? false)
        _refresh = State(initialValue: editing?.refreshSeconds ?? 5)
        _followCwd = State(initialValue: editing?.followCwd ?? true)
        _preview = State(initialValue: editing)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(editing == nil ? "Import Window Code" : "Edit \(editing!.name)").font(.title3.weight(.semibold))
                Spacer()
                Menu("Templates") {
                    ForEach(PanelTemplates.all) { t in
                        Button("\(t.name) — \(t.summary)") { code = t.code; codeChanged() }
                    }
                }
                .fixedSize()
            }
            Text("Paste HTML/CSS/JavaScript (code in ``` fences is fine), a JSON manifest, or a shell command. It becomes a panel in the left or right side of the window.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextEditor(text: $code)
                .font(.system(size: 12, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.secondary.opacity(0.25)))
                .frame(minHeight: 180)
                .onChange(of: code) { _, _ in codeChanged() }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text("Type").foregroundStyle(.secondary)
                    Picker("", selection: $kind) {
                        Text("Web (HTML/JS)").tag(CustomPanel.Kind.web)
                        Text("Command output").tag(CustomPanel.Kind.command)
                    }
                    .labelsHidden().pickerStyle(.segmented).frame(width: 280)
                    .onChange(of: kind) { _, _ in schedulePreview() }
                }
                GridRow {
                    Text("Name").foregroundStyle(.secondary)
                    TextField(detectedName ?? "Panel name", text: $name).frame(width: 280)
                }
                GridRow {
                    Text("Side").foregroundStyle(.secondary)
                    Picker("", selection: $side) {
                        Text("Left").tag(DockSide.left)
                        Text("Right").tag(DockSide.right)
                    }
                    .labelsHidden().pickerStyle(.segmented).frame(width: 160)
                }
                if kind == .web {
                    GridRow {
                        Text("Access").foregroundStyle(.secondary)
                        Toggle("Allow this panel to run shell commands and type into the terminal", isOn: $allowCommands)
                    }
                } else {
                    GridRow {
                        Text("Refresh").foregroundStyle(.secondary)
                        HStack {
                            Stepper(refresh == 0 ? "Only on directory change" : "Every \(Int(refresh)) s", value: $refresh, in: 0...3600, step: 1)
                            Toggle("Run in the terminal's current directory", isOn: $followCwd)
                        }
                    }
                }
            }

            GroupBox {
                ZStack {
                    if let preview, !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        PanelPreview(panel: preview).id(preview.code + preview.kind.rawValue)
                    } else {
                        Text("Preview").foregroundStyle(.secondary)
                    }
                }
                .frame(height: 170)
                .frame(maxWidth: .infinity)
            } label: {
                Text("Preview").font(.caption).foregroundStyle(.secondary)
            }

            DisclosureGroup("JavaScript API", isExpanded: $showAPI) {
                Text("""
                terminalus.cwd · .theme · .stats · .git — current values
                terminalus.on('cwd' | 'stats' | 'theme' | 'git', callback)
                terminalus.run(cmd) → Promise<{stdout, stderr, code}>   (needs access)
                terminalus.send(text) — types into the terminal          (needs access)
                terminalus.cd(path) · .open(urlOrPath) · .notify(title, body)
                CSS variables: --bg --fg --accent --accent2 --muted --border --panel --font-ui --font-mono --ansi-0…15
                localStorage is kept per panel.
                """)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { onDone() }.keyboardShortcut(.cancelAction)
                Button(editing == nil ? "Add Panel" : "Save") { commit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(18)
        .frame(minWidth: 620, minHeight: 640)
    }

    private func codeChanged() {
        let parsed = PanelCodeParser.parse(code)
        kind = parsed.kind
        detectedName = parsed.name
        if let s = parsed.side { side = s }
        if let r = parsed.refreshSeconds { refresh = r }
        if let a = parsed.allowCommands { allowCommands = a }
        schedulePreview()
    }

    private func schedulePreview() {
        previewTask?.cancel()
        let work = DispatchWorkItem { preview = buildPanel(id: "preview") }
        previewTask = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func buildPanel(id: String) -> CustomPanel {
        let parsed = PanelCodeParser.parse(code)
        let finalName = name.trimmingCharacters(in: .whitespaces).isEmpty ? (detectedName ?? (kind == .web ? "Panel" : "Command")) : name
        var p = CustomPanel(id: id, name: finalName, kind: kind,
                            code: parsed.kind == kind ? parsed.code : PanelCodeParser.stripFences(code).trimmingCharacters(in: .whitespacesAndNewlines))
        p.allowCommands = allowCommands
        p.refreshSeconds = refresh
        p.followCwd = followCwd
        if let e = editing { p.createdAt = e.createdAt }
        return p
    }

    private func commit() {
        let app = AppState.shared
        let p = buildPanel(id: editing?.id ?? UUID().uuidString.lowercased())
        app.panels.save(p)
        app.panelChanged(p)
        let pid = PanelID.custom(p.id)
        if editing == nil || app.settings.layout.side(of: pid) != side {
            app.settingsStore.update { $0.layout.move(pid, to: side) }
        }
        onDone()
    }
}

/// A throwaway panel instance for the import preview.
private struct PanelPreview: View {
    let panel: CustomPanel
    @State private var web: WebPanelController?
    @State private var command: CommandPanelController?

    var body: some View {
        Group {
            if let web {
                ReparentingHost(content: web.webView)
            } else if let command {
                ReparentingHost(content: command.terminal)
            } else {
                Color.clear
            }
        }
        .onAppear {
            let ws = AppState.shared.activeWorkspace
            switch panel.kind {
            case .web: web = WebPanelController(panel: panel, workspace: ws)
            case .command: command = CommandPanelController(panel: panel, workspace: ws)
            }
        }
        .onDisappear { command?.stop() }
    }
}

@MainActor
final class PanelImportWindowController: NSWindowController, NSWindowDelegate {
    static var current: PanelImportWindowController?

    static func show(editing: CustomPanel? = nil, side: DockSide = .right) {
        current?.close()
        let wc = PanelImportWindowController(editing: editing, side: side)
        current = wc
        wc.showWindow(nil)
        wc.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    init(editing: CustomPanel?, side: DockSide) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 720),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = editing == nil ? "Import Window Code" : "Edit Panel"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        let host = NSHostingView(rootView: PanelImportView(editing: editing, side: side) { [weak self] in self?.close() })
        host.sizingOptions = []
        window.contentView = host
        window.center()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func windowWillClose(_ notification: Notification) {
        if PanelImportWindowController.current === self { PanelImportWindowController.current = nil }
    }
}
