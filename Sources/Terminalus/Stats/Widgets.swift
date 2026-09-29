import SwiftUI
import TerminalusCore

/// The System panel's content (vertical) or the stats strip under the terminal (horizontal).
struct StatsPanelView: View {
    @Environment(\.ui) private var ui
    var horizontal = false
    var workspace: Workspace

    var body: some View {
        let widgets = AppState.shared.settings.stats.normalizedWidgets.filter(\.enabled)
        if horizontal {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(widgets) { w in
                        WidgetView(config: w, workspace: workspace, compact: true)
                            .frame(width: 200 * ui.scale)
                            .overlay(alignment: .trailing) { Rectangle().fill(ui.hairline).frame(width: 1) }
                    }
                }
            }
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(widgets) { w in
                        WidgetView(config: w, workspace: workspace, compact: false)
                    }
                }
            }
        }
    }
}

struct WidgetView: View {
    @Environment(\.ui) private var ui
    let config: WidgetConfig
    let workspace: Workspace
    let compact: Bool

    var body: some View {
        let stats = AppState.shared.stats
        let snap = stats.snapshot
        let color = widgetColor
        let s = AppState.shared.settings.stats
        if config.kind == .battery && snap.battery == nil {
            EmptyView()
        } else {
            Card(padding: compact ? 7 : 9) {
                VStack(alignment: .leading, spacing: 6 * ui.scale) {
                    if s.showWidgetHeaders {
                        HStack(spacing: 6) {
                            if s.showWidgetIcons {
                                Image(systemName: config.kind.symbol).font(.system(size: 10)).foregroundStyle(ui.secondary)
                            }
                            Text(title).font(ui.sectionFont).foregroundStyle(ui.secondary)
                            Spacer(minLength: 4)
                            headerValue(snap)
                                .font(ui.mono(-1, weight: .medium))
                                .foregroundStyle(ui.text)
                        }
                        .lineLimit(1)
                    }
                    content(stats: stats, snap: snap, color: color)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var title: String {
        switch config.kind {
        case .session: "Shell"
        case .cpu: "CPU"
        case .cores: "Cores"
        case .memory: "Memory"
        case .gpu: "GPU"
        case .network: "Network"
        case .disk: "Disk"
        case .processes: "Processes"
        case .system: "This Mac"
        case .thermal: "Thermal"
        case .clock: "Time"
        case .battery: "Battery"
        case .temperatures: "Temperatures"
        }
    }

    private var chartHeight: CGFloat {
        let base: CGFloat = compact ? 30 : 38
        switch config.size {
        case .compact: return base * 0.7 * ui.scale
        case .regular: return base * ui.scale
        case .large: return base * 1.8 * ui.scale
        }
    }

    /// One accent for data unless "colorful charts" is on or the widget has its own color.
    private var widgetColor: Color {
        if let hex = config.color, let c = RGBA(hex: hex) { return c.color }
        guard AppState.shared.settings.stats.colorfulCharts else { return ui.accent }
        let p = ui.theme.chartPalette
        switch config.kind {
        case .session, .clock: return ui.accent
        case .cpu: return p[0].color
        case .cores, .network: return p[1].color
        case .memory, .thermal, .battery: return p[2].color
        case .gpu: return p[6].color
        case .disk: return p[3].color
        case .processes, .system: return p[4].color
        case .temperatures: return p[5].color
        }
    }

    private var secondaryColor: Color { AppState.shared.settings.stats.colorfulCharts ? ui.accent2 : ui.secondary }

    @ViewBuilder
    private func headerValue(_ s: SystemSnapshot) -> some View {
        switch config.kind {
        case .cpu: Text(s.cpu.map { Fmt.percent($0.total) } ?? "–")
        case .memory: Text(s.memory.map { "\(Fmt.bytes($0.used, decimals: 1)) / \(Fmt.bytes($0.total, decimals: 0))" } ?? "–")
        case .gpu: Text(s.gpu.map { Fmt.percent($0.utilization) } ?? "–")
        case .network: Text(s.network.map { "↓ " + Fmt.rate($0.downRate, unit: netUnit) } ?? "–")
        case .disk: Text(s.disk?.volumes.first.map { Fmt.bytes($0.available, decimals: 0) + " free" } ?? "–")
        case .thermal: Text(s.info.thermal.rawValue.capitalized)
        case .battery: Text(s.battery.map { Fmt.percent($0.percent) } ?? "")
        case .temperatures:
            Text(s.temperatures?.dieMax.map { Fmt.temperature($0, unit: AppState.shared.settings.stats.temperatureUnit) } ?? "–")
        case .processes: Text("\(s.info.processCount)")
        case .cores: Text("\(s.info.performanceCores)P · \(s.info.efficiencyCores)E")
        case .session, .system, .clock: EmptyView()
        }
    }

    private var netUnit: NetworkUnit { AppState.shared.settings.stats.networkUnit }

    private func history(_ r: RingBuffer<Double>) -> [Double] {
        Array(r.elements.suffix(max(2, config.history)))
    }

    @ViewBuilder
    private func content(stats: StatsStore, snap: SystemSnapshot, color: Color) -> some View {
        switch config.kind {
        case .session: SessionWidget(workspace: workspace, stats: stats.session, compact: compact)
        case .cpu: cpuContent(snap, stats: stats, color: color)
        case .cores: coresContent(snap, stats: stats, color: color)
        case .memory: memoryContent(snap, stats: stats, color: color)
        case .gpu: gpuContent(snap, stats: stats, color: color)
        case .network: networkContent(snap, stats: stats, color: color)
        case .disk: diskContent(snap, stats: stats, color: color)
        case .processes: processesContent(snap, color: color)
        case .system: systemContent(snap)
        case .thermal: thermalContent(snap)
        case .clock: ClockWidget(compact: compact)
        case .battery: batteryContent(snap, color: color)
        case .temperatures: temperatureContent(snap, stats: stats, color: color)
        }
    }

    private func caption(_ s: String) -> some View {
        Text(s).font(ui.font(-2)).foregroundStyle(ui.secondary).lineLimit(1)
    }

    @ViewBuilder
    private func metric(value: Double, label: String, sub: String?, hist: [Double], color: Color, segments: [(Double, Color)] = []) -> some View {
        switch config.style {
        case .ring:
            HStack(spacing: 10) {
                RingGauge(value: value, color: color, track: ui.track, lineWidth: compact ? 4 : 5, label: label, segments: segments)
                    .frame(width: chartHeight * 1.4, height: chartHeight * 1.4)
                VStack(alignment: .leading, spacing: 4) {
                    if !compact { Sparkline(values: hist, color: color, maxValue: 1).frame(height: chartHeight * 0.8) }
                    if let sub { caption(sub) }
                }
            }
        case .bar:
            VStack(alignment: .leading, spacing: 5) {
                BarGauge(segments: segments.isEmpty ? [(value, color)] : segments, track: ui.track, height: compact ? 4 : 5)
                if let sub { caption(sub) }
            }
        case .sparkline:
            VStack(alignment: .leading, spacing: 4) {
                Sparkline(values: hist, color: color, fill: false, maxValue: 1).frame(height: chartHeight)
                if let sub, !compact { caption(sub) }
            }
        case .area:
            VStack(alignment: .leading, spacing: 4) {
                Sparkline(values: hist, color: color, fill: true, maxValue: 1).frame(height: chartHeight)
                if let sub, !compact { caption(sub) }
            }
        case .number, .heatmap, .list:
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.system(size: compact ? 18 : 24, weight: .medium, design: .monospaced)).foregroundStyle(ui.text)
                if let sub { caption(sub) }
            }
        }
    }

    @ViewBuilder
    private func cpuContent(_ s: SystemSnapshot, stats: StatsStore, color: Color) -> some View {
        let c = s.cpu ?? CPUSample.empty
        let la = s.info.loadAverage.map { String(format: "%.2f", $0) }.joined(separator: " ")
        metric(value: c.total, label: Fmt.percent(c.total), sub: "user \(Fmt.percent(c.user)) · sys \(Fmt.percent(c.system)) · load \(la)",
               hist: history(stats.cpu), color: color,
               segments: config.style == .ring || config.style == .bar ? [(c.user, color), (c.system, color.opacity(0.45))] : [])
    }

    @ViewBuilder
    private func coresContent(_ s: SystemSnapshot, stats: StatsStore, color: Color) -> some View {
        let c = s.cpu ?? CPUSample.empty
        let kinds = c.coreKinds
        if config.style == .bar {
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(Array(c.perCore.enumerated()), id: \.offset) { i, v in
                    VStack(spacing: 2) {
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 1.5).fill(ui.track)
                            RoundedRectangle(cornerRadius: 1.5).fill(color.opacity(i < kinds.count && kinds[i] == .efficiency ? 0.55 : 1))
                                .frame(height: max(1, chartHeight * CGFloat(v)))
                        }
                        .frame(height: chartHeight)
                        Text(i < kinds.count ? (kinds[i] == .efficiency ? "E" : "P") : "").font(.system(size: 7)).foregroundStyle(ui.tertiary)
                    }
                }
            }
        } else {
            let rows = stats.cores.map { Array($0.elements.suffix(max(10, min(120, config.history)))) }
            let eCount = kinds.filter { $0 == .efficiency }.count
            let rowH: CGFloat = compact ? 4 : 6
            let height = max(chartHeight, CGFloat(rows.count) * (rowH + 1))
            HStack(alignment: .top, spacing: 6) {
                VStack(alignment: .leading, spacing: 0) {
                    if eCount > 0 {
                        Text("E").frame(height: height * CGFloat(eCount) / CGFloat(max(1, rows.count)), alignment: .center)
                    }
                    if rows.count > eCount {
                        Text("P").frame(height: height * CGFloat(rows.count - eCount) / CGFloat(max(1, rows.count)), alignment: .center)
                    }
                }
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundStyle(ui.tertiary)
                Heatmap(rows: rows, low: ui.theme.sidebarBackground, high: color.rgba)
                    .frame(height: height)
            }
        }
    }

    @ViewBuilder
    private func memoryContent(_ s: SystemSnapshot, stats: StatsStore, color: Color) -> some View {
        let m = s.memory ?? MemorySample.empty
        let t = Double(max(1, m.total))
        let segs: [(Double, Color)] = [(Double(m.app) / t, color), (Double(m.wired) / t, color.opacity(0.6)), (Double(m.compressed) / t, color.opacity(0.3))]
        VStack(alignment: .leading, spacing: 5) {
            metric(value: m.usedFraction, label: Fmt.percent(m.usedFraction), sub: nil,
                   hist: history(stats.memory), color: color, segments: config.style == .ring || config.style == .bar ? segs : [])
            if !compact {
                HStack(spacing: 10) {
                    legend("App", Fmt.bytes(m.app), color)
                    legend("Wired", Fmt.bytes(m.wired), color.opacity(0.6))
                    legend("Compr.", Fmt.bytes(m.compressed), color.opacity(0.3))
                }
                HStack(spacing: 10) {
                    legend("Swap", Fmt.bytes(m.swapUsed), nil)
                    legend("Pressure", m.pressure.rawValue.capitalized, nil,
                           valueColor: m.pressure == .normal ? nil : (m.pressure == .warning ? ui.theme.warning.color : ui.theme.danger.color))
                }
            }
        }
    }

    private func legend(_ name: String, _ value: String, _ c: Color?, valueColor: Color? = nil) -> some View {
        HStack(spacing: 4) {
            if let c { RoundedRectangle(cornerRadius: 1).fill(c).frame(width: 6, height: 6) }
            Text(name).foregroundStyle(ui.secondary)
            Text(value).font(ui.mono(-3)).foregroundStyle(valueColor ?? ui.text)
        }
        .font(ui.font(-2))
        .lineLimit(1)
    }

    @ViewBuilder
    private func gpuContent(_ s: SystemSnapshot, stats: StatsStore, color: Color) -> some View {
        if let g = s.gpu {
            metric(value: g.utilization, label: Fmt.percent(g.utilization),
                   sub: "\(g.name)\(g.cores > 0 ? " · \(g.cores) cores" : "") · \(Fmt.bytes(g.memoryUsed)) in use",
                   hist: history(stats.gpu), color: color)
        } else {
            caption("GPU statistics unavailable")
        }
    }

    @ViewBuilder
    private func networkContent(_ s: SystemSnapshot, stats: StatsStore, color: Color) -> some View {
        let n = s.network ?? NetworkSample.empty
        VStack(alignment: .leading, spacing: 4) {
            if config.style != .number {
                DualAreaChart(a: history(stats.netDown), b: history(stats.netUp), colorA: color, colorB: secondaryColor)
                    .frame(height: chartHeight)
            }
            HStack {
                Text("↓ " + Fmt.rate(n.downRate, unit: netUnit))
                Spacer()
                Text("↑ " + Fmt.rate(n.upRate, unit: netUnit)).foregroundStyle(ui.secondary)
            }
            .font(ui.mono(-2))
            if !compact {
                caption("\(n.primaryInterface ?? "–") · \(n.localIPv4 ?? "no IPv4") · ↓\(Fmt.bytes(n.totalDown, decimals: 0)) ↑\(Fmt.bytes(n.totalUp, decimals: 0))")
            }
        }
    }

    @ViewBuilder
    private func diskContent(_ s: SystemSnapshot, stats: StatsStore, color: Color) -> some View {
        let d = s.disk ?? DiskSample.empty
        VStack(alignment: .leading, spacing: 6) {
            ForEach(d.volumes.prefix(compact ? 1 : 4)) { v in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(v.name).lineLimit(1)
                        Spacer()
                        Text("\(Fmt.bytes(v.used, decimals: 0)) of \(Fmt.bytes(v.total, decimals: 0))").font(ui.mono(-3)).foregroundStyle(ui.secondary)
                    }
                    .font(ui.font(-2))
                    BarGauge(segments: [(v.usedFraction, v.usedFraction > 0.92 ? ui.theme.danger.color : color)], track: ui.track, height: 4)
                }
            }
            HStack(spacing: 10) {
                Text("R " + Fmt.rate(d.readRate))
                Text("W " + Fmt.rate(d.writeRate)).foregroundStyle(ui.secondary)
                Spacer()
            }
            .font(ui.mono(-2))
        }
    }

    @ViewBuilder
    private func processesContent(_ s: SystemSnapshot, color: Color) -> some View {
        let list = s.processes ?? []
        VStack(alignment: .leading, spacing: 3) {
            ForEach(list.prefix(compact ? 3 : 20)) { p in
                HStack(spacing: 6) {
                    Text(p.name).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 4)
                    Text(String(format: "%.1f%%", p.cpu)).font(ui.mono(-2)).foregroundStyle(p.cpu > 50 ? color : ui.text)
                    if !compact {
                        Text(Fmt.bytes(p.memory, decimals: 0)).font(ui.mono(-2)).foregroundStyle(ui.secondary)
                            .frame(width: 56, alignment: .trailing)
                    }
                }
                .font(ui.font(-1))
                .help("PID \(p.pid)")
            }
            if list.isEmpty { caption("Sampling…") }
        }
    }

    @ViewBuilder
    private func systemContent(_ s: SystemSnapshot) -> some View {
        let i = s.info
        VStack(alignment: .leading, spacing: 3) {
            Text(i.modelName).font(ui.font(0, weight: .medium))
            row("Chip", i.chip)
            row("macOS", i.osVersion.replacingOccurrences(of: "macOS ", with: ""))
            if !compact {
                row("Cores", "\(i.logicalCPUs) (\(i.performanceCores)P + \(i.efficiencyCores)E)")
                row("Memory", Fmt.bytes(i.memoryTotal, decimals: 0))
                row("Host", i.hostname)
                row("Load", i.loadAverage.map { String(format: "%.2f", $0) }.joined(separator: "  "))
            }
            row("Uptime", Fmt.duration(i.uptime))
        }
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(k).foregroundStyle(ui.secondary)
            Spacer(minLength: 6)
            Text(v).lineLimit(1).truncationMode(.middle)
        }
        .font(ui.font(-2))
    }

    @ViewBuilder
    private func thermalContent(_ s: SystemSnapshot) -> some View {
        let t = s.info.thermal
        let c: Color = switch t {
        case .nominal: ui.secondary
        case .fair: ui.theme.warning.color
        case .serious, .critical: ui.theme.danger.color
        }
        HStack(spacing: 6) {
            Circle().fill(c).frame(width: 6, height: 6)
            Text(t == .nominal ? "Nominal — no throttling" : t.rawValue.capitalized)
                .font(ui.font(-1)).foregroundStyle(t == .nominal ? ui.secondary : c)
        }
    }

    @ViewBuilder
    private func batteryContent(_ s: SystemSnapshot, color: Color) -> some View {
        if let b = s.battery {
            let sub = b.isCharging ? "Charging" : (b.onAC ? "On power" : b.timeRemaining.map { "\(Fmt.duration(Double($0) * 60)) left" } ?? "On battery")
            metric(value: b.percent, label: Fmt.percent(b.percent), sub: sub, hist: [], color: b.percent < 0.2 ? ui.theme.danger.color : color)
        }
    }

    @ViewBuilder
    private func temperatureContent(_ s: SystemSnapshot, stats: StatsStore, color: Color) -> some View {
        let unit = AppState.shared.settings.stats.temperatureUnit
        if let t = s.temperatures, t.available {
            VStack(alignment: .leading, spacing: 3) {
                Sparkline(values: history(stats.temperature), color: color, maxValue: 110).frame(height: chartHeight * 0.8)
                row("Average", t.dieAverage.map { Fmt.temperature($0, unit: unit) } ?? "–")
                if !compact {
                    ForEach(t.sensors.sorted { $0.celsius > $1.celsius }.prefix(config.size == .large ? 16 : 5)) { sensor in
                        row(sensor.name, Fmt.temperature(sensor.celsius, unit: unit))
                    }
                }
            }
        } else {
            caption(s.temperatures == nil ? "Sampling…" : "No temperature sensors available")
        }
    }
}

