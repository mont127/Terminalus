import AppKit
import SwiftUI
import TerminalusCore

/// Root of every terminal window.
struct RootView: View {
    let workspace: Workspace

    var body: some View {
        let app = AppState.shared
        let s = app.settings
        let theme = app.uiTheme
        let ui = UIContext(theme: theme, appearance: s.appearance, stats: s.stats)
        let active = workspace.windowIsActive || !s.effects.pauseWhenInactive
        ZStack(alignment: .top) {
            BackgroundStack(theme: theme, window: s.window, background: s.background, effectsEnabled: s.effects.enabled, paused: !active)
            MainLayout(workspace: workspace, settings: s, effectsPaused: !active)
            if workspace.paletteVisible {
                CommandPaletteView(workspace: workspace)
                    .padding(.top, 70)
                    .transition(.opacity.combined(with: .offset(y: -8)))
                    .zIndex(10)
            }
            BannerView(store: app.settingsStore)
                .padding(.top, s.window.titlebar == .standard ? 8 : 34)
                .zIndex(11)
        }
        .environment(\.ui, ui)
        .foregroundStyle(ui.text)
        .tint(ui.accent)
        .ignoresSafeArea()
        .animation(s.appearance.animateUI ? .easeOut(duration: 0.15) : nil, value: workspace.paletteVisible)
        .background(WindowTitleSync(title: workspace.focusedSession?.displayTitle ?? "Terminalus", window: workspace.window))
    }
}

/// Keeps the NSWindow title (Mission Control, Window menu) in sync with the focused session.
private struct WindowTitleSync: View {
    let title: String
    weak var window: NSWindow?

    var body: some View {
        Color.clear
            .onAppear { window?.title = title }
            .onChange(of: title) { _, t in window?.title = t }
    }
}

private struct MainLayout: View {
    @Environment(\.ui) private var ui
    let workspace: Workspace
    let settings: AppSettings
    let effectsPaused: Bool

    @State private var leftDrag: CGFloat?
    @State private var rightDrag: CGFloat?

    private var layout: LayoutSettings { settings.layout }
    private var titlebarInset: CGFloat { settings.window.titlebar == .standard ? 0 : 28 }

    var body: some View {
        let leftVisible = workspace.isDockVisible(.left)
        let rightVisible = workspace.isDockVisible(.right)
        let leftWidth = leftDrag ?? CGFloat(layout.leftDockWidth)
        let rightWidth = rightDrag ?? CGFloat(layout.rightDockWidth)
        GeometryReader { geo in
            HStack(spacing: 0) {
                if leftVisible {
                    DockView(workspace: workspace, side: .left, topInset: titlebarInset)
                        .frame(width: leftWidth)
                    ResizeHandle(value: leftWidth, range: 180...700, invert: false) { v in leftDrag = v } onEnd: { v in
                        leftDrag = nil
                        AppState.shared.settingsStore.update { $0.layout.leftDockWidth = Double(v) }
                    }
                }
                TerminalColumn(workspace: workspace, settings: settings, effectsPaused: effectsPaused, titlebarInset: titlebarInset,
                               trafficLightInset: settings.window.titlebar == .transparent && !leftVisible ? 78 : 0)
                if rightVisible {
                    ResizeHandle(value: rightWidth, range: 180...700, invert: true) { v in rightDrag = v } onEnd: { v in
                        rightDrag = nil
                        AppState.shared.settingsStore.update { $0.layout.rightDockWidth = Double(v) }
                    }
                    DockView(workspace: workspace, side: .right, topInset: titlebarInset)
                        .frame(width: rightWidth)
                }
            }
            .onAppear { workspace.layoutSize = geo.size }
            .onChange(of: geo.size) { _, s in workspace.layoutSize = s }
        }
        .coordinateSpace(name: "workspace")
        .onPreferenceChange(DockFramesKey.self) { workspace.dockFrames = $0 }
        .onPreferenceChange(PanelFramesKey.self) { workspace.panelFrames = $0 }
        .overlay { PanelDragOverlay(workspace: workspace) }
    }
}

private struct TerminalColumn: View {
    @Environment(\.ui) private var ui
    let workspace: Workspace
    let settings: AppSettings
    let effectsPaused: Bool
    let titlebarInset: CGFloat
    let trafficLightInset: CGFloat

    var body: some View {
        let layout = settings.layout
        let showTabs = layout.tabBarPosition != .hidden && (layout.showTabBarWithOneTab || workspace.tabs.count > 1)
        VStack(spacing: 0) {
            if showTabs && layout.tabBarPosition == .top {
                TabBarView(workspace: workspace, leadingInset: trafficLightInset)
                    .frame(height: max(30, titlebarInset + 6))
                Rectangle().fill(ui.hairline).frame(height: 1)
            } else if titlebarInset > 0 {
                Color.clear.frame(height: titlebarInset)
            }
            if let tab = workspace.selectedTab, let editor = tab.editor {
                IDESplit(workspace: workspace, editor: editor) { paneArea }
            } else {
                paneArea
            }
            if showTabs && layout.tabBarPosition == .bottom {
                Rectangle().fill(ui.hairline).frame(height: 1)
                TabBarView(workspace: workspace, leadingInset: 0).frame(height: 32)
            }
            if layout.statsStrip {
                Rectangle().fill(ui.hairline).frame(height: 1)
                StatsPanelView(horizontal: true, workspace: workspace)
                    .frame(height: CGFloat(layout.statsStripHeight) * ui.scale + 30)
                    .background(ui.dockFill)
            }
            if layout.showStatusBar {
                StatusBarView(workspace: workspace)
            }
        }
    }

