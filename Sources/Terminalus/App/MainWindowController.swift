import AppKit
import SwiftUI
import TerminalusCore

/// The window itself is transparent; an NSVisualEffectView provides the optional blur and the SwiftUI
/// RootView paints the themed background, sidebar, tabs and panes on top.
final class TerminalusWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class MainWindowController: NSWindowController, NSWindowDelegate {
    let workspace: Workspace
    private let effectView = NSVisualEffectView()
    private let hosting: NSHostingView<RootView>
    private var responderObservation: NSKeyValueObservation?
    private var appliedTitlebar: TitlebarStyle?

    init(workspace: Workspace, cascadeFrom previous: NSWindow?) {
        self.workspace = workspace
        let s = AppState.shared.settings.window
        let window = TerminalusWindow(
            contentRect: NSRect(x: 0, y: 0, width: s.initialWidth, height: s.initialHeight),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        hosting = NSHostingView(rootView: RootView(workspace: workspace))
        super.init(window: window)

        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.minSize = NSSize(width: 520, height: 320)
        window.delegate = self
        window.collectionBehavior.insert(.fullScreenPrimary)

        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.autoresizingMask = [.width, .height]
        hosting.sizingOptions = []
        hosting.autoresizingMask = [.width, .height]
        effectView.addSubview(hosting)
        window.contentView = effectView
        hosting.frame = effectView.bounds

        workspace.window = window
        workspace.onEmpty = { [weak window] in window?.close() }

        if let prev = previous {
            let origin = prev.frame.origin
            window.setFrameOrigin(NSPoint(x: origin.x + 28, y: origin.y - 28))
        } else if !window.setFrameUsingName("TerminalusMainWindow") {
            window.center()
        }
        window.setFrameAutosaveName(previous == nil ? "TerminalusMainWindow" : "")

        responderObservation = window.observe(\.firstResponder, options: [.new]) { [weak self] w, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                var r = w.firstResponder as? NSView
                while let v = r {
                    if let tv = v as? TerminalusTerminalView {
                        self.workspace.terminalBecameFirstResponder(tv)
                        return
                    }
                    r = v.superview
                }
            }
        }
        applyWindowSettings()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func applyWindowSettings() {
        guard let window else { return }
        let s = AppState.shared.settings.window
        if appliedTitlebar != s.titlebar {
            appliedTitlebar = s.titlebar
            switch s.titlebar {
            case .standard:
                window.titlebarAppearsTransparent = false
                window.titleVisibility = .visible
                window.styleMask.remove(.fullSizeContentView)
                setTrafficLights(hidden: false)
            case .transparent:
                window.styleMask.insert(.fullSizeContentView)
                window.titlebarAppearsTransparent = true
                window.titleVisibility = s.showTitleText ? .visible : .hidden
                setTrafficLights(hidden: false)
            case .hidden:
                window.styleMask.insert(.fullSizeContentView)
                window.titlebarAppearsTransparent = true
                window.titleVisibility = .hidden
                setTrafficLights(hidden: true)
            }
        }
        if s.titlebar == .transparent { window.titleVisibility = s.showTitleText ? .visible : .hidden }
        effectView.material = s.blurMaterial.nsMaterial
        effectView.isHidden = false
        effectView.state = s.blur ? .active : .inactive
        // With blur off, the effect view must not paint its own (opaque) material.
        effectView.alphaValue = s.blur ? 1 : 0.0001
        window.level = s.alwaysOnTop ? .floating : .normal
        window.appearance = NSAppearance(named: AppState.shared.uiTheme.isDark ? .darkAqua : .aqua)
        window.invalidateShadow()
    }

    private func setTrafficLights(hidden: Bool) {
        for b in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window?.standardWindowButton(b)?.isHidden = hidden
        }
    }

    // MARK: NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        workspace.confirmCloseAll()
    }

    func windowWillClose(_ notification: Notification) {
        workspace.teardown()
        AppState.shared.windowClosed(self)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        workspace.windowIsActive = true
        AppState.shared.windowBecameKey(self)
        if let s = workspace.focusedSession {
            s.isFocused = true
            if window?.firstResponder === window || window?.firstResponder == nil {
                window?.makeFirstResponder(s.view)
            }
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        workspace.windowIsActive = false
    }

    func windowDidChangeOcclusionState(_ notification: Notification) {
        let visible = window?.occlusionState.contains(.visible) ?? true
        if !visible { workspace.windowIsActive = false }
        AppState.shared.stats.windowVisibilityChanged()
    }

    var isVisibleOnScreen: Bool {
        guard let window else { return false }
        return window.isVisible && window.occlusionState.contains(.visible) && !window.isMiniaturized
    }
}

extension BlurMaterial {
    var nsMaterial: NSVisualEffectView.Material {
        switch self {
        case .hudWindow: .hudWindow
        case .underWindowBackground: .underWindowBackground
        case .sidebar: .sidebar
        case .fullScreenUI: .fullScreenUI
        case .popover: .popover
        case .menu: .menu
        case .titlebar: .titlebar
        case .headerView: .headerView
        case .sheet: .sheet
        case .windowBackground: .windowBackground
        case .contentBackground: .contentBackground
        }
    }
}
