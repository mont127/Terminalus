import Foundation

public enum Paths {
    public static var appSupport: URL {
        // TERMINALUS_HOME gives an isolated settings/panels folder (used for test instances).
        if let custom = ProcessInfo.processInfo.environment["TERMINALUS_HOME"], !custom.isEmpty {
            return URL(fileURLWithPath: (custom as NSString).expandingTildeInPath, isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Terminalus", isDirectory: true)
    }

    public static var settingsFile: URL { appSupport.appendingPathComponent("settings.json") }
    public static var themesDirectory: URL { appSupport.appendingPathComponent("themes", isDirectory: true) }
    public static var stateFile: URL { appSupport.appendingPathComponent("state.json") }

    public static func ensureDirectories() {
        for dir in [appSupport, themesDirectory] {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    /// "/Users/me/x" → "~/x"
    public static func abbreviate(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }

    /// The path plus every ancestor up to "/", root first.
    public static func ancestry(of path: String) -> [String] {
        let std = (path as NSString).standardizingPath
        guard std.hasPrefix("/") else { return [std] }
        var out = ["/"]
        var cur = ""
        for comp in std.split(separator: "/") {
            cur += "/" + comp
            out.append(cur)
        }
        return out
    }

    public static func isAncestor(_ ancestor: String, of path: String) -> Bool {
        if ancestor == "/" { return path.hasPrefix("/") }
        return path == ancestor || path.hasPrefix(ancestor + "/")
    }
}
