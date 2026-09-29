import SwiftUI
import TerminalusCore

/// Circular gauge.
struct RingGauge: View {
    @Environment(\.ui) private var ui
    var value: Double
    var color: Color
    var track: Color
    var lineWidth: CGFloat = 5
    var label: String
    var sublabel: String? = nil
    var segments: [(Double, Color)] = []

    var body: some View {
        let glow = ui.stats.chartGlow
        ZStack {
            Circle().stroke(track, lineWidth: lineWidth)
            if segments.isEmpty {
                Circle()
                    .trim(from: 0, to: max(0.001, min(1, value)))
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: glow ? color.opacity(0.7) : .clear, radius: glow ? 4 : 0)
            } else {
                ForEach(Array(segmentRanges.enumerated()), id: \.offset) { _, seg in
                    Circle()
                        .trim(from: seg.0, to: seg.1)
                        .stroke(seg.2, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                        .rotationEffect(.degrees(-90))
                }
            }
            VStack(spacing: 0) {
                Text(label).font(.system(size: max(10, lineWidth * 2.3), weight: .medium, design: .monospaced))
                if let s = sublabel {
                    Text(s).font(.system(size: 8)).foregroundStyle(ui.secondary)
                }
            }
            .minimumScaleFactor(0.5)
            .lineLimit(1)
            .padding(lineWidth)
        }
    }

    private var segmentRanges: [(Double, Double, Color)] {
        var start = 0.0
        var out: [(Double, Double, Color)] = []
        for (v, c) in segments {
            let end = min(1, start + max(0, v))
            if end > start { out.append((start, end, c)) }
            start = end
        }
        return out
    }
}

/// Horizontal bar, optionally stacked.
struct BarGauge: View {
    @Environment(\.ui) private var ui
    var segments: [(Double, Color)]
    var track: Color
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: height / 2).fill(track)
                HStack(spacing: 0) {
                    ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                        Rectangle()
                            .fill(seg.1)
                            .frame(width: max(0, geo.size.width * CGFloat(min(1, max(0, seg.0)))))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: height / 2))
            }
        }
        .frame(height: height)
    }
}

/// Line (optionally filled) chart of recent values, drawn with Canvas.
struct Sparkline: View {
    @Environment(\.ui) private var ui
    var values: [Double]
    var color: Color
    var fill: Bool = true
    var maxValue: Double? = nil
    var lineWidth: CGFloat = 1.25

    var body: some View {
        let glow = ui.stats.chartGlow
        Canvas { ctx, size in
            guard values.count > 1 else { return }
            let top = max(maxValue ?? (values.max() ?? 1), 0.000_001)
            let step = size.width / CGFloat(max(1, values.count - 1))
            var path = Path()
            for (i, v) in values.enumerated() {
                let p = CGPoint(x: CGFloat(i) * step, y: size.height - CGFloat(min(1, max(0, v / top))) * (size.height - lineWidth) - lineWidth / 2)
                if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            if fill {
                var area = path
                area.addLine(to: CGPoint(x: size.width, y: size.height))
                area.addLine(to: CGPoint(x: 0, y: size.height))
                area.closeSubpath()
                ctx.fill(area, with: .linearGradient(Gradient(colors: [color.opacity(0.22), color.opacity(0.0)]),
                                                     startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            }
            var g = ctx
            if glow { g.addFilter(.shadow(color: color.opacity(0.9), radius: 3)) }
            g.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        }
    }
}

/// Two overlapping series (e.g. network down/up) sharing one scale.
struct DualAreaChart: View {
    var a: [Double]
    var b: [Double]
    var colorA: Color
    var colorB: Color

    var body: some View {
        let top = max(a.max() ?? 0, b.max() ?? 0, 1)
        ZStack {
            Sparkline(values: a, color: colorA, fill: true, maxValue: top)
            Sparkline(values: b, color: colorB, fill: false, maxValue: top)
        }
    }
}

/// Grid of cells: rows × columns of 0…1 values, colored along a gradient.
struct Heatmap: View {
    var rows: [[Double]]
    var low: RGBA
    var high: RGBA
    var spacing: CGFloat = 1

    var body: some View {
        Canvas { ctx, size in
            guard !rows.isEmpty else { return }
            let cols = rows.map(\.count).max() ?? 0
            guard cols > 0 else { return }
            let ch = (size.height - spacing * CGFloat(rows.count - 1)) / CGFloat(rows.count)
            let cw = (size.width - spacing * CGFloat(cols - 1)) / CGFloat(cols)
            for (r, row) in rows.enumerated() {
                let offset = cols - row.count
                for (c, v) in row.enumerated() {
                    let rect = CGRect(x: CGFloat(c + offset) * (cw + spacing), y: CGFloat(r) * (ch + spacing), width: cw, height: ch)
                    let t = min(1, max(0, v))
                    ctx.fill(Path(roundedRect: rect, cornerRadius: min(1.5, ch / 3)), with: .color(low.mix(high, t).withAlpha(0.25 + 0.75 * t).color))
                }
            }
        }
    }
}
