import AppKit
import SwiftUI
import TerminalusCore

/// Hosts the active document's scroll view (re-parented, never recreated).
struct CodeEditorHost: NSViewRepresentable {
    let document: EditorDocument
    let settings: EditorSettings
    let terminal: TerminalSettings
    let theme: ResolvedTheme

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        v.wantsLayer = true
        return v
    }

    func updateNSView(_ host: NSView, context: Context) {
        let sv = document.controller.scrollView
        document.controller.apply(settings: settings, terminal: terminal, theme: theme)
        if sv.superview !== host {
            host.subviews.forEach { $0.removeFromSuperview() }
            sv.removeFromSuperview()
            sv.frame = host.bounds
            sv.autoresizingMask = [.width, .height]
            host.addSubview(sv)
        }
    }
}

/// Editor tabs + code + status line.
struct EditorArea: View {
    @Environment(\.ui) private var ui
    let editor: EditorSession
    let workspace: Workspace

    var body: some View {
        let s = AppState.shared.settings
        VStack(spacing: 0) {
            EditorTabBar(editor: editor)
            Rectangle().fill(ui.hairline).frame(height: 1)
            if let msg = editor.message {
                notice(msg, actions: [("Dismiss", { editor.message = nil })])
            }
            if let doc = editor.active {
                if doc.externalChange {
                    notice("\(doc.name) changed on disk.", actions: [("Reload", { doc.reloadFromDisk() }), ("Keep Mine", { doc.externalChange = false })])
                }
                CodeEditorHost(document: doc, settings: s.editor, terminal: s.terminal, theme: AppState.shared.uiTheme)
                    .id(doc.id)
                EditorStatusLine(editor: editor, document: doc)
            } else {
                Spacer()
            }
        }
    }

    private func notice(_ text: String, actions: [(String, () -> Void)]) -> some View {
        HStack(spacing: 10) {
            Text(text).font(ui.font(-1))
            Spacer()
            ForEach(Array(actions.enumerated()), id: \.offset) { _, a in
                Button(a.0, action: a.1).controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(ui.theme.warning.withAlpha(0.12).color)
    }
}

private struct EditorTabBar: View {
    @Environment(\.ui) private var ui
    let editor: EditorSession

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(editor.documents) { doc in
                        EditorTab(editor: editor, doc: doc, active: doc.id == editor.active?.id)
                    }
                }
            }
            Spacer(minLength: 8)
            if let doc = editor.active {
                if let req = editor.requestFor(doc), !doc.isDirty {
                    Button("Open in \(req.command)") { editor.fallBack(doc) }
                        .buttonStyle(.plain)
                        .font(ui.font(-1))
                        .foregroundStyle(ui.secondary)
                        .help("Close it here and run the real \(req.command) in the terminal")
                        .padding(.trailing, 12)
                }
                if doc.url.map({ AppState.shared.settings.editor.runCommands[$0.pathExtension.lowercased()] != nil }) ?? false {
                    HeaderIconButton(symbol: "play.fill", help: "Run (⌘R)") { editor.runActive() }
                }
            }
            HeaderIconButton(symbol: "xmark", help: "Close the editor (⇧⌘I)") {
                _ = editor.closeAll()
            }
            .padding(.trailing, 8)
        }
        .frame(height: 30)
    }
}

