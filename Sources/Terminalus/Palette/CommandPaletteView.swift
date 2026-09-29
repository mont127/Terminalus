import AppKit
import SwiftUI
import TerminalusCore

struct PaletteItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let symbol: String
    let shortcut: String?
    let run: @MainActor () -> Void
}

@MainActor
enum CommandRegistry {
    static func items(for workspace: Workspace) -> [PaletteItem] {
        let app = AppState.shared
        let s = app.settings
        var out: [PaletteItem] = []
        for a in AppAction.allCases where a.tabIndex == nil {
            out.append(PaletteItem(id: "action." + a.rawValue, title: a.title, subtitle: a.category.rawValue, symbol: a.symbol,
                                   shortcut: app.bindings[a]?.symbolic) { app.perform(a) })
        }
        for t in app.themes.all {
            out.append(PaletteItem(id: "theme." + t.id, title: "Theme: \(t.name)", subtitle: t.id == s.appearance.themeID ? "Current theme" : "Appearance",
                                   symbol: "paintpalette", shortcut: nil) {
                app.settingsStore.update {
                    $0.appearance.themeID = t.id
                    $0.appearance.followSystemAppearance = false
                }
            })
        }
        for p in s.profiles {
            out.append(PaletteItem(id: "profile." + p.id, title: "New Tab: \(p.name)", subtitle: "Profile", symbol: "plus.rectangle", shortcut: nil) {
                workspace.newTab(profileID: p.id)
            })
        }
        for d in workspace.recentDirectories.prefix(20) {
            out.append(PaletteItem(id: "cd." + d, title: "cd \(Paths.abbreviate(d))", subtitle: "Recent directory", symbol: "folder", shortcut: nil) {
                workspace.focusedSession?.cd(d)
            })
        }
        let panelIDs = [PanelID.files, PanelID.system, PanelID.outline] + app.panels.panels.map { PanelID.custom($0.id) }
        for id in panelIDs {
            let title = PanelInfo.title(id)
            for (label, side) in [("Left Side", DockSide.left), ("Right Side", .right)] where s.layout.side(of: id) != side {
                out.append(PaletteItem(id: "panel.\(id).\(side.rawValue)", title: "Move \(title) to \(label)", subtitle: "Panels",
                                       symbol: side == .left ? "sidebar.left" : "sidebar.right", shortcut: nil) {
                    app.settingsStore.update { $0.layout.move(id, to: side) }
                })
            }
            if s.layout.side(of: id) != nil {
                out.append(PaletteItem(id: "panel.\(id).hide", title: "Hide \(title) Panel", subtitle: "Panels", symbol: "eye.slash", shortcut: nil) {
                    app.settingsStore.update { $0.layout.remove(id) }
                })
            }
        }
        if let ed = workspace.selectedTab?.editor, let doc = ed.active {
            for sym in doc.symbols.prefix(200) {
                out.append(PaletteItem(id: "sym.\(sym.id)", title: "@ \(sym.name)", subtitle: "\(doc.name):\(sym.line)", symbol: "text.alignleft", shortcut: nil) {
                    doc.controller.goTo(line: sym.line)
                })
            }
        }
        for m in TreeRootMode.allCases {
            out.append(PaletteItem(id: "root." + m.rawValue, title: "Tree Root: \(m.label)", subtitle: "Tree", symbol: "folder.badge.gearshape", shortcut: nil) {
                app.settingsStore.update { $0.tree.rootMode = m }
            })
        }
        for w in s.stats.normalizedWidgets {
            out.append(PaletteItem(id: "widget." + w.kind.rawValue, title: "\(w.enabled ? "Hide" : "Show") Widget: \(w.kind.label)",
                                   subtitle: "Stats", symbol: w.kind.symbol, shortcut: nil) {
                app.settingsStore.update { st in
                    var list = st.stats.normalizedWidgets
                    if let i = list.firstIndex(where: { $0.kind == w.kind }) { list[i].enabled.toggle() }
                    st.stats.widgets = list
                }
            })
        }
        for g in GradientStyle.allCases {
            out.append(PaletteItem(id: "gradient." + g.rawValue, title: "Background Gradient: \(g.label)", subtitle: "Effects", symbol: "sparkles", shortcut: nil) {
                app.settingsStore.update {
                    $0.background.gradient.style = g
                    $0.background.gradient.enabled = true
                }
            })
        }
        return out
    }
}

struct CommandPaletteView: View {
    @Environment(\.ui) private var ui
    @Bindable var workspace: Workspace
    @FocusState private var focused: Bool

    private var results: [PaletteItem] {
        Array(FuzzyMatcher.rank(CommandRegistry.items(for: workspace), query: workspace.paletteQuery) { $0.title + " " + $0.subtitle }.prefix(60))
    }

    var body: some View {
        let results = self.results
        let selection = min(workspace.paletteSelection, max(0, results.count - 1))
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(ui.secondary)
                TextField("Type a command, theme, profile or directory…", text: $workspace.paletteQuery)
                    .textFieldStyle(.plain)
                    .font(ui.font(3))
                    .focused($focused)
                    .onSubmit { run(results, selection) }
                Text("\(results.count)").font(ui.mono(-2)).foregroundStyle(ui.tertiary)
            }
            .padding(12)
            Rectangle().fill(ui.border).frame(height: 1)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 1) {
                        ForEach(Array(results.enumerated()), id: \.element.id) { i, item in
                            row(item, selected: i == selection)
                                .onTapGesture { run(results, i) }
                        }
                        if results.isEmpty {
                            Text("No matches").font(ui.font(-1)).foregroundStyle(ui.secondary).padding(20)
                        }
                    }
                    .padding(6)
                }
                .frame(height: 380)
                .onChange(of: selection) { _, v in
                    if results.indices.contains(v) { proxy.scrollTo(results[v].id) }
                }
            }
        }
        .frame(width: 600)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(ui.theme.panelBackground.withAlpha(0.98).color))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(ui.theme.text.withAlpha(0.12).color))
        .shadow(color: .black.opacity(0.35), radius: 24, y: 10)
        .onAppear { focused = true }
        .onKeyPress(.downArrow) {
            workspace.paletteSelection = min(results.count - 1, selection + 1)
            return .handled
        }
        .onKeyPress(.upArrow) {
            workspace.paletteSelection = max(0, selection - 1)
            return .handled
        }
        .onKeyPress(.escape) {
            close()
            return .handled
        }
        .onExitCommand { close() }
    }

    private func row(_ item: PaletteItem, selected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: item.symbol).font(.system(size: 11)).frame(width: 18).foregroundStyle(ui.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).font(ui.font(0)).foregroundStyle(ui.text)
                Text(item.subtitle).font(ui.font(-3)).foregroundStyle(ui.secondary)
            }
            Spacer()
            if let sc = item.shortcut {
                Text(sc).font(ui.font(-2, weight: .medium)).foregroundStyle(ui.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4).fill(ui.track))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(selected ? ui.selection : .clear))
        .contentShape(Rectangle())
        .id(item.id)
    }

    private func run(_ results: [PaletteItem], _ index: Int) {
        guard results.indices.contains(index) else { return }
        let item = results[index]
        close()
        DispatchQueue.main.async { item.run() }
    }

    private func close() {
        workspace.paletteVisible = false
        workspace.paletteQuery = ""
        DispatchQueue.main.async { workspace.focusedSession?.focusTerminal() }
    }
}
