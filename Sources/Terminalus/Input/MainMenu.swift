import AppKit
import TerminalusCore

/// Target for menu items that run AppActions.
@MainActor
final class MenuActionTarget: NSObject, NSMenuItemValidation {
    static let shared = MenuActionTarget()

    @objc func performAction(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let action = AppAction(rawValue: raw) else { return }
        // Closing commands target the key window when it is not a terminal window (e.g. Settings).
        if [.closePane, .closeTab, .closeWindow].contains(action), let key = NSApp.keyWindow,
           !(key.windowController is MainWindowController) {
            key.performClose(nil)
            return
        }
        AppState.shared.perform(action)
    }

    @objc func selectTheme(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        AppState.shared.settingsStore.update {
            $0.appearance.themeID = id
            $0.appearance.followSystemAppearance = false
        }
    }

    @objc func newTabWithProfile(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        if let ws = AppState.shared.activeWorkspace { ws.newTab(profileID: id) } else { AppState.shared.newWindow(profileID: id) }
    }

    @objc func openHelp(_ sender: Any?) {
        guard let ws = AppState.shared.activeWorkspace else { return }
        ws.paletteQuery = ""
        ws.paletteVisible = true
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        let s = AppState.shared.settings
        if item.action == #selector(selectTheme(_:)) {
            item.state = (item.representedObject as? String) == s.appearance.themeID ? .on : .off
            return true
        }
        if let raw = item.representedObject as? String, let a = AppAction(rawValue: raw) {
            switch a {
            case .toggleLeftDock: item.state = s.layout.leftDockVisible ? .on : .off
            case .toggleRightDock: item.state = s.layout.rightDockVisible && !s.layout.rightPanels.isEmpty ? .on : .off
            case .toggleStats: item.state = s.layout.side(of: PanelID.system) != nil ? .on : .off
            case .toggleHiddenFiles: item.state = s.tree.showHidden ? .on : .off
            case .toggleEffects: item.state = s.effects.enabled ? .on : .off
            case .toggleGlow: item.state = s.effects.glow.enabled ? .on : .off
            case .toggleScanlines: item.state = s.effects.scanlines.enabled ? .on : .off
            case .toggleGradient: item.state = s.background.gradient.enabled ? .on : .off
            case .toggleAlwaysOnTop: item.state = s.window.alwaysOnTop ? .on : .off
            default: break
            }
        }
        return true
    }
}

