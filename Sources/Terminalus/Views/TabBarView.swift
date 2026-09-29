import AppKit
import SwiftUI
import UniformTypeIdentifiers
import TerminalusCore

struct TabBarView: View {
    @Environment(\.ui) private var ui
    let workspace: Workspace
    let leadingInset: CGFloat

    var body: some View {
        let style = AppState.shared.settings.layout.tabBarStyle
        HStack(spacing: 0) {
            Color.clear.frame(width: leadingInset)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: style == .pills ? 4 : 0) {
                    ForEach(Array(workspace.tabs.enumerated()), id: \.element.id) { i, tab in
                        TabItem(workspace: workspace, tab: tab, index: i, style: style)
                            .onDrag { NSItemProvider(object: tab.id as NSString) }
                            .onDrop(of: [UTType.text], delegate: TabDropDelegate(workspace: workspace, targetID: tab.id))
                    }
                }
                .padding(.horizontal, style == .pills ? 6 : 0)
                .frame(maxHeight: .infinity)
            }
            newTabButton.padding(.horizontal, 8)
        }
        .frame(maxHeight: .infinity)
    }

    private var newTabButton: some View {
        let profiles = AppState.shared.settings.profiles
        return Menu {
            ForEach(profiles) { p in
                Button("New Tab — \(p.name)") { workspace.newTab(profileID: p.id) }
            }
            Divider()
            Button("Split Right") { workspace.split(.horizontal) }
            Button("Split Down") { workspace.split(.vertical) }
        } label: {
            Image(systemName: "plus").font(.system(size: 11, weight: .medium)).foregroundStyle(ui.secondary)
        } primaryAction: {
            workspace.newTab()
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("New tab — hold for profiles and splits")
    }
}

private struct TabItem: View {
    @Environment(\.ui) private var ui
    let workspace: Workspace
    let tab: TabModel
    let index: Int
    let style: TabBarStyle
    @State private var hovering = false