    @ViewBuilder
    private var paneArea: some View {
        if let tab = workspace.selectedTab {
            let theme = ui.theme
            PaneAreaRepresentable(
                root: tab.root,
                sessions: workspace.sessions,
                focused: tab.focusedPaneID,
                zoomed: tab.zoomedPaneID,
                style: PaneAreaView.Style(dividerWidth: CGFloat(settings.layout.splitDividerWidth),
                                          dividerColor: theme.border.a < 0.05 ? theme.text.withAlpha(0.1) : theme.border,
                                          accent: theme.accent,
                                          dimAmount: CGFloat(settings.effects.inactivePaneDim)),
                effects: settings.effects,
                effectsTint: theme.glow,
                effectsPaused: effectsPaused,
                onResize: { path, f in workspace.resizeSplit(path: path, fraction: f) }
            )
        } else {
            Color.clear
        }
    }
}

/// Editor above, the tab's terminals below, with a draggable divider.
private struct IDESplit<Terminal: View>: View {
    @Environment(\.ui) private var ui
    let workspace: Workspace
    let editor: EditorSession
    @ViewBuilder let terminal: Terminal
    @State private var dragFraction: Double?
    @State private var start: Double?
    @State private var hovering = false

    var body: some View {
        GeometryReader { geo in
            let fraction = dragFraction ?? AppState.shared.settings.editor.terminalHeight
            let termH = max(60, min(geo.size.height - 120, geo.size.height * CGFloat(fraction)))
            VStack(spacing: 0) {
                EditorArea(editor: editor, workspace: workspace)
                    .frame(height: geo.size.height - termH - 5)
                ZStack {
                    Rectangle().fill(ui.hairline).frame(height: 1)
                    if hovering { Rectangle().fill(ui.accent.opacity(0.5)).frame(height: 2) }
                }
                .frame(height: 5)
                .contentShape(Rectangle())
                .onHover { inside in
                    hovering = inside
                    if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
                }
                .gesture(
                    DragGesture(minimumDistance: 1, coordinateSpace: .global)
                        .onChanged { g in
                            if start == nil { start = fraction }
                            dragFraction = min(0.85, max(0.1, (start ?? fraction) - Double(g.translation.height / max(1, geo.size.height))))
                        }
                        .onEnded { _ in
                            if let f = dragFraction { AppState.shared.settingsStore.update { $0.editor.terminalHeight = f } }
                            dragFraction = nil
                            start = nil
                        }
                )
                terminal.frame(height: termH)
            }
        }
    }
}

/// Invisible drag strip that resizes an adjacent panel.
struct ResizeHandle: View {
    @Environment(\.ui) private var ui
    let value: CGFloat
    let range: ClosedRange<CGFloat>
    let invert: Bool
    let onChange: (CGFloat) -> Void
    let onEnd: (CGFloat) -> Void
    @State private var start: CGFloat?
    @State private var hovering = false

    var body: some View {
        Rectangle()
            .fill(hovering ? ui.accent.opacity(0.5) : ui.hairline)
            .frame(width: hovering ? 2 : 1)
            .frame(width: 5)
            .contentShape(Rectangle())
            .onHover { inside in
                hovering = inside
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { g in
                        if start == nil { start = value }
                        let d = invert ? -g.translation.width : g.translation.width
                        onChange(min(range.upperBound, max(range.lowerBound, (start ?? value) + d)))
                    }
                    .onEnded { g in
                        let d = invert ? -g.translation.width : g.translation.width
                        onEnd(min(range.upperBound, max(range.lowerBound, (start ?? value) + d)))
                        start = nil
                    }
            )
    }
}

/// Error / safe-mode banner.
private struct BannerView: View {
    @Environment(\.ui) private var ui
    let store: SettingsStore

    var body: some View {
        if let err = store.loadError {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(ui.theme.warning.color)
                Text(err).font(ui.font(-1)).lineLimit(3)
                Button("Open settings.json") { AppState.shared.openSettingsJSON() }
                Button("Use current settings") { store.overwriteBrokenFile() }
                Button { store.loadError = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(ui.theme.panelBackground.withAlpha(0.97).color))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(ui.hairline))
            .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
            .frame(maxWidth: 720)
        } else if store.safeMode {
            Text("Safe mode — default settings, nothing is saved")
                .font(ui.font(-2, weight: .medium))
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(ui.theme.warning.color.opacity(0.9)))
                .foregroundStyle(Color.black)
        }
    }
}
