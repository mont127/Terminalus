import Foundation

/// A keyboard shortcut such as "cmd+shift+t", "ctrl+alt+left" or "cmd+=".
public struct KeyCombo: Hashable, Codable, Sendable, CustomStringConvertible {
    public var command: Bool
    public var shift: Bool
    public var option: Bool
    public var control: Bool
    /// Lowercased key: a single character, or a named key (left, right, up, down, return, tab, space,
    /// escape, delete, forwarddelete, home, end, pageup, pagedown, f1…f20).
    public var key: String

    public init(key: String, command: Bool = false, shift: Bool = false, option: Bool = false, control: Bool = false) {
        self.key = KeyCombo.normalizeKey(key)
        self.command = command; self.shift = shift; self.option = option; self.control = control
    }

    public static let namedKeys: Set<String> = Set([
        "left", "right", "up", "down", "return", "enter", "tab", "space", "escape", "esc", "delete", "backspace",
        "forwarddelete", "home", "end", "pageup", "pagedown",
    ]).union((1...20).map { "f\($0)" })

    private static func normalizeKey(_ k: String) -> String {
        let l = k.lowercased()
        switch l {
        case "esc": return "escape"
        case "backspace": return "delete"
        case "enter": return "return"
        case "plus": return "+"
        case "minus": return "-"
        case "comma": return ","
        case "period": return "."
        case "slash": return "/"
        case "backslash": return "\\"
        default: return l
        }
    }

    /// Parses "cmd+shift+t". Modifier aliases: cmd/command/⌘, shift/⇧, alt/opt/option/⌥, ctrl/control/⌃.
    /// A literal "+" key is written "cmd++" or "cmd+plus".
    public init?(_ string: String) {
        var s = string.trimmingCharacters(in: .whitespaces).lowercased()
        guard !s.isEmpty else { return nil }
        var keyPart: String
        if s.hasSuffix("++") {
            keyPart = "+"
            s.removeLast(2)
        } else if s == "+" {
            keyPart = "+"
            s = ""
        } else {
            let parts = s.split(separator: "+", omittingEmptySubsequences: false).map(String.init)
            keyPart = parts.last ?? ""
            s = parts.dropLast().joined(separator: "+")
        }
        var cmd = false, shift = false, opt = false, ctrl = false
        for m in s.split(separator: "+").map(String.init) where !m.isEmpty {
            switch m {
            case "cmd", "command", "⌘", "super", "meta": cmd = true
            case "shift", "⇧": shift = true
            case "alt", "opt", "option", "⌥": opt = true
            case "ctrl", "control", "⌃": ctrl = true
            default: return nil
            }
        }
        keyPart = KeyCombo.normalizeKey(keyPart)
        guard keyPart.count == 1 || KeyCombo.namedKeys.contains(keyPart) else { return nil }
        self.init(key: keyPart, command: cmd, shift: shift, option: opt, control: ctrl)
    }

    /// Canonical string form ("cmd+shift+t").
    public var description: String {
        var parts: [String] = []
        if control { parts.append("ctrl") }
        if option { parts.append("alt") }
        if shift { parts.append("shift") }
        if command { parts.append("cmd") }
        parts.append(key == "+" ? "plus" : key)
        return parts.joined(separator: "+")
    }

    /// Symbolic form for menus and the palette ("⇧⌘T").
    public var symbolic: String {
        var s = ""
        if control { s += "⌃" }
        if option { s += "⌥" }
        if shift { s += "⇧" }
        if command { s += "⌘" }
        let names: [String: String] = [
            "left": "←", "right": "→", "up": "↑", "down": "↓", "return": "↩", "tab": "⇥", "space": "Space",
            "escape": "⎋", "delete": "⌫", "forwarddelete": "⌦", "home": "↖", "end": "↘", "pageup": "⇞", "pagedown": "⇟",
        ]
        s += names[key] ?? key.uppercased()
        return s
    }
}
