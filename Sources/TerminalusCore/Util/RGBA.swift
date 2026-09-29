import Foundation

/// A platform-neutral sRGB color with hex parsing, used by the settings/theme model.
public struct RGBA: Equatable, Hashable, Sendable {
    public var r: Double
    public var g: Double
    public var b: Double
    public var a: Double

    public init(r: Double, g: Double, b: Double, a: Double = 1) {
        self.r = r.clamped01; self.g = g.clamped01; self.b = b.clamped01; self.a = a.clamped01
    }

    /// Parses `#rgb`, `#rrggbb` or `#rrggbbaa` (leading `#` optional).
    public init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6 || s.count == 8, let v = UInt64(s, radix: 16) else { return nil }
        if s.count == 6 {
            self.init(r: Double((v >> 16) & 0xff) / 255, g: Double((v >> 8) & 0xff) / 255, b: Double(v & 0xff) / 255)
        } else {
            self.init(r: Double((v >> 24) & 0xff) / 255, g: Double((v >> 16) & 0xff) / 255,
                      b: Double((v >> 8) & 0xff) / 255, a: Double(v & 0xff) / 255)
        }
    }

    public static let black = RGBA(r: 0, g: 0, b: 0)
    public static let white = RGBA(r: 1, g: 1, b: 1)

    public var hex: String {
        let c = [r, g, b].map { Int(($0 * 255).rounded()) }
        if a < 0.999 {
            return String(format: "#%02x%02x%02x%02x", c[0], c[1], c[2], Int((a * 255).rounded()))
        }
        return String(format: "#%02x%02x%02x", c[0], c[1], c[2])
    }

    public var r8: UInt16 { UInt16((r * 255).rounded()) }
    public var g8: UInt16 { UInt16((g * 255).rounded()) }
    public var b8: UInt16 { UInt16((b * 255).rounded()) }

    /// Relative luminance (WCAG).
    public var luminance: Double {
        func lin(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }

    public var isDark: Bool { luminance < 0.35 }

    public func withAlpha(_ alpha: Double) -> RGBA { RGBA(r: r, g: g, b: b, a: alpha) }

    public func mix(_ other: RGBA, _ t: Double) -> RGBA {
        RGBA(r: r + (other.r - r) * t, g: g + (other.g - g) * t, b: b + (other.b - b) * t, a: a + (other.a - a) * t)
    }

    public func lighter(_ t: Double) -> RGBA { mix(.white, t).withAlpha(a) }
    public func darker(_ t: Double) -> RGBA { mix(.black, t).withAlpha(a) }

    /// Moves the color toward more contrast against itself (lighter if dark, darker if light).
    public func raised(_ t: Double) -> RGBA { isDark ? lighter(t) : darker(t) }
}

extension Double {
    var clamped01: Double { Swift.min(1, Swift.max(0, self.isNaN ? 0 : self)) }
}
