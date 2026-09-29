import AppKit
import SwiftTerm
import TerminalusCore

/// Opt-in scripting hook used for automated testing. Only active when the app is launched with
/// `--automation <dir>` (or TERMINALUS_AUTOMATION=<dir>). Every 0.25 s the app runs and deletes the
/// `*.json` command files in <dir>, in name order. Each file holds {"cmd": "...", ...}.
///
///   {"cmd":"type","text":"ls\r"}             send text to the focused shell
///   {"cmd":"action","name":"splitRight"}     run an AppAction
///   {"cmd":"snapshot","path":"/tmp/x.png"}   save the key window as PNG
///   {"cmd":"dump","path":"/tmp/state.json"}  write the focused workspace's state
@MainActor
enum Automation {
    static var directory: URL? {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--automation"), i + 1 < args.count { return URL(fileURLWithPath: args[i + 1]) }
        if let e = ProcessInfo.processInfo.environment["TERMINALUS_AUTOMATION"], !e.isEmpty { return URL(fileURLWithPath: e) }
        return nil
    }

    private static var timer: Timer?

    /// Appends a line to <dir>/log.txt (testing only).
    static func log(_ line: @autoclosure () -> String) {
        guard let dir = directory else { return }
        let url = dir.appendingPathComponent("log.txt")
        let text = line() + "\n"
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile()
            h.write(Data(text.utf8))
            try? h.close()
        } else {
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    static func install() {
        guard let dir = directory else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let t = Timer(timeInterval: 0.25, repeats: true) { _ in
            MainActor.assumeIsolated { poll(dir) }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        NSLog("Terminalus automation enabled: %@", dir.path)
    }

    private static func poll(_ dir: URL) {
        let files = ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" && $0.lastPathComponent.hasPrefix("cmd-") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        for f in files {
            let data = try? Data(contentsOf: f)
            try? FileManager.default.removeItem(at: f)
            guard let data, let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let cmd = obj["cmd"] as? String else { continue }
            handle(cmd, obj)
        }
    }

    private static func handle(_ cmd: String, _ obj: [String: Any]) {
        let app = AppState.shared
        switch cmd {
        case "type":
            app.activeWorkspace?.focusedSession?.send((obj["text"] as? String) ?? "")
        case "action":
            if let n = obj["name"] as? String, let a = AppAction(rawValue: n) { app.perform(a) }
        case "snapshot":
            if let p = obj["path"] as? String { snapshot(to: URL(fileURLWithPath: p), settingsWindow: (obj["window"] as? String) == "settings") }
        case "dump":
            if let p = obj["path"] as? String { dump(to: URL(fileURLWithPath: p)) }
        case "palette":
            if let ws = app.activeWorkspace {
                ws.paletteQuery = (obj["query"] as? String) ?? ""
                ws.paletteVisible = true
            }
        case "newTab":
            let profile = (obj["profile"] as? String).flatMap { name in app.settings.profiles.first { $0.id == name || $0.name == name }?.id }
            app.activeWorkspace?.newTab(profileID: profile, cwd: obj["cwd"] as? String)
        case "closeTab":
            app.activeWorkspace?.closeTab()
        case "key":
            // Posts a synthetic key-down through the normal event path (local monitors, menus, views).
            guard let window = app.activeWorkspace?.window, let code = obj["keyCode"] as? Int else { return }
            var flags: NSEvent.ModifierFlags = []
            for m in (obj["mods"] as? [String]) ?? [] {
                switch m {
                case "cmd": flags.insert(.command)
                case "shift": flags.insert(.shift)
                case "alt": flags.insert(.option)
                case "ctrl": flags.insert(.control)
                default: break
                }
            }
            let chars = (obj["chars"] as? String) ?? ""
            if let ev = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                                         windowNumber: window.windowNumber, context: nil, characters: chars,
                                         charactersIgnoringModifiers: chars, isARepeat: false, keyCode: UInt16(code)) {
                NSApp.postEvent(ev, atStart: false)
            }
        case "editorType":
            // Types into the focused code editor through the normal key path (auto-indent etc. apply).
            if let ed = app.activeWorkspace?.selectedTab?.editor, let doc = ed.active, let text = obj["text"] as? String {
                let tv = doc.controller.textView
                tv.window?.makeFirstResponder(tv)
                for ch in text {
                    if ch == "\n" { tv.insertNewline(nil) } else if ch == "\t" { tv.insertTab(nil) } else { tv.insertText(String(ch), replacementRange: tv.selectedRange()) }
                }
            }
        case "editorSave":
            if let ed = app.activeWorkspace?.selectedTab?.editor, let doc = ed.active { ed.save(doc) }
        case "editorClose":
            if let ed = app.activeWorkspace?.selectedTab?.editor, let doc = ed.active { ed.close(doc) }
        case "editorFallback":
            if let ed = app.activeWorkspace?.selectedTab?.editor, let doc = ed.active { ed.fallBack(doc) }
        case "movePanel":
            if let id = obj["id"] as? String, let side = (obj["side"] as? String).flatMap(DockSide.init(rawValue:)) {
                app.settingsStore.update { $0.layout.move(id, to: side, at: obj["index"] as? Int) }
            }
        case "addPanel":
            // {"cmd":"addPanel","code":"…","side":"right","allowCommands":true}
            if let code = obj["code"] as? String {
                let parsed = PanelCodeParser.parse(code)
                var p = CustomPanel(name: (obj["name"] as? String) ?? parsed.name ?? "Panel", kind: parsed.kind, code: parsed.code)
                p.allowCommands = (obj["allowCommands"] as? Bool) ?? parsed.allowCommands ?? false
                p.refreshSeconds = parsed.refreshSeconds ?? 5
                app.panels.save(p)
                app.settingsStore.update { $0.layout.move(PanelID.custom(p.id), to: DockSide(rawValue: (obj["side"] as? String) ?? "right") ?? .right) }
            }
        case "dragPanel":
            // Simulates the header drag of a panel: {"id":"system","to":[x,y],"drop":true}
            guard let ws = app.activeWorkspace, let id = obj["id"] as? String, let to = obj["to"] as? [Double] else { return }
            let p = CGPoint(x: to[0], y: to[1])
            let target = ws.dropTarget(at: p, dragging: id)
            ws.panelDrag = PanelDrag(id: id, title: PanelInfo.title(id), location: p, target: target)
            log("dragPanel \(id) at \(p) → \(target.map { "\($0.side.rawValue)#\($0.index)" } ?? "none")")
            if obj["drop"] as? Bool == true {
                if let t = target { app.settingsStore.update { $0.layout.move(id, to: t.side, at: t.index) } }
                ws.panelDrag = nil
            }
        case "importWindow":
            PanelImportWindowController.show()
        case "drag":
            // Synthetic mouse drag in window coordinates (origin top-left): {"from":[x,y],"to":[x,y]}
            guard let w = app.activeWorkspace?.window, let f = obj["from"] as? [Double], let t = obj["to"] as? [Double] else { return }
            let h = w.contentView?.bounds.height ?? w.frame.height
            func pt(_ a: [Double]) -> NSPoint { NSPoint(x: a[0], y: h - a[1]) }
            let steps = 12
            var events: [NSEvent] = []
            func ev(_ type: NSEvent.EventType, _ p: NSPoint) -> NSEvent? {
                NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                   windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
            }
            if let e = ev(.leftMouseDown, pt(f)) { events.append(e) }
            for i in 1...steps {
                let x = f[0] + (t[0] - f[0]) * Double(i) / Double(steps), y = f[1] + (t[1] - f[1]) * Double(i) / Double(steps)
                if let e = ev(.leftMouseDragged, pt([x, y])) { events.append(e) }
            }
            if let e = ev(.leftMouseUp, pt(t)) { events.append(e) }
            for (i, e) in events.enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.03 * Double(i)) { NSApp.postEvent(e, atStart: false) }
            }
        case "closeSettings":
            app.settingsWindow?.close()
        case "settingsPane":
            if let n = obj["name"] as? String { NotificationCenter.default.post(name: .terminalusSettingsPane, object: n) }
        default:
            break
        }
    }

    private static func snapshot(to url: URL, settingsWindow: Bool) {
        let window = settingsWindow
            ? AppState.shared.settingsWindow?.window
            : (NSApp.orderedWindows.first { $0.isVisible && $0.windowController is MainWindowController } ?? NSApp.keyWindow)
        guard let window else { return }
        let target = (obj: window, id: CGWindowID(window.windowNumber))
        if let img = CGWindowListCreateImage(.null, .optionIncludingWindow, target.id, [.boundsIgnoreFraming, .bestResolution]) {
            write(img, to: url)
            return
        }
        // Fallback: render the layer tree (no blur, but shows the layout).
        guard let view = target.obj.contentView, let layer = view.layer else { return }
        let scale = target.obj.backingScaleFactor
        let w = Int(view.bounds.width * scale), h = Int(view.bounds.height * scale)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.scaleBy(x: scale, y: scale)
        layer.render(in: ctx)
        if let img = ctx.makeImage() { write(img, to: url) }
    }

    private static func write(_ img: CGImage, to url: URL) {
        let rep = NSBitmapImageRep(cgImage: img)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    private static func dump(to url: URL) {
        guard let ws = AppState.shared.activeWorkspace else { return }
        let s = ws.focusedSession
        let tree = ws.tree
        var d: [String: Any] = [
            "tabs": ws.tabs.count,
            "panes": ws.selectedTab?.root.leaves.count ?? 0,
            "treeRoot": tree.rootPath,
            "treeCwd": tree.cwd,
            "expanded": Array(tree.expandedPaths).sorted(),
            "theme": AppState.shared.effectiveThemeID,
            "statsTick": AppState.shared.stats.tick,
            "sessions": ws.sessions.count,
            "rss": Int(ProcessInspector.taskInfo(of: getpid())?.rss ?? 0),
        ]
        if let s {
            d["cwd"] = s.cwd
            d["shell"] = s.shellName
            d["pid"] = s.shellPid
            d["integration"] = s.integrationActive
            d["runningCommand"] = s.runningCommand ?? NSNull()
            d["lastCommand"] = s.lastCommand ?? NSNull()
            d["lastExitCode"] = s.lastExitCode.map { Int($0) } ?? NSNull()
            d["foreground"] = s.foregroundProcess ?? NSNull()
            d["title"] = s.displayTitle
            d["cols"] = s.cols
            d["rows"] = s.rows
            let t = s.view.getTerminal()
            d["screen"] = (0..<t.rows).compactMap { t.getLine(row: $0)?.translateToString(trimRight: true) }
                .joined(separator: "\n").trimmingCharacters(in: .newlines)
        }
        if let ed = ws.selectedTab?.editor {
            d["editor"] = [
                "documents": ed.documents.map { ["name": $0.name, "path": $0.path ?? "", "dirty": $0.isDirty, "language": $0.language.rawValue,
                                                 "line": $0.cursorLine, "symbols": $0.symbols.map(\.name)] as [String: Any] },
                "active": ed.active?.name ?? "",
                "text": ed.active?.controller.text ?? "",
                "requests": ed.requests.count,
                "message": ed.message ?? "",
            ]
        }
        d["leftPanels"] = ws.effectivePanels(.left)
        d["rightPanels"] = ws.effectivePanels(.right)
        d["dockFrames"] = ws.dockFrames.map { "\($0.key.rawValue): \(Int($0.value.minX)),\(Int($0.value.minY)) \(Int($0.value.width))x\(Int($0.value.height))" }
        d["panelFrames"] = ws.panelFrames.map { "\($0.key): \(Int($0.value.minX)),\(Int($0.value.minY)) \(Int($0.value.width))x\(Int($0.value.height))" }
        d["waiting"] = ws.sessions.values.filter(\.waitingForEditor).count
        d["focusedResponder"] = String(describing: type(of: ws.window?.firstResponder as Any))
        if let g = tree.gitStatus {
            d["git"] = ["root": g.root, "branch": g.branch ?? "", "dirty": g.isDirty, "files": g.files.count]
        }
        if let data = try? JSONSerialization.data(withJSONObject: d, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: url)
        }
    }
}


extension Notification.Name {
    static let terminalusSettingsPane = Notification.Name("terminalusSettingsPane")
}