@MainActor
enum MainMenu {
    static func install() {
        let app = AppState.shared
        let bindings = app.bindings
        let main = NSMenu()

        func item(_ a: AppAction, _ title: String? = nil) -> NSMenuItem {
            let mi = NSMenuItem(title: title ?? a.title, action: #selector(MenuActionTarget.performAction(_:)), keyEquivalent: "")
            mi.target = MenuActionTarget.shared
            mi.representedObject = a.rawValue
            if let combo = bindings[a] { combo.apply(to: mi) }
            return mi
        }
        func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
            let top = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let m = NSMenu(title: title)
            items.forEach { m.addItem($0) }
            top.submenu = m
            return top
        }
        func std(_ title: String, _ sel: Selector, _ key: String, _ mods: NSEvent.ModifierFlags = .command) -> NSMenuItem {
            let mi = NSMenuItem(title: title, action: sel, keyEquivalent: key)
            mi.keyEquivalentModifierMask = mods
            return mi
        }

        func panelsMenu() -> NSMenuItem {
            var items: [NSMenuItem] = [item(.importPanel), .separator()]
            let ids = [PanelID.files, PanelID.system, PanelID.outline] + app.panels.panels.map { PanelID.custom($0.id) }
            for id in ids {
                let current = app.settings.layout.side(of: id)
                let choices: [(String, DockSide?)] = [("Left Side", .left), ("Right Side", .right), ("Hidden", nil)]
                let subs = choices.map { title, side -> NSMenuItem in
                    let mi = ClosureMenuItem(title: title, symbol: "", block: {
                        AppState.shared.settingsStore.update { s in
                            if let side { s.layout.move(id, to: side) } else { s.layout.remove(id) }
                        }
                    })
                    mi.image = nil
                    mi.state = current == side ? .on : .off
                    return mi
                }
                items.append(submenu(PanelInfo.title(id), subs))
            }
            return submenu("Panels", items)
        }

        // App
        main.addItem(submenu("Terminalus", [
            std("About Terminalus", #selector(NSApplication.orderFrontStandardAboutPanel(_:)), ""),
            .separator(),
            item(.openSettings),
            item(.openSettingsJSON),
            item(.reloadSettings),
            .separator(),
            std("Hide Terminalus", #selector(NSApplication.hide(_:)), "h"),
            std("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]),
            std("Show All", #selector(NSApplication.unhideAllApplications(_:)), ""),
            .separator(),
            std("Quit Terminalus", #selector(NSApplication.terminate(_:)), "q"),
        ]))

        // Shell
        let profiles = app.settings.profiles.map { p -> NSMenuItem in
            let mi = NSMenuItem(title: p.name, action: #selector(MenuActionTarget.newTabWithProfile(_:)), keyEquivalent: "")
            mi.target = MenuActionTarget.shared
            mi.representedObject = p.id
            return mi
        }
        main.addItem(submenu("Shell", [
            item(.newWindow), item(.newTab), submenu("New Tab with Profile", profiles),
            .separator(),
            item(.splitRight), item(.splitDown),
            .separator(),
            item(.closePane), item(.closeTab), item(.closeWindow),
            .separator(),
            item(.copyCwd), item(.openCwdInFinder), item(.clearBuffer),
        ]))

        // Edit
        main.addItem(submenu("File", [
            item(.openFileInEditor), item(.toggleIDE),
            .separator(),
            item(.save), item(.saveAs),
            .separator(),
            item(.runFile), item(.goToLine), item(.toggleComment),
        ]))

        main.addItem(submenu("Edit", [
            std("Undo", Selector(("undo:")), "z"),
            std("Redo", Selector(("redo:")), "z", [.command, .shift]),
            .separator(),
            std("Cut", #selector(NSText.cut(_:)), "x"),
            std("Copy", #selector(NSText.copy(_:)), "c"),
            std("Paste", #selector(NSText.paste(_:)), "v"),
            std("Select All", #selector(NSText.selectAll(_:)), "a"),
            .separator(),
            item(.find), item(.findNext), item(.findPrevious),
        ]))

        // View
        main.addItem(submenu("View", [
            item(.commandPalette),
            .separator(),
            item(.toggleLeftDock), item(.toggleRightDock), panelsMenu(), item(.toggleStats), item(.cycleStatsPlacement), item(.focusTerminal),
            .separator(),
            item(.increaseFont), item(.decreaseFont), item(.resetFont),
            .separator(),
            item(.scrollToTop), item(.scrollToBottom),
            .separator(),
            item(.toggleFullScreen),
        ]))

        // Tree
        main.addItem(submenu("Tree", [
            item(.focusTree), item(.revealCwdInTree), item(.toggleHiddenFiles), item(.collapseTree), item(.cycleTreeRoot),
        ]))

        // Appearance
        let themeItems = app.themes.all.map { t -> NSMenuItem in
            let mi = NSMenuItem(title: t.name, action: #selector(MenuActionTarget.selectTheme(_:)), keyEquivalent: "")
            mi.target = MenuActionTarget.shared
            mi.representedObject = t.id
            return mi
        }
        main.addItem(submenu("Appearance", [
            submenu("Theme", themeItems), item(.nextTheme), item(.previousTheme),
            .separator(),
            item(.toggleEffects), item(.toggleGlow), item(.toggleScanlines), item(.toggleGradient), item(.toggleTransparency),
        ]))

        // Window
        let tabItems: [NSMenuItem] = [AppAction.selectTab1, .selectTab2, .selectTab3, .selectTab4, .selectTab5, .selectTab6,
                                      .selectTab7, .selectTab8, .selectTab9].map { item($0) }
        let windowMenu = submenu("Window", [
            std("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"),
            std("Zoom", #selector(NSWindow.performZoom(_:)), ""),
            .separator(),
            item(.nextTab), item(.previousTab), item(.moveTabLeft), item(.moveTabRight),
            submenu("Select Tab", tabItems),
            .separator(),
            item(.focusNextPane), item(.focusPreviousPane), item(.focusPaneLeft), item(.focusPaneRight),
            item(.focusPaneUp), item(.focusPaneDown), item(.zoomPane), item(.equalizePanes),
            .separator(),
            item(.toggleAlwaysOnTop),
            .separator(),
            std("Bring All to Front", #selector(NSApplication.arrangeInFront(_:)), ""),
        ])
        main.addItem(windowMenu)

        let help = NSMenuItem(title: "Command Palette & Shortcuts", action: #selector(MenuActionTarget.openHelp(_:)), keyEquivalent: "")
        help.target = MenuActionTarget.shared
        let helpMenu = submenu("Help", [help])
        main.addItem(helpMenu)

        NSApp.mainMenu = main
        NSApp.windowsMenu = windowMenu.submenu
        NSApp.helpMenu = helpMenu.submenu
    }
}

extension KeyCombo {
    /// The key-equivalent string AppKit expects for this combo.
    var menuKeyEquivalent: String {
        let special: [String: Int] = [
            "left": NSLeftArrowFunctionKey, "right": NSRightArrowFunctionKey, "up": NSUpArrowFunctionKey,
            "down": NSDownArrowFunctionKey, "home": NSHomeFunctionKey, "end": NSEndFunctionKey,
            "pageup": NSPageUpFunctionKey, "pagedown": NSPageDownFunctionKey, "forwarddelete": NSDeleteFunctionKey,
        ]
        if let code = special[key], let scalar = UnicodeScalar(code) { return String(Character(scalar)) }
        if key.hasPrefix("f"), let n = Int(key.dropFirst()), (1...20).contains(n), let scalar = UnicodeScalar(NSF1FunctionKey + n - 1) {
            return String(Character(scalar))
        }
        switch key {
        case "return": return "\r"
        case "tab": return "\t"
        case "space": return " "
        case "escape": return "\u{1b}"
        case "delete": return "\u{8}"
        default: return key
        }
    }

    var modifierFlags: NSEvent.ModifierFlags {
        var f: NSEvent.ModifierFlags = []
        if command { f.insert(.command) }
        if shift { f.insert(.shift) }
        if option { f.insert(.option) }
        if control { f.insert(.control) }
        return f
    }

    func apply(to item: NSMenuItem) {
        item.keyEquivalent = menuKeyEquivalent
        item.keyEquivalentModifierMask = modifierFlags
    }

    /// Builds a combo from a key-down event, using the unshifted character of the physical key.
    static func from(event: NSEvent) -> KeyCombo? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let named: [UInt16: String] = [
            123: "left", 124: "right", 125: "down", 126: "up", 36: "return", 76: "return", 48: "tab", 49: "space",
            53: "escape", 51: "delete", 117: "forwarddelete", 115: "home", 119: "end", 116: "pageup", 121: "pagedown",
            122: "f1", 120: "f2", 99: "f3", 118: "f4", 96: "f5", 97: "f6", 98: "f7", 100: "f8", 101: "f9", 109: "f10",
            103: "f11", 111: "f12", 105: "f13", 107: "f14", 113: "f15", 106: "f16", 64: "f17", 79: "f18", 80: "f19", 90: "f20",
        ]
        let key: String
        if let n = named[event.keyCode] {
            key = n
        } else if let c = event.characters(byApplyingModifiers: []), !c.isEmpty {
            key = c.lowercased()
        } else if let c = event.charactersIgnoringModifiers, !c.isEmpty {
            key = c.lowercased()
        } else {
            return nil
        }
        return KeyCombo(key: key, command: flags.contains(.command), shift: flags.contains(.shift),
                        option: flags.contains(.option), control: flags.contains(.control))
    }
}

/// Intercepts key-downs in terminal windows and runs bound actions before the terminal sees them.
@MainActor
final class KeybindingManager {
    static let shared = KeybindingManager()
    private var monitor: Any?
    /// While set (e.g. the shortcut recorder is active) key events pass through untouched.
    var suspended = false

    func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated { KeybindingManager.shared.handle(event) }
        }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard !suspended, let window = event.window, window.windowController is MainWindowController else { return event }
        guard let combo = KeyCombo.from(event: event) else { return event }
        // Plain keys (no ⌘/⌃/⌥) are never intercepted so typing is unaffected.
        guard combo.command || combo.control || combo.option || combo.key.hasPrefix("f") && combo.key.count > 1 else { return event }
        let bindings = AppState.shared.bindings
        guard let action = bindings.first(where: { $0.value == combo })?.key else { return event }
        // Standard editing shortcuts belong to text fields (palette search, rename…).
        if window.firstResponder is NSTextView, [.find, .findNext, .findPrevious, .clearBuffer].contains(action) { return event }
        AppState.shared.perform(action)
        return nil
    }
}
