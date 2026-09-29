import AppKit
import SwiftUI
import TerminalusCore

/// Lays out the terminal panes of one tab from its split tree, draws/drags the dividers and hosts
/// the effects overlay. Pure AppKit so terminal views are re-parented, never recreated.
final class PaneAreaView: NSView {
    struct Style: Equatable {
        var dividerWidth: CGFloat = 2
        var dividerColor: RGBA = .white
        var accent: RGBA = .white
        var dimAmount: CGFloat = 0.25
    }

    private var root: PaneNode?
    private var zoomed: String?
    private var focused: String?
    private var style = Style()
    private var containers: [String: TerminalContainerView] = [:]
    let effects = EffectsOverlayView()

    var onResize: (([Bool], Double) -> Void)?

    private struct Divider {
        var rect: NSRect
        var axis: SplitAxis
        var path: [Bool]
        var splitRect: NSRect
    }
    private var dividers: [Divider] = []
    private var dragging: Divider?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        addSubview(effects)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var isFlipped: Bool { true }

    func update(root: PaneNode?, sessions: [String: TerminalSession], focused: String?, zoomed: String?, style: Style) {
        let layoutChanged = root != self.root || zoomed != self.zoomed
        let styleChanged = style != self.style
        let focusChanged = focused != self.focused
        self.root = root
        self.zoomed = zoomed
        self.focused = focused
        self.style = style

        let visible: [String] = {
            guard let root else { return [] }
            if let z = zoomed, root.contains(z) { return [z] }
            return root.leaves
        }()
        var next: [String: TerminalContainerView] = [:]
        for id in visible {
            guard let s = sessions[id] else { continue }
            next[id] = s.container
        }
        for (id, c) in containers where next[id] !== c {
            if c.superview === self { c.removeFromSuperview() }
        }
        for (_, c) in next where c.superview !== self {
            c.removeFromSuperview()
            addSubview(c, positioned: .below, relativeTo: effects)
        }
        containers = next
        if layoutChanged || styleChanged { needsLayout = true; needsDisplay = true }
        if focusChanged || styleChanged || layoutChanged { updateDimming(animated: focusChanged && !layoutChanged) }
    }

    private func updateDimming(animated: Bool) {
        let multiple = containers.count > 1
        for (id, c) in containers {
            let isFocused = id == focused
            c.setDim(multiple && !isFocused ? style.dimAmount : 0,
                     focusColor: multiple && isFocused && style.dimAmount == 0 ? style.accent.withAlpha(0.6).nsColor : nil,
                     animated: animated)
        }
    }

    override func layout() {
        super.layout()
        effects.frame = bounds
        dividers = []
        guard let root else { return }
        if let z = zoomed, let c = containers[z] {
            c.frame = bounds
            window?.invalidateCursorRects(for: self)
            return
        }
        layoutNode(root, in: bounds, path: [])
        window?.invalidateCursorRects(for: self)
    }

    private func layoutNode(_ node: PaneNode, in rect: NSRect, path: [Bool]) {
        switch node {
        case .leaf(let id):
            containers[id]?.frame = rect.integral
        case .split(let axis, let f, let a, let b):
            let dw = style.dividerWidth
            if axis == .horizontal {
                let w1 = (rect.width - dw) * CGFloat(f)
                let r1 = NSRect(x: rect.minX, y: rect.minY, width: w1, height: rect.height)
                let d = NSRect(x: r1.maxX, y: rect.minY, width: dw, height: rect.height)
                let r2 = NSRect(x: d.maxX, y: rect.minY, width: rect.maxX - d.maxX, height: rect.height)
                dividers.append(Divider(rect: d, axis: axis, path: path, splitRect: rect))
                layoutNode(a, in: r1, path: path + [false])
                layoutNode(b, in: r2, path: path + [true])
            } else {
                let h1 = (rect.height - dw) * CGFloat(f)
                let r1 = NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: h1)
                let d = NSRect(x: rect.minX, y: r1.maxY, width: rect.width, height: dw)
                let r2 = NSRect(x: rect.minX, y: d.maxY, width: rect.width, height: rect.maxY - d.maxY)
                dividers.append(Divider(rect: d, axis: axis, path: path, splitRect: rect))
                layoutNode(a, in: r1, path: path + [false])
                layoutNode(b, in: r2, path: path + [true])
            }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !dividers.isEmpty, zoomed == nil else { return }
        style.dividerColor.nsColor.setFill()
        for d in dividers { d.rect.fill() }
    }

    // MARK: Divider dragging

    private func grabRect(_ d: Divider) -> NSRect {
        d.axis == .horizontal ? d.rect.insetBy(dx: -4, dy: 0) : d.rect.insetBy(dx: 0, dy: -4)
    }

    override func resetCursorRects() {
        for d in dividers where zoomed == nil {
            addCursorRect(grabRect(d), cursor: d.axis == .horizontal ? .resizeLeftRight : .resizeUpDown)
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        if zoomed == nil, dividers.contains(where: { grabRect($0).contains(local) }) { return self }
        return super.hitTest(point)
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        dragging = dividers.first { grabRect($0).contains(p) }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let d = dragging else { return }
        let p = convert(event.locationInWindow, from: nil)
        let f: Double
        if d.axis == .horizontal {
            f = Double((p.x - d.splitRect.minX) / max(1, d.splitRect.width))
        } else {
            f = Double((p.y - d.splitRect.minY) / max(1, d.splitRect.height))
        }
        onResize?(d.path, min(0.9, max(0.1, f)))
    }

    override func mouseUp(with event: NSEvent) {
        if event.clickCount == 2, let d = dragging { onResize?(d.path, 0.5) }
        dragging = nil
    }
}

/// SwiftUI wrapper. All inputs are plain values so SwiftUI re-runs `updateNSView` when they change.
struct PaneAreaRepresentable: NSViewRepresentable {
    var root: PaneNode?
    var sessions: [String: TerminalSession]
    var focused: String?
    var zoomed: String?
    var style: PaneAreaView.Style
    var effects: EffectsSettings
    var effectsTint: RGBA
    var effectsPaused: Bool
    var onResize: ([Bool], Double) -> Void

    func makeNSView(context: Context) -> PaneAreaView {
        PaneAreaView(frame: .zero)
    }

    func updateNSView(_ view: PaneAreaView, context: Context) {
        view.onResize = onResize
        view.update(root: root, sessions: sessions, focused: focused, zoomed: zoomed, style: style)
        view.effects.configure(effects, tint: effectsTint, paused: effectsPaused)
    }
}
