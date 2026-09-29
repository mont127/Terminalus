import AppKit
import QuartzCore
import SwiftUI
import TerminalusCore

/// Animated background gradients built from Core Animation layers. The render server runs the
/// animations, so they cost the app almost no CPU (unlike a Canvas redrawn every frame).
final class GradientLayerView: NSView {
    struct Config: Equatable {
        var style: GradientStyle
        var colors: [RGBA]
        var speed: Double
        var animated: Bool
        var paused: Bool
    }

    private var config: Config?
    private let container = CALayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer = CALayer()
        layer?.masksToBounds = true
        layer?.addSublayer(container)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func apply(_ c: Config) {
        let old = config
        config = c
        if old == nil || old!.style != c.style || old!.colors != c.colors || old!.speed != c.speed || old!.animated != c.animated {
            rebuild()
        }
        setPaused(c.paused || !c.animated || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }

    override func layout() {
        super.layout()
        if container.frame.size != bounds.size {
            rebuild()
            setPaused(config.map { $0.paused || !$0.animated } ?? true)
        }
    }

    // MARK: Pause / resume without losing the current frame

    private func setPaused(_ paused: Bool) {
        let l = container
        if paused {
            guard l.speed != 0 else { return }
            let t = l.convertTime(CACurrentMediaTime(), from: nil)
            l.speed = 0
            l.timeOffset = t
        } else {
            guard l.speed == 0 else { return }
            let paused = l.timeOffset
            l.speed = 1
            l.timeOffset = 0
            l.beginTime = 0
            l.beginTime = l.convertTime(CACurrentMediaTime(), from: nil) - paused
        }
    }

    // MARK: Building

    private func rebuild() {
        guard let c = config else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        container.sublayers?.forEach { $0.removeFromSuperlayer() }
        container.frame = bounds
        let colors = c.colors.isEmpty ? [RGBA.white] : c.colors
        let speed = max(0.001, c.speed)
        switch c.style {
        case .aurora: buildAurora(colors, speed: speed, animated: c.animated)
        case .linear: buildLinear(colors, speed: speed, animated: c.animated)
        case .radial: buildRadial(colors, speed: speed, animated: c.animated)
        case .conic: buildConic(colors, speed: speed, animated: c.animated)
        case .waves: buildWaves(colors, speed: speed, animated: c.animated)
        }
        CATransaction.commit()
    }

    private func buildAurora(_ colors: [RGBA], speed: Double, animated: Bool) {
        let w = bounds.width, h = bounds.height
        let m = max(w, h)
        for (i, c) in colors.enumerated() {
            let fi = Double(i)
            let blob = CAGradientLayer()
            blob.type = .radial
            blob.colors = [c.cgColor, c.withAlpha(0).cgColor]
            blob.startPoint = CGPoint(x: 0.5, y: 0.5)
            blob.endPoint = CGPoint(x: 1, y: 1)
            let r = m * 1.15
            blob.bounds = CGRect(x: 0, y: 0, width: r, height: r)
            let cx = w * (0.5 + 0.42 * sin(fi * 1.7)), cy = h * (0.5 + 0.42 * cos(fi * 2.3))
            blob.position = CGPoint(x: cx, y: cy)
            container.addSublayer(blob)
            guard animated else { continue }
            // Drift along an ellipse around the center (Lissajous-like thanks to per-blob periods).
            let path = CGMutablePath()
            let rx = w * 0.42, ry = h * 0.42
            let steps = 48
            for s in 0...steps {
                let a = Double(s) / Double(steps) * 2 * .pi
                let p = CGPoint(x: w / 2 + rx * sin(a + fi * 1.7), y: h / 2 + ry * cos(a * (i % 2 == 0 ? 1 : -1) + fi * 2.3))
                if s == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            let move = CAKeyframeAnimation(keyPath: "position")
            move.path = path
            move.duration = (2 * .pi / (0.7 + 0.13 * fi)) / speed
            move.repeatCount = .infinity
            move.calculationMode = .cubicPaced
            blob.add(move, forKey: "drift")
            let breathe = CABasicAnimation(keyPath: "transform.scale")
            breathe.fromValue = 0.85
            breathe.toValue = 1.15
            breathe.duration = (2 * .pi / 0.9) / speed / 2
            breathe.autoreverses = true
            breathe.repeatCount = .infinity
            breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            blob.add(breathe, forKey: "breathe")
        }
    }

    private func buildLinear(_ colors: [RGBA], speed: Double, animated: Bool) {
        // An oversized square rotated around the center, so the gradient direction sweeps.
        let d = hypot(bounds.width, bounds.height)
        let g = CAGradientLayer()
        g.colors = colors.map(\.cgColor)
        g.startPoint = CGPoint(x: 0, y: 0.5)
        g.endPoint = CGPoint(x: 1, y: 0.5)
        g.bounds = CGRect(x: 0, y: 0, width: d, height: d)
        g.position = CGPoint(x: bounds.midX, y: bounds.midY)
        container.addSublayer(g)
        if animated { g.add(spin(duration: (2 * .pi / 0.6) / speed), forKey: "spin") }
    }

    private func buildRadial(_ colors: [RGBA], speed: Double, animated: Bool) {
        let m = max(bounds.width, bounds.height)
        let g = CAGradientLayer()
        g.type = .radial
        g.colors = (colors + [colors.last!.withAlpha(0)]).map(\.cgColor)
        g.startPoint = CGPoint(x: 0.5, y: 0.5)
        g.endPoint = CGPoint(x: 1, y: 1)
        g.bounds = CGRect(x: 0, y: 0, width: m * 1.5, height: m * 1.5)
        g.position = CGPoint(x: bounds.midX, y: bounds.midY)
        container.addSublayer(g)
        if animated {
            let pulse = CABasicAnimation(keyPath: "transform.scale")
            pulse.fromValue = 0.7
            pulse.toValue = 1.05
            pulse.duration = (2 * .pi / 1.3) / speed / 2
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            g.add(pulse, forKey: "pulse")
        }
    }

    private func buildConic(_ colors: [RGBA], speed: Double, animated: Bool) {
        let d = hypot(bounds.width, bounds.height)
        let g = CAGradientLayer()
        g.type = .conic
        g.colors = (colors + [colors[0]]).map(\.cgColor)
        g.startPoint = CGPoint(x: 0.5, y: 0.5)
        g.endPoint = CGPoint(x: 0.5, y: 0)
        g.bounds = CGRect(x: 0, y: 0, width: d, height: d)
        g.position = CGPoint(x: bounds.midX, y: bounds.midY)
        container.addSublayer(g)
        if animated { g.add(spin(duration: (2 * .pi) / speed), forKey: "spin") }
    }

    private func buildWaves(_ colors: [RGBA], speed: Double, animated: Bool) {
        let w = bounds.width, h = bounds.height
        for (i, c) in colors.enumerated() {
            let fi = CGFloat(i)
            let base = h * (0.35 + 0.18 * fi)
            // A wave twice as wide as the view, slid sideways by one wavelength so it loops seamlessly.
            let wavelength = 260 + 60 * fi
            let width = w + wavelength * 2
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: 0))
            var x: CGFloat = 0
            while x <= width {
                path.addLine(to: CGPoint(x: x, y: base + 34 * sin(x / wavelength * 2 * .pi)))
                x += 8
            }
            path.addLine(to: CGPoint(x: width, y: 0))
            path.closeSubpath()
            let shape = CAShapeLayer()
            shape.path = path
            shape.frame = CGRect(x: 0, y: 0, width: width, height: h)
            let mask = shape
            let g = CAGradientLayer()
            g.colors = [c.withAlpha(0).cgColor, c.withAlpha(0.7).cgColor]
            g.startPoint = CGPoint(x: 0.5, y: 0)
            g.endPoint = CGPoint(x: 0.5, y: min(1, (base + 40) / max(1, h)))
            g.frame = CGRect(x: -wavelength, y: 0, width: width, height: h)
            g.mask = mask
            container.addSublayer(g)
            if animated {
                let slide = CABasicAnimation(keyPath: "position.x")
                slide.byValue = wavelength * (i % 2 == 0 ? 1 : -1)
                slide.duration = 1 / ((1.2 + 0.3 * Double(fi)) * speed) * 2 * .pi / 2
                slide.repeatCount = .infinity
                g.add(slide, forKey: "slide")
            }
        }
    }

    private func spin(duration: Double) -> CABasicAnimation {
        let a = CABasicAnimation(keyPath: "transform.rotation.z")
        a.fromValue = 0
        a.toValue = 2 * Double.pi
        a.duration = duration
        a.repeatCount = .infinity
        return a
    }
}

struct GradientLayerRepresentable: NSViewRepresentable {
    var config: GradientLayerView.Config

    func makeNSView(context: Context) -> GradientLayerView { GradientLayerView(frame: .zero) }

    func updateNSView(_ view: GradientLayerView, context: Context) {
        view.apply(config)
    }
}
