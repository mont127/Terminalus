import AppKit
import QuartzCore
import TerminalusCore

/// Hosts one terminal view with padding, the text glow (a layer shadow — TerminalView clips its own
/// layer, so the shadow must live on this container) and the inactive-pane dimming overlay.
final class TerminalContainerView: NSView {
    let terminal: TerminalusTerminalView
    /// Holds only the terminal so the glow shadow is cast by text alone (not by the dim overlay).
    private let glowHost = GlowHostView()
    private let dimView = PassthroughView()
    private let focusBorder = PassthroughView()

    var padding: CGFloat = 10 {
        didSet { if padding != oldValue { needsLayout = true } }
    }

    /// Called once, after the first layout in a window, when the terminal has its real size.
    var onFirstLayout: (() -> Void)?

    init(terminal: TerminalusTerminalView) {
        self.terminal = terminal
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false
        glowHost.wantsLayer = true
        glowHost.layer?.masksToBounds = false
        glowHost.addSubview(terminal)
        addSubview(glowHost)
        dimView.wantsLayer = true
        dimView.layer?.backgroundColor = NSColor.black.cgColor
        dimView.alphaValue = 0
        addSubview(dimView)
        focusBorder.wantsLayer = true
        focusBorder.layer?.borderWidth = 1
        focusBorder.layer?.cornerRadius = 6
        focusBorder.alphaValue = 0
        addSubview(focusBorder)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        glowHost.frame = bounds
        let inset = bounds.insetBy(dx: padding, dy: padding * 0.6)
        if terminal.frame != inset { terminal.frame = inset }
        dimView.frame = bounds
        focusBorder.frame = bounds.insetBy(dx: 1, dy: 1)
        if let cb = onFirstLayout, window != nil, inset.width > 40, inset.height > 20 {
            onFirstLayout = nil
            DispatchQueue.main.async(execute: cb)
        }
    }

    func applyGlow(enabled: Bool, color: RGBA, radius: Double, opacity: Double) {
        // NSView.shadow (not raw layer properties, which AppKit resets on layer-backed views).
        if enabled && radius > 0 && opacity > 0 {
            let sh = NSShadow()
            sh.shadowColor = color.withAlpha(min(1, max(0, opacity))).nsColor
            sh.shadowBlurRadius = CGFloat(radius)
            sh.shadowOffset = .zero
            glowHost.shadow = sh
        } else {
            glowHost.shadow = nil
        }
    }

    /// Dims the pane when it is not focused (only meaningful with splits).
    func setDim(_ amount: CGFloat, focusColor: NSColor?, animated: Bool) {
        let apply = {
            self.dimView.animator().alphaValue = amount
            self.focusBorder.animator().alphaValue = focusColor == nil ? 0 : 0.8
        }
        focusBorder.layer?.borderColor = focusColor?.cgColor
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                apply()
            }
        } else {
            dimView.alphaValue = amount
            focusBorder.alphaValue = focusColor == nil ? 0 : 0.8
        }
    }
}

private final class GlowHostView: NSView {
    override var isFlipped: Bool { true }
}

/// A view that never receives mouse events.
class PassthroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

