import AppKit
import SwiftUI
import SwiftTerm
import TerminalusCore

typealias STColor = SwiftTerm.Color

extension RGBA {
    var nsColor: NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: a) }
    var cgColor: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
    var color: SwiftUI.Color { SwiftUI.Color(.sRGB, red: r, green: g, blue: b, opacity: a) }
    var stColor: STColor {
        STColor(red: UInt16((r * 65535).rounded()), green: UInt16((g * 65535).rounded()), blue: UInt16((b * 65535).rounded()))
    }
}

extension NSColor {
    var rgba: RGBA {
        let c = usingColorSpace(.sRGB) ?? usingColorSpace(.deviceRGB) ?? .black
        return RGBA(r: Double(c.redComponent), g: Double(c.greenComponent), b: Double(c.blueComponent), a: Double(c.alphaComponent))
    }
}

extension SwiftUI.Color {
    init(hex: String, fallback: SwiftUI.Color = .clear) {
        if let c = RGBA(hex: hex) { self = c.color } else { self = fallback }
    }

    var rgba: RGBA { NSColor(self).rgba }
}

extension FontWeightOption {
    var nsWeight: NSFont.Weight {
        switch self {
        case .ultraLight: .ultraLight
        case .thin: .thin
        case .light: .light
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        case .heavy: .heavy
        }
    }
}

extension UIFontDesign {
    var swiftUI: Font.Design {
        switch self {
        case .system: .default
        case .rounded: .rounded
        case .monospaced: .monospaced
        case .serif: .serif
        }
    }
}

enum FontResolver {
    /// The terminal font for a family name ("" = system monospaced), size and weight.
    static func terminalFont(family: String, size: Double, weight: FontWeightOption) -> NSFont {
        let sz = CGFloat(min(72, max(6, size)))
        if family.isEmpty {
            return NSFont.monospacedSystemFont(ofSize: sz, weight: weight.nsWeight)
        }
        let desc = NSFontDescriptor(fontAttributes: [
            .family: family,
            .traits: [NSFontDescriptor.TraitKey.weight: weight.nsWeight.rawValue],
        ])
        if let f = NSFont(descriptor: desc, size: sz), f.familyName == family { return f }
        if let f = NSFont(name: family, size: sz) { return f }
        return NSFont.monospacedSystemFont(ofSize: sz, weight: weight.nsWeight)
    }

    /// Installed fixed-pitch font families, sorted.
    static let monospacedFamilies: [String] = {
        let fm = NSFontManager.shared
        let fixed = fm.availableFontNames(with: .fixedPitchFontMask) ?? []
        var families = Set<String>()
        for name in fixed {
            if let f = NSFont(name: name, size: 12), let fam = f.familyName, !fam.hasPrefix(".") { families.insert(fam) }
        }
        // Common coding fonts that don't always set the fixed-pitch trait.
        for fam in fm.availableFontFamilies where fam.localizedCaseInsensitiveContains("mono") || fam.localizedCaseInsensitiveContains("code") || fam.contains("Nerd") {
            families.insert(fam)
        }
        return families.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }()
}
