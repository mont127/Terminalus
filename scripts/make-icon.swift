// Renders the Terminalus app icon into an .iconset folder (run by build-app.sh, then `iconutil`).
// Usage: swift scripts/make-icon.swift <output.iconset>
import AppKit
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: a)
}

let pink: UInt32 = 0xff2e97
let cyan: UInt32 = 0x00f0ff
let violet: UInt32 = 0x9d4dff

func render(size px: Int) -> CGImage {
    let s = CGFloat(px)
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: s / 1024, y: s / 1024)

    // macOS icon grid: 824×824 squircle centered in 1024.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let squircle = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

    // Drop shadow.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 28, color: color(0x000000, 0.45))
    ctx.addPath(squircle)
    ctx.setFillColor(color(0x0a0714))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()

    // Deep indigo background gradient.
    let bg = CGGradient(colorsSpace: cs, colors: [color(0x1a0f3d), color(0x0b0718), color(0x05030c)] as CFArray, locations: [0, 0.6, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])

    // Aurora blobs.
    for (c, center, r) in [(pink, CGPoint(x: 260, y: 820), 420.0), (cyan, CGPoint(x: 860, y: 260), 440.0), (violet, CGPoint(x: 780, y: 860), 360.0)] {
        let g = CGGradient(colorsSpace: cs, colors: [color(c, 0.42), color(c, 0)] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(g, startCenter: center, startRadius: 0, endCenter: center, endRadius: CGFloat(r), options: [])
    }

    // Scanlines.
    ctx.setFillColor(color(0x000000, 0.18))
    var y: CGFloat = 100
    while y < 924 {
        ctx.fill(CGRect(x: 100, y: y, width: 824, height: 3))
        y += 9
    }

    // Left "file tree" column.
    let treeX: CGFloat = 170
    let rows: [(CGFloat, CGFloat, UInt32)] = [(0, 150, cyan), (30, 120, 0x9aa4ff), (30, 170, 0x9aa4ff), (60, 110, pink), (30, 140, 0x9aa4ff), (0, 130, cyan)]
    var ty: CGFloat = 780
    for (indent, w, c) in rows {
        ctx.setFillColor(color(c, 0.85))
        ctx.fill(CGRect(x: treeX + indent, y: ty, width: 22, height: 22))
        ctx.setFillColor(color(c, 0.55))
        ctx.addPath(CGPath(roundedRect: CGRect(x: treeX + indent + 34, y: ty + 4, width: w, height: 14), cornerWidth: 7, cornerHeight: 7, transform: nil))
        ctx.fillPath()
        ty -= 46
    }

    // Stat bars (bottom left).
    let bars: [(CGFloat, UInt32)] = [(0.45, cyan), (0.8, pink), (0.6, violet), (0.95, cyan), (0.35, pink)]
    for (i, (h, c)) in bars.enumerated() {
        let x = 180 + CGFloat(i) * 44
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 18, color: color(c, 0.9))
        ctx.setFillColor(color(c))
        ctx.addPath(CGPath(roundedRect: CGRect(x: x, y: 190, width: 28, height: 170 * h), cornerWidth: 6, cornerHeight: 6, transform: nil))
        ctx.fillPath()
        ctx.restoreGState()
    }

    // Divider between tree and terminal.
    ctx.setFillColor(color(pink, 0.5))
    ctx.fill(CGRect(x: 440, y: 170, width: 4, height: 690))

    // Neon prompt ">_" with glow.
    func drawText(_ text: String, size: CGFloat, at p: CGPoint, fill: UInt32, glow: UInt32) {
        let font = CTFontCreateWithName("Menlo-Bold" as CFString, size, nil)
        let attrs: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color(fill),
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
        for (blur, alpha) in [(60.0, 0.9), (26.0, 1.0), (8.0, 1.0)] {
            ctx.saveGState()
            ctx.setShadow(offset: .zero, blur: CGFloat(blur), color: color(glow, CGFloat(alpha)))
            ctx.textPosition = p
            CTLineDraw(line, ctx)
            ctx.restoreGState()
        }
        ctx.textPosition = p
        CTLineDraw(line, ctx)
    }
    drawText(">", size: 330, at: CGPoint(x: 480, y: 430), fill: 0xffffff, glow: pink)
    drawText("_", size: 330, at: CGPoint(x: 680, y: 430), fill: 0xe8fdff, glow: cyan)

    ctx.restoreGState()

    // Glowing rim.
    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.setLineWidth(6)
    ctx.setStrokeColor(color(pink, 0.55))
    ctx.setShadow(offset: .zero, blur: 16, color: color(pink, 0.8))
    ctx.strokePath()
    ctx.restoreGState()

    return ctx.makeImage()!
}

let sizes: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, px) in sizes {
    let img = render(size: px)
    let url = URL(fileURLWithPath: outDir).appendingPathComponent(name + ".png")
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, img, nil)
    CGImageDestinationFinalize(dest)
}
print("Wrote \(sizes.count) icon sizes to \(outDir)")
