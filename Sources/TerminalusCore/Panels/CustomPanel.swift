import Foundation

/// A user panel created from pasted code. Stored as JSON in ~/Library/Application Support/Terminalus/panels.
public struct CustomPanel: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        /// HTML/CSS/JavaScript rendered in a web view, with the `terminalus` JavaScript API.
        case web
        /// A shell command whose (colored) output is shown and refreshed.
        case command
    }

    public var id: String
    public var name: String
    public var kind: Kind
    /// HTML for web panels, the command line for command panels.
    public var code: String
    /// Command panels: refresh interval in seconds (0 = only on demand / directory change).
    public var refreshSeconds: Double = 5
    /// Command panels: run in the focused terminal's working directory (otherwise in home).
    public var followCwd: Bool = true
    /// Web panels: allow `terminalus.run()` to execute shell commands.
    public var allowCommands: Bool = false
    public var createdAt: Date = Date()

    public init(id: String = UUID().uuidString.lowercased(), name: String, kind: Kind, code: String) {
        self.id = id
        self.name = name
        self.kind = kind
        self.code = code
    }

    private enum CodingKeys: String, CodingKey { case id, name, kind, code, refreshSeconds, followCwd, allowCommands, createdAt }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Panel"
        kind = try c.decodeIfPresent(Kind.self, forKey: .kind) ?? .web
        code = try c.decodeIfPresent(String.self, forKey: .code) ?? ""
        refreshSeconds = try c.decodeIfPresent(Double.self, forKey: .refreshSeconds) ?? 5
        followCwd = try c.decodeIfPresent(Bool.self, forKey: .followCwd) ?? true
        allowCommands = try c.decodeIfPresent(Bool.self, forKey: .allowCommands) ?? false
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }
}

/// Result of reading pasted panel code.
public struct ParsedPanelCode: Equatable, Sendable {
    public var name: String?
    public var kind: CustomPanel.Kind
    public var code: String
    public var side: DockSide?
    public var refreshSeconds: Double?
    public var allowCommands: Bool?
}

/// Understands three kinds of pasted "window code":
///  1. HTML (a full document or a fragment with <style>/<script>), optionally inside ``` fences;
///  2. a JSON manifest: {"name", "html" | "command", "side", "refresh", "allowCommands"};
///  3. a shell command (e.g. `git log --oneline -15`) → a command panel.
public enum PanelCodeParser {
    public static func parse(_ raw: String) -> ParsedPanelCode {
        let text = stripFences(raw).trimmingCharacters(in: .whitespacesAndNewlines)

        if text.hasPrefix("{"), let data = text.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let side = (obj["side"] as? String).flatMap(DockSide.init(rawValue:))
            let refresh = (obj["refresh"] as? NSNumber)?.doubleValue ?? (obj["refreshSeconds"] as? NSNumber)?.doubleValue
            let allow = obj["allowCommands"] as? Bool
            let name = obj["name"] as? String
            if let html = (obj["html"] as? String) ?? (obj["code"] as? String).flatMap({ looksLikeHTML($0) ? $0 : nil }) {
                return ParsedPanelCode(name: name ?? htmlTitle(html), kind: .web, code: html, side: side, refreshSeconds: refresh, allowCommands: allow)
            }
            if let cmd = (obj["command"] as? String) ?? (obj["code"] as? String) {
                return ParsedPanelCode(name: name ?? commandName(cmd), kind: .command, code: cmd, side: side, refreshSeconds: refresh, allowCommands: allow)
            }
        }

        if looksLikeHTML(text) {
            return ParsedPanelCode(name: htmlTitle(text), kind: .web, code: text, side: nil, refreshSeconds: nil, allowCommands: nil)
        }
        // Loose JavaScript (no markup) still becomes a web panel.
        if looksLikeJavaScript(text) {
            return ParsedPanelCode(name: nil, kind: .web, code: "<div id=\"app\"></div>\n<script>\n\(text)\n</script>",
                                   side: nil, refreshSeconds: nil, allowCommands: nil)
        }
        var cmd = text
        if cmd.hasPrefix("$ ") { cmd.removeFirst(2) }
        return ParsedPanelCode(name: commandName(cmd), kind: .command, code: cmd, side: nil, refreshSeconds: nil, allowCommands: nil)
    }

    /// Removes a surrounding Markdown code fence (```html … ```), as pasted from chat tools.
    public static func stripFences(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.hasPrefix("```") else { return s }
        if let nl = t.firstIndex(of: "\n") { t = String(t[t.index(after: nl)...]) } else { return s }
        if let end = t.range(of: "```", options: .backwards) { t = String(t[..<end.lowerBound]) }
        return t
    }

    public static func looksLikeHTML(_ s: String) -> Bool {
        let l = s.lowercased()
        let tags = ["<!doctype", "<html", "<body", "<div", "<script", "<style", "<canvas", "<svg", "<span", "<p>", "<p ",
                    "<h1", "<h2", "<h3", "<ul", "<table", "<button", "<input", "<textarea", "<main", "<section", "<pre", "<img"]
        return tags.contains { l.contains($0) }
    }

    static func looksLikeJavaScript(_ s: String) -> Bool {
        let markers = ["document.", "function ", "=> {", "const ", "let ", "terminalus.", "addEventListener", "console.log"]
        let hits = markers.filter { s.contains($0) }.count
        return hits >= 2 && s.contains(";") || s.contains("terminalus.") && s.contains("(")
    }

    public static func htmlTitle(_ html: String) -> String? {
        guard let r = html.range(of: "<title>", options: .caseInsensitive),
              let e = html.range(of: "</title>", options: .caseInsensitive, range: r.upperBound..<html.endIndex) else { return nil }
        let t = html[r.upperBound..<e.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    static func commandName(_ cmd: String) -> String {
        let first = cmd.split(whereSeparator: { $0 == "\n" }).first.map(String.init) ?? cmd
        return String(first.prefix(32))
    }

    /// A shareable manifest for a panel (what "Copy Panel Code" puts on the clipboard).
    public static func manifest(for p: CustomPanel, side: DockSide?) -> String {
        var d: [String: Any] = ["name": p.name]
        switch p.kind {
        case .web:
            d["html"] = p.code
            if p.allowCommands { d["allowCommands"] = true }
        case .command:
            d["command"] = p.code
            d["refresh"] = p.refreshSeconds
        }
        if let side { d["side"] = side.rawValue }
        guard let data = try? JSONSerialization.data(withJSONObject: d, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) else { return p.code }
        return String(decoding: data, as: UTF8.self)
    }
}