struct ClockWidget: View {
    @Environment(\.ui) private var ui
    var compact: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let h24 = AppState.shared.settings.stats.clock24h
            VStack(alignment: .leading, spacing: 1) {
                Text(ctx.date, format: .dateTime.hour(h24 ? .twoDigits(amPM: .omitted) : .defaultDigits(amPM: .abbreviated)).minute().second())
                    .font(.system(size: compact ? 18 : 22, weight: .medium, design: .monospaced))
                Text(ctx.date, format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(ui.font(-2)).foregroundStyle(ui.secondary)
            }
        }
    }
}

/// What the focused shell is doing.
struct SessionWidget: View {
    @Environment(\.ui) private var ui
    let workspace: Workspace
    let stats: SessionProcessStats
    let compact: Bool

    var body: some View {
        if let s = workspace.focusedSession {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(s.shellName).font(ui.font(-1, weight: .medium))
                    Text("pid \(s.shellPid)").font(ui.mono(-3)).foregroundStyle(ui.secondary)
                    if !s.integrationActive {
                        Text("polling").font(ui.font(-3)).foregroundStyle(ui.tertiary)
                            .help("No shell integration: the directory is read from the process instead")
                    }
                    Spacer()
                    Text("\(s.cols)×\(s.rows)").font(ui.mono(-3)).foregroundStyle(ui.secondary)
                }

                if let cmd = s.runningCommand, let start = s.commandStartedAt {
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        HStack(spacing: 6) {
                            Text(cmd).lineLimit(1).truncationMode(.tail)
                            Spacer()
                            Text(Fmt.stopwatch(ctx.date.timeIntervalSince(start))).font(ui.mono(-2)).foregroundStyle(ui.accent)
                        }
                        .font(ui.font(-1))
                    }
                } else if let fg = s.foregroundProcess {
                    Text("Running \(fg)").font(ui.font(-1))
                } else if let last = s.lastCommand, !compact {
                    let ok = (s.lastExitCode ?? 0) == 0
                    HStack(spacing: 6) {
                        Text(last).lineLimit(1).foregroundStyle(ui.secondary)
                        Spacer()
                        Text(ok ? "exit 0" : "exit \(s.lastExitCode ?? 0)")
                            .font(ui.mono(-3))
                            .foregroundStyle(ok ? ui.secondary : ui.theme.danger.color)
                        if let d = s.lastDuration, d >= 1 { Text(Fmt.duration(d)).font(ui.mono(-3)).foregroundStyle(ui.secondary) }
                    }
                    .font(ui.font(-1))
                } else {
                    Text("Idle").font(ui.font(-1)).foregroundStyle(ui.secondary)
                }

                if !compact {
                    HStack(spacing: 8) {
                        Text("\(stats.processCount) proc")
                        Text(Fmt.bytes(stats.rss, decimals: 0))
                        Text(String(format: "%.0f%% CPU", stats.cpuPercent))
                        Spacer()
                        TimelineView(.periodic(from: .now, by: 1)) { ctx in
                            Text("up " + Fmt.duration(ctx.date.timeIntervalSince(s.startedAt)))
                        }
                    }
                    .font(ui.mono(-3))
                    .foregroundStyle(ui.secondary)
                }
            }
        } else {
            Text("No session").font(ui.font(-2)).foregroundStyle(ui.secondary)
        }
    }
}
