import AppKit
import Observation
import TerminalusCore

/// Stats about the focused terminal session's process tree.
struct SessionProcessStats: Equatable {
    var processCount = 0
    var rss: UInt64 = 0
    var cpuPercent: Double = 0
}

/// Latest system snapshot plus rolling histories for charts. Only the stats views read this, so the
/// once-per-interval updates never invalidate the terminal area.
@MainActor
@Observable
final class StatsStore {
    static let historyCapacity = 600

    private(set) var snapshot = SystemSnapshot()
    private(set) var tick = 0
    private(set) var session = SessionProcessStats()

    @ObservationIgnored private(set) var cpu = RingBuffer<Double>(capacity: historyCapacity)
    @ObservationIgnored private(set) var cores: [RingBuffer<Double>] = []
    @ObservationIgnored private(set) var memory = RingBuffer<Double>(capacity: historyCapacity)
    @ObservationIgnored private(set) var gpu = RingBuffer<Double>(capacity: historyCapacity)
    @ObservationIgnored private(set) var netDown = RingBuffer<Double>(capacity: historyCapacity)
    @ObservationIgnored private(set) var netUp = RingBuffer<Double>(capacity: historyCapacity)
    @ObservationIgnored private(set) var diskRead = RingBuffer<Double>(capacity: historyCapacity)
    @ObservationIgnored private(set) var diskWrite = RingBuffer<Double>(capacity: historyCapacity)
    @ObservationIgnored private(set) var temperature = RingBuffer<Double>(capacity: historyCapacity)

    @ObservationIgnored private var sampler: SystemSampler?
    @ObservationIgnored private var config: SystemSampler.Config?
    @ObservationIgnored private var paused = false
    @ObservationIgnored private var sessionCPUPrev: (seconds: Double, at: Date, pid: pid_t)?

    func configure(settings: AppSettings) {
        let s = settings.stats
        var enabled = Set(s.normalizedWidgets.filter(\.enabled).map(\.kind))
        if settings.layout.side(of: PanelID.system) == nil && !settings.layout.statsStrip { enabled = [] }
        let cfg = SystemSampler.Config(interval: max(0.25, s.refreshInterval), enabled: enabled, processBackend: s.processBackend,
                                       processCount: max(1, s.processCount), processSort: s.processSort)
        guard cfg != config else { return }
        config = cfg
        if let sampler {
            sampler.update(cfg)
        } else {
            let smp = SystemSampler(config: cfg) { snap in
                DispatchQueue.main.async { AppState.shared.stats.ingest(snap) }
            }
            sampler = smp
            smp.start()
        }
    }

    /// Stops sampling while no terminal window is visible.
    func windowVisibilityChanged() {
        let anyVisible = AppState.shared.windowControllers.contains { $0.isVisibleOnScreen }
        if anyVisible && paused {
            paused = false
            sampler?.start()
        } else if !anyVisible && !paused {
            paused = true
            sampler?.stop()
        }
    }

    private func ingest(_ s: SystemSnapshot) {
        if let c = s.cpu {
            cpu.append(c.total)
            if cores.count != c.perCore.count {
                cores = c.perCore.map { _ in RingBuffer<Double>(capacity: 120) }
            }
            for (i, v) in c.perCore.enumerated() { cores[i].append(v) }
        }
        if let m = s.memory { memory.append(m.usedFraction) }
        if let g = s.gpu { gpu.append(g.utilization) }
        if let n = s.network {
            netDown.append(n.downRate)
            netUp.append(n.upRate)
        }
        if let d = s.disk {
            diskRead.append(d.readRate)
            diskWrite.append(d.writeRate)
        }
        if let t = s.temperatures, let m = t.dieMax { temperature.append(m) }
        snapshot = s
        updateSessionStats()
        tick &+= 1
        AppState.shared.statsTicked()
    }

    private func updateSessionStats() {
        guard let sess = AppState.shared.activeWorkspace?.focusedSession, sess.view.isRunning else {
            if session != SessionProcessStats() { session = SessionProcessStats() }
            return
        }
        let root = sess.shellPid
        var stack = [root]
        var seen = Set<pid_t>()
        var st = SessionProcessStats()
        var cpuSeconds = 0.0
        while let pid = stack.popLast(), seen.count < 512 {
            guard !seen.contains(pid) else { continue }
            seen.insert(pid)
            if let ti = ProcessInspector.taskInfo(of: pid) {
                st.processCount += 1
                st.rss += ti.rss
                cpuSeconds += ti.cpuSeconds
            }
            stack.append(contentsOf: ProcessInspector.children(of: pid))
        }
        let now = Date()
        if let prev = sessionCPUPrev, prev.pid == root, cpuSeconds >= prev.seconds {
            st.cpuPercent = (cpuSeconds - prev.seconds) / max(0.01, now.timeIntervalSince(prev.at)) * 100
        }
        sessionCPUPrev = (cpuSeconds, now, root)
        if st != session { session = st }
    }
}
