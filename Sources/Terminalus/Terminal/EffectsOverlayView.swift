import AppKit
import QuartzCore
import TerminalusCore

/// Screen-space effects drawn over the terminal area: CRT scanlines (with an optional rolling band),
/// vignette, film grain and flicker. Built from Core Animation layers, never intercepts the mouse.
final class EffectsOverlayView: NSView {
    private let scanlines = CALayer()
    private let rollBand = CAGradientLayer()
    private let vignette = CAGradientLayer()
    private let noise = CALayer()
    private let flicker = CALayer()

    private var config = EffectsSettings()
    private var tint = RGBA.white
    private var paused = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer = CALayer()
        layer?.masksToBounds = true
        for l in [scanlines, rollBand, noise, vignette, flicker] as [CALayer] {
            l.actions = ["bounds": NSNull(), "position": NSNull(), "contents": NSNull()]
            layer?.addSublayer(l)
        }
        vignette.type = .radial
        vignette.startPoint = CGPoint(x: 0.5, y: 0.5)
        vignette.endPoint = CGPoint(x: 1.15, y: 1.15)
        flicker.backgroundColor = NSColor.black.cgColor
        flicker.opacity = 0
        rollBand.startPoint = CGPoint(x: 0.5, y: 0)
        rollBand.endPoint = CGPoint(x: 0.5, y: 1)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var isFlipped: Bool { true }

    func configure(_ effects: EffectsSettings, tint: RGBA, paused: Bool) {
        let changed = effects != config || tint != self.tint
        let pauseChanged = paused != self.paused
        config = effects
        self.tint = tint
        self.paused = paused
        if changed { rebuild() }
        if changed || pauseChanged { updateAnimations() }
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for l in [scanlines, vignette, noise, flicker] as [CALayer] { l.frame = bounds }
        rollBand.frame = CGRect(x: 0, y: 0, width: bounds.width, height: max(60, bounds.height * 0.18))
        CATransaction.commit()
        updateAnimations()
    }

    private var on: Bool { config.enabled }

    private func rebuild() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let sc = config.scanlines
        scanlines.isHidden = !(on && sc.enabled)
        if !scanlines.isHidden {
            scanlines.backgroundColor = NSColor(patternImage: Self.scanlinePattern(spacing: sc.spacing, thickness: sc.thickness)).cgColor
            scanlines.opacity = Float(sc.opacity)
        }
        rollBand.isHidden = !(on && sc.enabled && sc.animated)
        let band = tint.withAlpha(min(0.08, sc.opacity * 0.5)).cgColor
        rollBand.colors = [NSColor.clear.cgColor, band, NSColor.clear.cgColor]

        let v = config.vignette
        vignette.isHidden = !(on && v.enabled)
        vignette.colors = [NSColor.clear.cgColor, NSColor.black.withAlphaComponent(CGFloat(min(0.95, v.intensity))).cgColor]
        vignette.locations = [0.55, 1.0]

        let n = config.noise
        noise.isHidden = !(on && n.enabled)
        if !noise.isHidden {
            noise.backgroundColor = NSColor(patternImage: Self.noisePattern).cgColor
            noise.opacity = Float(n.opacity)
        }
        flicker.isHidden = !(on && config.flicker.enabled)
        CATransaction.commit()
    }

    private func updateAnimations() {
        rollBand.removeAllAnimations()
        flicker.removeAllAnimations()
        guard !paused, on else { return }
        if !rollBand.isHidden, bounds.height > 0 {
            let a = CABasicAnimation(keyPath: "position.y")
            a.fromValue = -rollBand.bounds.height
            a.toValue = bounds.height + rollBand.bounds.height
            a.duration = 7
            a.repeatCount = .infinity
            rollBand.add(a, forKey: "roll")
        }
        if !flicker.isHidden {
            let i = Float(min(0.3, config.flicker.intensity))
            let a = CAKeyframeAnimation(keyPath: "opacity")
            a.values = [0, i, 0, i * 0.4, 0, 0, i * 0.8, 0]
            a.keyTimes = [0, 0.05, 0.1, 0.32, 0.36, 0.7, 0.72, 1]
            a.duration = 2.3
            a.repeatCount = .infinity
            flicker.add(a, forKey: "flicker")
        }
    }

    private static func scanlinePattern(spacing: Double, thickness: Double) -> NSImage {
        let h = max(2, CGFloat(spacing))
        let t = min(h - 0.5, max(0.5, CGFloat(thickness)))
        return NSImage(size: NSSize(width: 4, height: h), flipped: true) { rect in
            NSColor.clear.setFill()
            rect.fill()
            NSColor.black.setFill()
            NSRect(x: 0, y: 0, width: rect.width, height: t).fill()
            return true
        }
    }

    private static let noisePattern: NSImage = {
        let size = 128
        var bytes = [UInt8](repeating: 0, count: size * size * 4)
        var rng = SystemRandomNumberGenerator()
        for i in 0..<(size * size) {
            let v = UInt8.random(in: 0...255, using: &rng)
            bytes[i * 4] = v
            bytes[i * 4 + 1] = v
            bytes[i * 4 + 2] = v
            bytes[i * 4 + 3] = UInt8.random(in: 40...140, using: &rng)
        }
        let cs = CGColorSpaceCreateDeviceRGB()
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        let cg = CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: size * 4, space: cs,
                         bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue), provider: provider,
                         decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        return NSImage(cgImage: cg, size: NSSize(width: size, height: size))
    }()
}
