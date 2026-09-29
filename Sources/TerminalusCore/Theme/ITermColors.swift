import Foundation

/// Import/export of iTerm2 `.itermcolors` property lists.
public enum ITermColors {
    public enum ImportError: LocalizedError {
        case notAPlist, missingColors
        public var errorDescription: String? {
            switch self {
            case .notAPlist: "The file is not a valid .itermcolors property list."
            case .missingColors: "The file does not define the 16 ANSI colors."
            }
        }
    }

    public static func importTheme(data: Data, name: String) throws -> Theme {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw ImportError.notAPlist
        }
        func color(_ key: String) -> String? {
            guard let d = plist[key] as? [String: Any] else { return nil }
            func comp(_ k: String) -> Double { (d[k] as? NSNumber)?.doubleValue ?? 0 }
            let alpha = (d["Alpha Component"] as? NSNumber)?.doubleValue ?? 1
            var r = comp("Red Component"), g = comp("Green Component"), b = comp("Blue Component")
            // Calibrated/generic RGB is close enough to sRGB for terminal palettes except for gamma;
            // Display P3 values are clipped into sRGB.
            let space = (d["Color Space"] as? String)?.lowercased() ?? "srgb"
            if space.contains("p3") {
                r = min(1, max(0, r)); g = min(1, max(0, g)); b = min(1, max(0, b))
            }
            return RGBA(r: r, g: g, b: b, a: alpha).hex
        }
        var ansi: [String] = []
        for i in 0..<16 {
            guard let c = color("Ansi \(i) Color") else { throw ImportError.missingColors }
            ansi.append(c)
        }
        let fg = color("Foreground Color") ?? ansi[7]
        let bg = color("Background Color") ?? ansi[0]
        let id = "user-" + name.lowercased().map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
        return Theme(
            id: id,
            name: name,
            foreground: fg,
            background: bg,
            cursor: color("Cursor Color") ?? fg,
            cursorText: color("Cursor Text Color") ?? bg,
            selection: color("Selection Color") ?? RGBA(hex: fg)!.withAlpha(0.3).hex,
            selectionText: color("Selected Text Color"),
            bold: color("Bold Color"),
            link: color("Link Color"),
            ansi: ansi
        )
    }

    public static func export(_ theme: Theme) throws -> Data {
        func dict(_ hex: String) -> [String: Any] {
            let c = RGBA(hex: hex) ?? .black
            return ["Red Component": c.r, "Green Component": c.g, "Blue Component": c.b, "Alpha Component": c.a, "Color Space": "sRGB"]
        }
        var d: [String: Any] = [:]
        for (i, c) in theme.ansi.prefix(16).enumerated() { d["Ansi \(i) Color"] = dict(c) }
        d["Foreground Color"] = dict(theme.foreground)
        d["Background Color"] = dict(theme.background)
        d["Cursor Color"] = dict(theme.cursor)
        if let c = theme.cursorText { d["Cursor Text Color"] = dict(c) }
        d["Selection Color"] = dict(theme.selection)
        if let c = theme.selectionText { d["Selected Text Color"] = dict(c) }
        if let c = theme.bold { d["Bold Color"] = dict(c) }
        if let c = theme.link { d["Link Color"] = dict(c) }
        return try PropertyListSerialization.data(fromPropertyList: d, format: .xml, options: 0)
    }
}