private struct EditorTab: View {
    @Environment(\.ui) private var ui
    let editor: EditorSession
    let doc: EditorDocument
    let active: Bool
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            Text(doc.name)
                .font(ui.font(-1, weight: active ? .medium : .regular))
                .foregroundStyle(active ? ui.text : ui.secondary)
                .lineLimit(1)
            ZStack {
                if doc.isDirty && !hovering {
                    Circle().fill(ui.text.opacity(0.7)).frame(width: 6, height: 6)
                } else {
                    Button { editor.close(doc) } label: {
                        Image(systemName: "xmark").font(.system(size: 8, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(ui.secondary)
                    .opacity(hovering || active ? 1 : 0)
                }
            }
            .frame(width: 12)
        }
        .padding(.horizontal, 12)
        .frame(maxHeight: .infinity)
        .background(active ? ui.theme.background.withAlpha(0.35).color : Color.clear)
        .overlay(alignment: .bottom) {
            Rectangle().fill(active ? ui.accent : .clear).frame(height: 1.5)
        }
        .overlay(alignment: .trailing) { Rectangle().fill(ui.hairline).frame(width: 1) }
        .contentShape(Rectangle())
        .onTapGesture { editor.activate(doc) }
        .onHover { hovering = $0 }
        .help(doc.path ?? "Not saved yet")
        .contextMenu {
            Button("Save") { editor.save(doc) }
            Button("Save As…") { editor.save(doc, forceChooseLocation: true) }
            if let p = doc.path {
                Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: p)]) }
                Button("Copy Path") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(p, forType: .string)
                }
            }
            Divider()
            Button("Close") { editor.close(doc) }
        }
    }
}

private struct EditorStatusLine: View {
    @Environment(\.ui) private var ui
    let editor: EditorSession
    let document: EditorDocument

    var body: some View {
        let s = AppState.shared.settings.editor
        HStack(spacing: 14) {
            Text(document.path.map(Paths.abbreviate) ?? "Untitled").lineLimit(1).truncationMode(.head)
            Spacer()
            Text("Ln \(document.cursorLine), Col \(document.cursorColumn)" + (document.selectionLength > 0 ? " (\(document.selectionLength) selected)" : ""))
            Text(s.insertSpaces ? "Spaces: \(s.tabWidth)" : "Tabs")
            Text(document.usesCRLF ? "CRLF" : "LF")
            Text(document.language.displayName)
        }
        .font(ui.font(-2))
        .foregroundStyle(ui.secondary)
        .padding(.horizontal, 12)
        .frame(height: 22)
        .overlay(alignment: .top) { Rectangle().fill(ui.hairline).frame(height: 1) }
    }
}

/// Symbols of the active document; click to jump.
struct OutlinePanelView: View {
    @Environment(\.ui) private var ui
    let workspace: Workspace

    var body: some View {
        if let doc = workspace.selectedTab?.editor?.active {
            if doc.symbols.isEmpty {
                placeholder(doc.language == .plain ? "No outline for plain text." : "No symbols found in \(doc.name).")
            } else {
                let minDepth = doc.symbols.map(\.depth).min() ?? 0
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(doc.symbols) { sym in
                            OutlineRow(symbol: sym, indent: CGFloat(sym.depth - minDepth), current: isCurrent(sym, doc)) {
                                doc.controller.goTo(line: sym.line)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        } else {
            placeholder("Open a file in the editor to see its outline.")
        }
    }

    private func isCurrent(_ s: OutlineSymbol, _ doc: EditorDocument) -> Bool {
        let before = doc.symbols.last { $0.line <= doc.cursorLine }
        return before?.id == s.id
    }

    private func placeholder(_ text: String) -> some View {
        Text(text).font(ui.font(-1)).foregroundStyle(ui.secondary).padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct OutlineRow: View {
    @Environment(\.ui) private var ui
    let symbol: OutlineSymbol
    let indent: CGFloat
    let current: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            Text(badge).font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(ui.secondary)
                .frame(width: 12)
            Text(symbol.name).font(ui.font(-1)).lineLimit(1).truncationMode(.middle)
                .foregroundStyle(current ? ui.accent : ui.text)
            Spacer()
            Text("\(symbol.line)").font(ui.mono(-3)).foregroundStyle(ui.tertiary)
        }
        .padding(.leading, 10 + min(5, indent) * 10)
        .padding(.trailing, 10)
        .frame(height: 22)
        .background(RoundedRectangle(cornerRadius: 4).fill(hovering ? ui.hover : .clear).padding(.horizontal, 4))
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .onHover { hovering = $0 }
    }

    private var badge: String {
        switch symbol.kind {
        case .function: "ƒ"
        case .type: "T"
        case .property: "·"
        case .section: "#"
        }
    }
}
