import Foundation

public enum CoreKind: String, Sendable {
    case performance, efficiency, unknown
}

public struct CPUSample: Sendable, Equatable {
    public var total: Double = 0
    public var user: Double = 0
    public var system: Double = 0
    public var perCore: [Double] = []
    public var coreKinds: [CoreKind] = []
}

public enum MemoryPressure: String, Sendable {
    case normal, warning, critical
}

public struct MemorySample: Sendable, Equatable {
    public var total: UInt64 = 0
    public var used: UInt64 = 0
    public var app: UInt64 = 0
    public var wired: UInt64 = 0
    public var compressed: UInt64 = 0
    public var cached: UInt64 = 0
    public var free: UInt64 = 0
    public var swapUsed: UInt64 = 0
    public var swapTotal: UInt64 = 0
    public var pressure: MemoryPressure = .normal
    public var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
}

public struct DiskVolume: Sendable, Equatable, Identifiable {
    public var name: String
    public var path: String
    public var total: UInt64
    public var available: UInt64
    public var isInternal: Bool
    public var id: String { path }
    public var used: UInt64 { total > available ? total - available : 0 }
    public var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
}

public struct DiskSample: Sendable, Equatable {
    public var volumes: [DiskVolume] = []
    public var readRate: Double = 0
    public var writeRate: Double = 0
}

public struct NetworkSample: Sendable, Equatable {
    public var downRate: Double = 0
    public var upRate: Double = 0
    public var totalDown: UInt64 = 0
    public var totalUp: UInt64 = 0
    public var primaryInterface: String?
    public var localIPv4: String?
}

public struct GPUSample: Sendable, Equatable {
    public var name: String = "GPU"
    public var cores: Int = 0
    public var utilization: Double = 0
    public var rendererUtilization: Double = 0
    public var tilerUtilization: Double = 0
    public var memoryUsed: UInt64 = 0
    public var memoryAllocated: UInt64 = 0
}

public struct ProcessEntry: Sendable, Equatable, Identifiable {
    public var pid: Int32
    public var name: String
    /// Percent of one core (can exceed 100).
    public var cpu: Double
    public var memory: UInt64
    public var id: Int32 { pid }
}

public struct BatterySample: Sendable, Equatable {
    public var percent: Double
    public var isCharging: Bool
    public var onAC: Bool
    /// Minutes, nil when unknown/calculating.
    public var timeRemaining: Int?
}

public struct TemperatureSensor: Sendable, Equatable, Identifiable {
    public var name: String
    public var celsius: Double
    public var id: String { name }
}

public struct TemperatureSample: Sendable, Equatable {
    public var sensors: [TemperatureSensor] = []
    public var available: Bool = false
    public var dieMax: Double? {
        let die = sensors.filter { $0.name.lowercased().contains("tdie") }
        return (die.isEmpty ? sensors : die).map(\.celsius).max()
    }
    public var dieAverage: Double? {
        let die = sensors.filter { $0.name.lowercased().contains("tdie") }
        let s = die.isEmpty ? sensors : die
        return s.isEmpty ? nil : s.map(\.celsius).reduce(0, +) / Double(s.count)
    }
}

public enum ThermalLevel: String, Sendable {
    case nominal, fair, serious, critical

    public init(_ s: ProcessInfo.ThermalState) {
        switch s {
        case .nominal: self = .nominal
        case .fair: self = .fair
        case .serious: self = .serious
        case .critical: self = .critical
        @unknown default: self = .nominal
        }
    }
}

public struct SystemInfoSample: Sendable, Equatable {
    public var modelIdentifier: String = ""
    public var modelName: String = ""
    public var chip: String = ""
    public var osVersion: String = ""
    public var hostname: String = ""
    public var user: String = ""
    public var uptime: TimeInterval = 0
    public var loadAverage: [Double] = [0, 0, 0]
    public var processCount: Int = 0
    public var logicalCPUs: Int = 0
    public var performanceCores: Int = 0
    public var efficiencyCores: Int = 0
    public var memoryTotal: UInt64 = 0
    public var thermal: ThermalLevel = .nominal
}

public struct SystemSnapshot: Sendable {
    public var timestamp = Date()
    public var cpu: CPUSample?
    public var memory: MemorySample?
    public var disk: DiskSample?
    public var network: NetworkSample?
    public var gpu: GPUSample?
    public var processes: [ProcessEntry]?
    /// nil when the Mac has no battery.
    public var battery: BatterySample?
    public var temperatures: TemperatureSample?
    public var info = SystemInfoSample()

    public init() {}
}

// Empty values for use outside the module (the synthesized initializers are internal).
extension CPUSample { public static let empty = CPUSample() }
extension MemorySample { public static let empty = MemorySample() }
extension DiskSample { public static let empty = DiskSample() }
extension NetworkSample { public static let empty = NetworkSample() }
extension GPUSample { public static let empty = GPUSample() }
extension TemperatureSample { public static let empty = TemperatureSample() }
extension SystemInfoSample { public static let empty = SystemInfoSample() }