    var body: some View {
        let selected = workspace.selectedTab?.id == tab.id
        let sessions = workspace.sessions(in: tab)
        let focused = workspace.sessions[tab.focusedPaneID]
        let editorName = tab.editor?.active?.name
        let title = tab.customTitle ?? editorName ?? focused?.displayTitle ?? "shell"
        let activity = sessions.contains { $0.hasUnseenActivity } && !selected
        let bell = sessions.contains { $0.bellPending }
        let running = sessions.contains { $0.runningCommand != nil && !$0.waitingForEditor }
        let profile = AppState.shared.settings.profile(id: focused?.profileID)
        let tint = profile.tabColor.flatMap(RGBA.init(hex:))?.color

        HStack(spacing: 6) {
            if tab.editor != nil {
                Image(systemName: "chevron.left.forwardslash.chevron.right").font(.system(size: 9)).foregroundStyle(ui.secondary)
            }
            if let tint { Circle().fill(tint).frame(width: 6, height: 6) }
            Text(title)
                .font(ui.font(-1, weight: selected ? .medium : .regular))
                .foregroundStyle(selected ? ui.text : ui.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 200)
            if sessions.count > 1 {
                Text("\(sessions.count)").font(ui.mono(-3)).foregroundStyle(ui.tertiary)
            }
            ZStack {
                if hovering {
                    Button { workspace.closeTab(tab.id) } label: {
                        Image(systemName: "xmark").font(.system(size: 8, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(ui.secondary)
                } else if bell {
                    Image(systemName: "bell.fill").font(.system(size: 8)).foregroundStyle(ui.theme.warning.color)
                } else if running {
                    Circle().fill(ui.accent).frame(width: 5, height: 5)
                } else if activity {
                    Circle().fill(ui.secondary).frame(width: 5, height: 5)
                } else if AppState.shared.settings.layout.showTabShortcuts && index < 9 {
                    Text("⌘\(index + 1)").font(ui.font(-3)).foregroundStyle(ui.tertiary)
                }
            }
            .frame(width: AppState.shared.settings.layout.showTabShortcuts ? 18 : 10)
        }
        .padding(.horizontal, 12)
        .frame(maxHeight: .infinity)
        .background(background(selected: selected))
        .contentShape(Rectangle())
        .onTapGesture { workspace.select(tab: tab) }
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Close Tab") { workspace.closeTab(tab.id) }
            Button("Split Right") { workspace.select(tab: tab); workspace.split(.horizontal) }
            Button("Split Down") { workspace.select(tab: tab); workspace.split(.vertical) }
            Divider()
            Button("Rename…") { rename() }
            if tab.customTitle != nil { Button("Reset Name") { tab.customTitle = nil } }
        }
    }

    @ViewBuilder
    private func background(selected: Bool) -> some View {
        switch style {
        case .underline:
            ZStack(alignment: .bottom) {
                Rectangle().fill(selected ? ui.hover : (hovering ? ui.hover.opacity(0.5) : .clear))
                Rectangle().fill(selected ? ui.accent : .clear).frame(height: 1.5)
            }
            .overlay(alignment: .trailing) { Rectangle().fill(ui.hairline).frame(width: 1) }
        case .pills:
            RoundedRectangle(cornerRadius: 6)
                .fill(selected ? ui.selection : (hovering ? ui.hover : .clear))
                .padding(.vertical, 5)
        case .blocks:
            Rectangle().fill(selected ? ui.selection : ui.track.opacity(hovering ? 1.4 : 0.8))
                .overlay(alignment: .trailing) { Rectangle().fill(ui.hairline).frame(width: 1) }
        case .minimal:
            Color.clear
        }
    }

    private func rename() {
        let alert = NSAlert()
        alert.messageText = "Rename Tab"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = tab.customTitle ?? ""
        field.placeholderString = "Automatic"
        alert.accessoryView = field
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        if alert.runModal() == .alertFirstButtonReturn {
            let t = field.stringValue.trimmingCharacters(in: .whitespaces)
            tab.customTitle = t.isEmpty ? nil : t
        }
    }
}

private struct TabDropDelegate: DropDelegate {
    let workspace: Workspace
    let targetID: String

    func performDrop(info: DropInfo) -> Bool {
        guard let item = info.itemProviders(for: [UTType.text]).first else { return false }
        item.loadObject(ofClass: NSString.self) { obj, _ in
            guard let id = obj as? String else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let to = workspace.tabs.firstIndex(where: { $0.id == targetID }) else { return }
                    workspace.moveTab(id: id, to: to)
                }
            }
        }
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
}

/// Thin bar under the terminal.
struct StatusBarView: View {
    @Environment(\.ui) private var ui
    let workspace: Workspace

    var body: some View {
        let s = workspace.focusedSession
        HStack(spacing: 14) {
            if let s {
                Text(s.isRemote ? "ssh \(s.remoteHost ?? "")" : Paths.abbreviate(s.cwd))
                    .lineLimit(1).truncationMode(.head)
                if let g = workspace.tree.gitStatus {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.branch").font(.system(size: 9))
                        Text((g.branch ?? "detached") + (g.isDirty ? "*" : ""))
                    }
                }
                Spacer()
                if let cmd = s.runningCommand, let start = s.commandStartedAt, !s.waitingForEditor {
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        Text("\(cmd.prefix(40))  \(Fmt.stopwatch(ctx.date.timeIntervalSince(start)))")
                    }
                } else if let code = s.lastExitCode, code != 0 {
                    Text("exit \(code)").foregroundStyle(ui.theme.danger.color)
                }
                Text("\(s.shellName)  \(s.cols)×\(s.rows)").font(ui.mono(-3))
            } else {
                Spacer()
            }
        }
        .font(ui.font(-2))
        .foregroundStyle(ui.secondary)
        .padding(.horizontal, 12)
        .frame(height: 22)
        .background(ui.dockFill)
        .overlay(alignment: .top) { Rectangle().fill(ui.hairline).frame(height: 1) }
    }
}
