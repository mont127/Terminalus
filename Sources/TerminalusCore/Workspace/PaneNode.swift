import Foundation

public enum SplitAxis: String, Codable, Sendable {
    /// Children side by side (divider is vertical).
    case horizontal
    /// Children stacked (divider is horizontal).
    case vertical
}

public enum PaneDirection: Sendable {
    case left, right, up, down
}

/// Immutable split tree. Leaves hold pane (session) ids.
public indirect enum PaneNode: Equatable, Sendable {
    case leaf(String)
    case split(axis: SplitAxis, fraction: Double, first: PaneNode, second: PaneNode)

    public var leaves: [String] {
        switch self {
        case .leaf(let id): [id]
        case .split(_, _, let a, let b): a.leaves + b.leaves
        }
    }

    public func contains(_ id: String) -> Bool { leaves.contains(id) }

    /// Replaces leaf `id` with a split of it and `newID`.
    public func splitting(_ id: String, with newID: String, axis: SplitAxis, newFirst: Bool = false) -> PaneNode {
        switch self {
        case .leaf(let l):
            guard l == id else { return self }
            return newFirst
                ? .split(axis: axis, fraction: 0.5, first: .leaf(newID), second: .leaf(l))
                : .split(axis: axis, fraction: 0.5, first: .leaf(l), second: .leaf(newID))
        case .split(let ax, let f, let a, let b):
            return .split(axis: ax, fraction: f, first: a.splitting(id, with: newID, axis: axis, newFirst: newFirst),
                          second: b.splitting(id, with: newID, axis: axis, newFirst: newFirst))
        }
    }

    /// Removes leaf `id`; its sibling takes the parent's place. Returns nil if the tree becomes empty.
    public func removing(_ id: String) -> PaneNode? {
        switch self {
        case .leaf(let l):
            return l == id ? nil : self
        case .split(let ax, let f, let a, let b):
            let na = a.removing(id), nb = b.removing(id)
            switch (na, nb) {
            case (nil, nil): return nil
            case (let x?, nil): return x
            case (nil, let y?): return y
            case (let x?, let y?): return .split(axis: ax, fraction: f, first: x, second: y)
            }
        }
    }

    /// Sets the fraction of the split whose first subtree's leaves start with `firstLeaf`… identified by path.
    public func settingFraction(at path: [Bool], to fraction: Double) -> PaneNode {
        switch self {
        case .leaf:
            return self
        case .split(let ax, let f, let a, let b):
            guard let head = path.first else {
                return .split(axis: ax, fraction: min(0.9, max(0.1, fraction)), first: a, second: b)
            }
            let rest = Array(path.dropFirst())
            return head
                ? .split(axis: ax, fraction: f, first: a, second: b.settingFraction(at: rest, to: fraction))
                : .split(axis: ax, fraction: f, first: a.settingFraction(at: rest, to: fraction), second: b)
        }
    }

    public func equalized() -> PaneNode {
        switch self {
        case .leaf: self
        case .split(let ax, _, let a, let b): .split(axis: ax, fraction: 0.5, first: a.equalized(), second: b.equalized())
        }
    }

    /// Normalized rectangles (0…1) of every leaf.
    public func layout(in rect: PaneRect = PaneRect(x: 0, y: 0, w: 1, h: 1)) -> [String: PaneRect] {
        switch self {
        case .leaf(let id):
            return [id: rect]
        case .split(let ax, let f, let a, let b):
            let (ra, rb): (PaneRect, PaneRect)
            if ax == .horizontal {
                ra = PaneRect(x: rect.x, y: rect.y, w: rect.w * f, h: rect.h)
                rb = PaneRect(x: rect.x + rect.w * f, y: rect.y, w: rect.w * (1 - f), h: rect.h)
            } else {
                ra = PaneRect(x: rect.x, y: rect.y, w: rect.w, h: rect.h * f)
                rb = PaneRect(x: rect.x, y: rect.y + rect.h * f, w: rect.w, h: rect.h * (1 - f))
            }
            return a.layout(in: ra).merging(b.layout(in: rb)) { x, _ in x }
        }
    }

    /// The nearest leaf in `direction` from leaf `id` (y grows downward).
    public func neighbor(of id: String, _ direction: PaneDirection) -> String? {
        let rects = layout()
        guard let r = rects[id] else { return nil }
        let eps = 1e-6
        let candidates = rects.filter { key, o in
            guard key != id else { return false }
            switch direction {
            case .left: return abs(o.x + o.w - r.x) < eps && o.y < r.y + r.h - eps && o.y + o.h > r.y + eps
            case .right: return abs(r.x + r.w - o.x) < eps && o.y < r.y + r.h - eps && o.y + o.h > r.y + eps
            case .up: return abs(o.y + o.h - r.y) < eps && o.x < r.x + r.w - eps && o.x + o.w > r.x + eps
            case .down: return abs(r.y + r.h - o.y) < eps && o.x < r.x + r.w - eps && o.x + o.w > r.x + eps
            }
        }
        // Prefer the candidate whose center is closest along the perpendicular axis.
        return candidates.min { a, b in
            let da: Double, db: Double
            switch direction {
            case .left, .right:
                da = abs((a.value.y + a.value.h / 2) - (r.y + r.h / 2))
                db = abs((b.value.y + b.value.h / 2) - (r.y + r.h / 2))
            case .up, .down:
                da = abs((a.value.x + a.value.w / 2) - (r.x + r.w / 2))
                db = abs((b.value.x + b.value.w / 2) - (r.x + r.w / 2))
            }
            return da < db
        }?.key
    }
}

public struct PaneRect: Equatable, Sendable {
    public var x, y, w, h: Double
    public init(x: Double, y: Double, w: Double, h: Double) {
        self.x = x; self.y = y; self.w = w; self.h = h
    }
}
