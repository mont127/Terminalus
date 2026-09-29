import Foundation

/// Samples the enabled metrics on a background queue and delivers snapshots on the main queue.
public final class SystemSampler: @unchecked Sendable {
    public struct Config: Equatable, Sendable {
        public var interval: TimeInterval
        public var enabled: Set<WidgetKind>
        public var processBackend: ProcessBackend
        public var processCount: Int
        public var processSort: ProcessSortKey

        public init(interval: TimeInterval, enabled: Set<WidgetKind>, processBackend: ProcessBackend,
                    processCount: Int, processSort: ProcessSortKey) {
            self.interval = interval; self.enabled = enabled; self.processBackend = processBackend
            self.processCount = processCount; self.processSort = processSort
        }
    }

    private let queue = DispatchQueue(label: "terminalus.sampler", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var config: Config
    private let onSnapshot: @Sendable (SystemSnapshot) -> Void

    private let cpu = CPUSampler()
    private let disk = DiskSampler()
    private let net = NetworkSampler()
    private lazy var gpu = GPUSampler()
    private let procs = ProcessSampler()
    private lazy var temps = TemperatureSampler()

    public init(config: Config, onSnapshot: @escaping @Sendable (SystemSnapshot) -> Void) {
        self.config = config
        self.onSnapshot = onSnapshot
    }

    public func start() {
        queue.async { self.reschedule(fireNow: true) }
    }

    public func stop() {
        queue.async {
            self.timer?.cancel()
            self.timer = nil
        }
    }

    public func update(_ newConfig: Config) {
        queue.async {
            let intervalChanged = newConfig.interval != self.config.interval
            self.config = newConfig
            if intervalChanged || self.timer == nil { self.reschedule(fireNow: true) }
        }
    }

    private func reschedule(fireNow: Bool) {
        timer?.cancel()
        let t = DispatchSource.makeTimerSource(queue: queue)
        let iv = max(0.25, config.interval)
        t.schedule(deadline: .now() + (fireNow ? 0.05 : iv), repeating: iv, leeway: .milliseconds(Int(iv * 100)))
        t.setEventHandler { [weak self] in self?.tick() }
        timer = t
        t.resume()
    }

    private func tick() {
        let c = config
        var s = SystemSnapshot()
        s.info = SystemInfoReader.sample()
        let wants = c.enabled
        // CPU history widgets and the session widget both benefit from CPU even if only one is shown.
        if wants.contains(.cpu) || wants.contains(.cores) { s.cpu = cpu.sample() }
        if wants.contains(.memory) { s.memory = MemorySampler.sample() }
        if wants.contains(.disk) { s.disk = disk.sample() }
        if wants.contains(.network) { s.network = net.sample() }
        if wants.contains(.gpu) { s.gpu = gpu.sample() }
        if wants.contains(.processes) {
            s.processes = procs.sample(backend: c.processBackend, count: c.processCount, sort: c.processSort,
                                       minInterval: max(2, c.interval))
        }
        if wants.contains(.battery) { s.battery = PowerSampler.sample() }
        if wants.contains(.temperatures) { s.temperatures = temps.sample() }
        onSnapshot(s)
    }
}
