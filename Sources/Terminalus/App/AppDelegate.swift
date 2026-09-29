import AppKit
import TerminalusCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppState.shared.start()
        KeybindingManager.shared.install()
        Automation.install()
        if Automation.directory != nil {
            // Test instances stay behind other windows and never take focus.
            for w in NSApp.windows { w.orderBack(nil) }
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        if AppState.shared.settingsStore.safeMode {
            let alert = NSAlert()
            alert.messageText = "Terminalus started in safe mode"
            alert.informativeText = "⌥ was held at launch, so default settings are in use and settings.json is neither read nor written. Quit and relaunch normally to leave safe mode."
            alert.runModal()
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let app = AppState.shared
        let mode = app.settings.terminal.confirmClose
        let running = app.hasRunningCommands
        guard mode == .always || (mode == .whenRunning && running) else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Quit Terminalus?"
        alert.informativeText = running ? "Some terminals are still running commands. Quitting will terminate them." : "All shells will be terminated."
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        return alert.runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppState.shared.settingsStore.writeNow()
        for wc in AppState.shared.windowControllers { wc.workspace.teardown() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if AppState.shared.windowControllers.isEmpty { AppState.shared.newWindow() }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    /// Folders dropped on the Dock icon (or `open -a Terminalus dir`) open in a new tab.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            let dir = isDir.boolValue ? url.path : url.deletingLastPathComponent().path
            if let ws = AppState.shared.activeWorkspace { ws.newTab(cwd: dir) } else { AppState.shared.newWindow(cwd: dir) }
        }
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let m = NSMenu()
        for a in [AppAction.newWindow, .newTab] {
            let mi = NSMenuItem(title: a.title, action: #selector(MenuActionTarget.performAction(_:)), keyEquivalent: "")
            mi.target = MenuActionTarget.shared
            mi.representedObject = a.rawValue
            m.addItem(mi)
        }
        return m
    }
}
