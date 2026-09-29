import AppKit
import SwiftUI
import TerminalusCore

/// A panel being dragged between docks.
struct PanelDrag: Equatable {
    var id: String
    var title: String
    var location: CGPoint
    var target: PanelDropTarget?
}

struct PanelDropTarget: Equatable {
    var side: DockSide
    var index: Int
}

struct DockFramesKey: PreferenceKey {
    static let defaultValue: [DockSide: CGRect] = [:]
    static func reduce(value: inout [DockSide: CGRect], nextValue: () -> [DockSide: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

struct PanelFramesKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

@MainActor
enum PanelInfo {
    static func title(_ id: String) -> String {
        switch id {
        case PanelID.files: return "Files"
        case PanelID.system: return "System"
        case PanelID.outline: return "Outline"
        default:
            if let cid = PanelID.customID(id) { return AppState.shared.panels.panel(id: cid)?.name ?? "Panel" }
            return id
        }
    }
}

/// One side of the window: a stack of panels.
struct DockView: View {
    @Environment(\.ui) private var ui
    let workspace: Workspace
    let side: DockSide
    let topInset: CGFloat

    var body: some View {
        let layout = AppState.shared.settings.layout
        let panels = workspace.effectivePanels(side)
        GeometryReader { geo in
            let heights = panelHeights(panels, total: geo.size.height - topInset, layout: layout)
            VStack(spacing: 0) {
                Color.clear.frame(height: topInset)
                ForEach(Array(panels.enumerated()), id: \.element) { i, id in
                    PanelContainer(workspace: workspace, id: id, side: side, isFirst: i == 0,
                                   collapsed: layout.collapsedPanels.contains(id), contentHeight: heights[id] ?? 0,
                                   index: i, count: panels.count)
                    if i < panels.count - 1, !layout.collapsedPanels.contains(id),
                       let next = panels[i + 1] as String?, !layout.collapsedPanels.contains(next) {
                        PanelSplitHandle(upper: id, lower: next, upperHeight: heights[id] ?? 0, lowerHeight: heights[next] ?? 0)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .background(ui.dockFill)
        .background(GeometryReader { g in
            Color.clear.preference(key: DockFramesKey.self, value: [side: g.frame(in: .named("workspace"))])
        })
    }

    static let headerHeight: CGFloat = 28
    static let handleHeight: CGFloat = 5

    private func panelHeights(_ panels: [String], total: CGFloat, layout: LayoutSettings) -> [String: CGFloat] {
        let expanded = panels.filter { !layout.collapsedPanels.contains($0) }
        let handles = CGFloat(max(0, expanded.count - 1)) * Self.handleHeight
        let available = max(0, total - CGFloat(panels.count) * Self.headerHeight - handles)
        let weights = expanded.map { max(0.1, layout.panelWeights[$0] ?? 1) }
        let sum = weights.reduce(0, +)
        var out: [String: CGFloat] = [:]
        for (id, w) in zip(expanded, weights) { out[id] = sum > 0 ? floor(available * CGFloat(w / sum)) : 0 }
        return out
    }
}

/// Header + content of one panel.
private struct PanelContainer: View {
    @Environment(\.ui) private var ui
    let workspace: Workspace
    let id: String
    let side: DockSide
    let isFirst: Bool
    let collapsed: Bool
    let contentHeight: CGFloat
    let index: Int
    let count: Int

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(workspace: workspace, id: id, side: side, isFirst: isFirst, collapsed: collapsed, index: index, count: count)
            if !collapsed {
                content
                    .frame(height: max(0, contentHeight))
                    .clipped()
            }
        }
        .background(GeometryReader { g in
            Color.clear.preference(key: PanelFramesKey.self, value: [id: g.frame(in: .named("workspace"))])
        })
    }

    @ViewBuilder
    private var content: some View {
        switch id {
        case PanelID.files:
            FilesPanel(workspace: workspace)
        case PanelID.system:
            StatsPanelView(horizontal: false, workspace: workspace)
        case PanelID.outline:
            OutlinePanelView(workspace: workspace)
        default:
            if let cid = PanelID.customID(id), let p = AppState.shared.panels.panel(id: cid) {
                CustomPanelContent(panel: p, workspace: workspace)
            } else {
                Color.clear
            }
        }
    }
}

private struct PanelHeader: View {
    @Environment(\.ui) private var ui
    let workspace: Workspace
    let id: String
    let side: DockSide
    let isFirst: Bool
    let collapsed: Bool
    let index: Int
    let count: Int
    @State private var hovering = false

    var body: some View {
        let title = PanelInfo.title(id)
        HStack(spacing: 4) {
            Image(systemName: "chevron.right")
                .font(.system(size: 8, weight: .semibold))
                .rotationEffect(.degrees(collapsed ? 0 : 90))
                .foregroundStyle(ui.tertiary)
                .frame(width: 10)
            Text(title)
                .font(ui.sectionFont)
                .foregroundStyle(ui.secondary)
                .lineLimit(1)
            if let status = customStatus, let err = status.error {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 9)).foregroundStyle(ui.theme.warning.color)
                    .help(err)
            }
            if let status = customStatus, status.running {
                ProgressView().controlSize(.mini).scaleEffect(0.6).frame(width: 12, height: 12)
            }
            Spacer(minLength: 4)
            HStack(spacing: 0) {
                actions
                Menu {
                    PanelMenuItems(workspace: workspace, id: id, side: side, index: index, count: count, collapsed: collapsed)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 11))
                        .frame(width: 20, height: 18)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .foregroundStyle(ui.secondary)
            }
            .opacity(hovering || workspace.panelDrag != nil ? 1 : 0.55)
        }
        .padding(.leading, 8)
        .padding(.trailing, 6)
        .frame(height: DockView.headerHeight)
        .contentShape(Rectangle())
        .overlay(alignment: .top) { if !isFirst { Rectangle().fill(ui.hairline).frame(height: 1) } }
        .onHover { hovering = $0 }
        .onTapGesture(count: 1) { toggleCollapsed() }
        .gesture(
            DragGesture(minimumDistance: 6, coordinateSpace: .named("workspace"))
                .onChanged { g in
                    if workspace.panelDrag == nil { NSCursor.closedHand.push() }
                    workspace.panelDrag = PanelDrag(id: id, title: title, location: g.location,
                                                    target: workspace.dropTarget(at: g.location, dragging: id))
                }
                .onEnded { g in
                    NSCursor.pop()
                    if let t = workspace.dropTarget(at: g.location, dragging: id) {
                        AppState.shared.settingsStore.update { $0.layout.move(id, to: t.side, at: t.index) }
                    }
                    workspace.panelDrag = nil
                }
        )
        .help("Drag to move this panel to the other side")
    }

    private var customStatus: PanelStatus? {
        guard let cid = PanelID.customID(id), let p = AppState.shared.panels.panel(id: cid) else { return nil }
        return p.kind == .web ? workspace.webController(for: p).status : workspace.commandController(for: p).status
    }

    private func toggleCollapsed() {
        AppState.shared.settingsStore.update { s in
            if s.layout.collapsedPanels.contains(id) { s.layout.collapsedPanels.removeAll { $0 == id } } else { s.layout.collapsedPanels.append(id) }
        }
    }

    @ViewBuilder
    private var actions: some View {
        let s = AppState.shared.settings
        switch id {
        case PanelID.files:
            Menu {
                ForEach(TreeRootMode.allCases) { m in
                    Button {
                        AppState.shared.settingsStore.update { $0.tree.rootMode = m }
                    } label: {
                        if s.tree.rootMode == m { Label(m.label, systemImage: "checkmark") } else { Text(m.label) }
                    }
                }
                Divider()
                Toggle("Follow current directory", isOn: Binding(get: { s.tree.followCwd },
                                                                 set: { v in AppState.shared.settingsStore.update { $0.tree.followCwd = v } }))
                Toggle("Hidden files", isOn: Binding(get: { s.tree.showHidden },
                                                     set: { v in AppState.shared.settingsStore.update { $0.tree.showHidden = v } }))
                Toggle("Git status", isOn: Binding(get: { s.tree.gitBadges },
                                                   set: { v in AppState.shared.settingsStore.update { $0.tree.gitBadges = v } }))
                Divider()
                Button("Collapse All") { workspace.tree.collapseAll() }
            } label: {
                Image(systemName: "line.3.horizontal.decrease").font(.system(size: 11)).frame(width: 20, height: 18)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .foregroundStyle(ui.secondary)
            .help("Tree options")
            HeaderIconButton(symbol: "scope", help: "Reveal the current directory") { AppState.shared.perform(.revealCwdInTree) }
        case PanelID.system:
            Menu {
                ForEach(s.stats.normalizedWidgets) { w in
                    Toggle(w.kind.label, isOn: Binding(get: { w.enabled }, set: { v in
                        AppState.shared.settingsStore.update { st in
                            var list = st.stats.normalizedWidgets
                            if let i = list.firstIndex(where: { $0.kind == w.kind }) { list[i].enabled = v }
                            st.stats.widgets = list
                        }
                    }))
                }
            } label: {
                Image(systemName: "slider.horizontal.3").font(.system(size: 11)).frame(width: 20, height: 18)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .foregroundStyle(ui.secondary)
            .help("Choose widgets")
        default:
            if let cid = PanelID.customID(id), let p = AppState.shared.panels.panel(id: cid) {
                HeaderIconButton(symbol: "arrow.clockwise", help: "Reload") {
                    if p.kind == .web { workspace.webController(for: p).load() } else { workspace.commandController(for: p).runNow() }
                }
            }
        }
    }
}

/// Items of a panel's "…" menu (also used for its context menu).
private struct PanelMenuItems: View {
    let workspace: Workspace
    let id: String
    let side: DockSide
    let index: Int
    let count: Int
    let collapsed: Bool

    var body: some View {
        let store = AppState.shared.settingsStore
        Button("Move to \(side.opposite.label) Side") { store.update { $0.layout.move(id, to: side.opposite) } }
        if index > 0 { Button("Move Up") { store.update { $0.layout.move(id, to: side, at: index - 1) } } }
        if index < count - 1 { Button("Move Down") { store.update { $0.layout.move(id, to: side, at: index + 1) } } }
        Button(collapsed ? "Expand" : "Collapse") {
            store.update { s in
                if collapsed { s.layout.collapsedPanels.removeAll { $0 == id } } else { s.layout.collapsedPanels.append(id) }
            }
        }
        Button("Hide Panel") { store.update { $0.layout.remove(id) } }
        if let cid = PanelID.customID(id), let p = AppState.shared.panels.panel(id: cid) {
            Divider()
            Button("Edit Code…") { PanelImportWindowController.show(editing: p, side: side) }
            Button("Copy Panel Code") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(PanelCodeParser.manifest(for: p, side: side), forType: .string)
            }
            Button("Delete Panel…") { AppState.shared.deletePanel(p) }
        }
        Divider()
        Menu("Add Panel Here") {
            ForEach(AppState.shared.hiddenPanelIDs, id: \.self) { pid in
                Button(PanelInfo.title(pid)) { store.update { $0.layout.move(pid, to: side, at: index + 1) } }
            }
            Divider()
            Button("Import Window Code…") { PanelImportWindowController.show(side: side) }
        }
    }
}

/// Drag handle between two panels in the same dock.
private struct PanelSplitHandle: View {
    @Environment(\.ui) private var ui
    let upper: String
    let lower: String
    let upperHeight: CGFloat
    let lowerHeight: CGFloat
    @State private var hovering = false
    @State private var start: (Double, Double)?

    var body: some View {
        Rectangle()
            .fill(hovering ? ui.accent.opacity(0.5) : Color.clear)
            .frame(height: hovering ? 2 : 1)
            .frame(height: DockView.handleHeight)
            .contentShape(Rectangle())
            .onHover { inside in
                hovering = inside
                if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { g in
                        let layout = AppState.shared.settings.layout
                        if start == nil { start = (layout.panelWeights[upper] ?? 1, layout.panelWeights[lower] ?? 1) }
                        guard let (wu, wl) = start else { return }
                        let total = upperHeight + lowerHeight
                        guard total > 40 else { return }
                        let newUpper = min(total - 40, max(40, upperHeight + g.translation.height))
                        let sum = wu + wl
                        AppState.shared.settingsStore.update {
                            $0.layout.panelWeights[upper] = sum * Double(newUpper / total)
                            $0.layout.panelWeights[lower] = sum * Double((total - newUpper) / total)
                        }
                    }
                    .onEnded { _ in start = nil }
            )
    }
}

/// Drop zones and the dragged panel's label while a panel is being moved.
struct PanelDragOverlay: View {
    @Environment(\.ui) private var ui
    let workspace: Workspace

    var body: some View {
        if let drag = workspace.panelDrag {
            ZStack(alignment: .topLeading) {
                ForEach([DockSide.left, .right], id: \.self) { side in
                    let zone = workspace.dropZone(for: side)
                    let isTarget = drag.target?.side == side
                    RoundedRectangle(cornerRadius: 6)
                        .fill(ui.accent.opacity(isTarget ? 0.10 : 0.03))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(ui.accent.opacity(isTarget ? 0.8 : 0.25),
                                                                                style: StrokeStyle(lineWidth: 1, dash: isTarget ? [] : [4, 4])))
                        .frame(width: zone.width - 8, height: zone.height - 8)
                        .offset(x: zone.minX + 4, y: zone.minY + 4)
                    if isTarget, let y = workspace.insertionY(for: drag) {
                        Rectangle().fill(ui.accent).frame(width: zone.width - 24, height: 2)
                            .offset(x: zone.minX + 12, y: y - 1)
                    }
                }
                Text(drag.title)
                    .font(ui.font(-1, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 6).fill(ui.theme.panelBackground.color))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(ui.hairline))
                    .shadow(color: .black.opacity(0.3), radius: 8, y: 3)
                    .fixedSize()
                    // Keep the label inside the window when dragging near the right edge.
                    .offset(x: drag.location.x + 160 > workspace.layoutSize.width ? drag.location.x - 150 : drag.location.x + 12,
                            y: drag.location.y + 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .allowsHitTesting(false)
        }
    }
}

/// Files panel: current path, git line and the tree.
struct FilesPanel: View {
    @Environment(\.ui) private var ui
    let workspace: Workspace

    var body: some View {
        let s = AppState.shared.settings
        VStack(spacing: 0) {
            if s.layout.showBreadcrumb {
                BreadcrumbView(workspace: workspace)
            }
            treeView(s)
        }
    }

    private func treeView(_ s: AppSettings) -> some View {
        var h = Hasher()
        h.combine(ui.theme.id)
        h.combine(s.appearance.accentOverride)
        h.combine(s.appearance.uiFontDesign)
        h.combine(s.tree.fontSize)
        h.combine(s.tree.rowHeight)
        h.combine(s.tree.iconStyle)
        h.combine(s.tree.coloredIcons)
        return FileTreeView(model: workspace.tree, styleKey: h.finalize())
            .padding(.horizontal, 2)
    }
}

/// The current path as clickable segments, plus the git line.
struct BreadcrumbView: View {
    @Environment(\.ui) private var ui
    let workspace: Workspace

    var body: some View {
        let session = workspace.focusedSession
        let cwd = session?.cwd ?? "/"
        let parts = Paths.ancestry(of: cwd)
        VStack(alignment: .leading, spacing: 3) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 3) {
                    ForEach(Array(parts.enumerated()), id: \.offset) { i, p in
                        if i > 1 { Text("/").foregroundStyle(ui.tertiary) }
                        segment(p, isLast: i == parts.count - 1, session: session)
                    }
                }
                .font(ui.font(-1))
                .padding(.horizontal, 12)
            }
            .defaultScrollAnchor(.trailing)
            .id(cwd)
            if let s = session, s.isRemote {
                Text("ssh · \(s.remoteHost ?? "remote host")").font(ui.font(-2)).foregroundStyle(ui.theme.warning.color).padding(.horizontal, 12)
            } else if let g = workspace.tree.gitStatus {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.branch").font(.system(size: 9))
                    Text(g.branch ?? "detached")
                    if g.ahead > 0 { Text("↑\(g.ahead)") }
                    if g.behind > 0 { Text("↓\(g.behind)") }
                    let changes = g.stagedCount + g.unstagedCount + g.untrackedCount
                    if changes > 0 { Text("· \(changes) changed") }
                }
                .font(ui.font(-2))
                .foregroundStyle(ui.secondary)
                .padding(.horizontal, 12)
            }
        }
        .padding(.top, 2)
        .padding(.bottom, 6)
    }

    private func segment(_ path: String, isLast: Bool, session: TerminalSession?) -> some View {
        let name = path == "/" ? "/" : (path == NSHomeDirectory() ? "~" : (path as NSString).lastPathComponent)
        return Button {
            workspace.tree.reveal(path, select: true, force: true)
        } label: {
            Text(name)
                .fontWeight(isLast ? .semibold : .regular)
                .foregroundStyle(isLast ? ui.text : ui.secondary)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("cd Here") { session?.cd(path) }
            Button("New Tab Here") { workspace.newTab(cwd: path) }
            Button("Open in Finder") { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(path, forType: .string)
            }
        }
        .help(path)
    }
}
