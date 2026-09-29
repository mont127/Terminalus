import Foundation
import Darwin
import IOKit
import IOKit.ps

// All samplers are confined to SystemSampler's serial queue; they keep previous counters for rates.

final class CPUSampler {
    private var previous: [[UInt32]] = []
    private(set) lazy var coreKinds: [CoreKind] = CPUSampler.detectCoreKinds()

    func sample() -> CPUSample {
        let ticks = CPUSampler.ticks()
        defer { previous = ticks }
        guard previous.count == ticks.count, !ticks.isEmpty else {
            return CPUSample(perCore: Array(repeating: 0, count: ticks.count), coreKinds: coreKinds)
        }
        var per: [Double] = []
        var tu = 0.0, ts = 0.0, tt = 0.0
        for (a, b) in zip(previous, ticks) {
            let user = Double(b[Int(CPU_STATE_USER)] &- a[Int(CPU_STATE_USER)])
            let sys = Double(b[Int(CPU_STATE_SYSTEM)] &- a[Int(CPU_STATE_SYSTEM)])
            let nice = Double(b[Int(CPU_STATE_NICE)] &- a[Int(CPU_STATE_NICE)])
            let idle = Double(b[Int(CPU_STATE_IDLE)] &- a[Int(CPU_STATE_IDLE)])
            let tot = user + sys + nice + idle
            per.append(tot > 0 ? (user + sys + nice) / tot : 0)
            tu += user + nice
            ts += sys
            tt += tot
        }
        return CPUSample(total: tt > 0 ? (tu + ts) / tt : 0, user: tt > 0 ? tu / tt : 0, system: tt > 0 ? ts / tt : 0,
                         perCore: per, coreKinds: coreKinds)
    }

    static func ticks() -> [[UInt32]] {
        var n: natural_t = 0
        var info: processor_info_array_t?
        var cnt: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &n, &info, &cnt) == KERN_SUCCESS, let info else { return [] }
        defer { vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(Int(cnt) * MemoryLayout<integer_t>.stride)) }
        return (0..<Int(n)).map { i in
            (0..<Int(CPU_STATE_MAX)).map { UInt32(bitPattern: info[Int(CPU_STATE_MAX) * i + $0]) }
        }
    }

    /// Reads `cluster-type` of each CPU from the device tree; falls back to "efficiency cores first".
    static func detectCoreKinds() -> [CoreKind] {
        let n = Int(Sysctl.int("hw.logicalcpu") ?? 0)
        var kinds = [CoreKind](repeating: .unknown, count: n)
        let cpus = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/cpus")
        if cpus != 0 {
            defer { IOObjectRelease(cpus) }
            var it: io_iterator_t = 0
            if IORegistryEntryGetChildIterator(cpus, kIODeviceTreePlane, &it) == KERN_SUCCESS {
                defer { IOObjectRelease(it) }
                var e = IOIteratorNext(it)
                while e != 0 {
                    var idx: Int?
                    if let d = IOKitHelpers.property(e, "logical-cpu-id") as? Data, d.count >= 4 {
                        idx = Int(d.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) })
                    }
                    if let d = IOKitHelpers.property(e, "cluster-type") as? Data, let i = idx, i < n {
                        let s = String(decoding: d.prefix { $0 != 0 }, as: UTF8.self)
                        kinds[i] = s == "E" ? .efficiency : (s == "P" ? .performance : .unknown)
                    }
                    IOObjectRelease(e)
                    e = IOIteratorNext(it)
                }
            }
        }
        if kinds.contains(.unknown), let e = Sysctl.int("hw.perflevel1.logicalcpu"), Sysctl.int("hw.nperflevels") ?? 1 > 1 {
            kinds = (0..<n).map { $0 < Int(e) ? .efficiency : .performance }
        }
        return kinds
    }
}

enum MemorySampler {
    static func sample() -> MemorySample {
        var s = MemorySample()
        s.total = UInt64(Sysctl.int("hw.memsize") ?? 0)
        var vm = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &vm) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) }
        }
        if kr == KERN_SUCCESS {
            let page = UInt64(vm_kernel_page_size)
            let internalPages = UInt64(vm.internal_page_count), purgeable = UInt64(vm.purgeable_count)
            s.app = (internalPages > purgeable ? internalPages - purgeable : 0) * page
            s.wired = UInt64(vm.wire_count) * page
            s.compressed = UInt64(vm.compressor_page_count) * page
            s.cached = (UInt64(vm.external_page_count) + purgeable) * page
            s.used = s.app + s.wired + s.compressed
            s.free = s.total > s.used ? s.total - s.used : 0
        }
        var sw = xsw_usage()
        var sws = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &sw, &sws, nil, 0) == 0 {
            s.swapUsed = sw.xsu_used
            s.swapTotal = sw.xsu_total
        }
        switch Sysctl.int("kern.memorystatus_vm_pressure_level") ?? 1 {
        case 2: s.pressure = .warning
        case 4: s.pressure = .critical
        default: s.pressure = .normal
        }
        return s
    }
}

final class DiskSampler {
    private var drivers: [io_object_t] = []
    private var driversRefreshed = Date.distantPast
    private var volumes: [DiskVolume] = []
    private var volumesRefreshed = Date.distantPast
    private var previous: (read: UInt64, write: UInt64, at: Date)?

    deinit { drivers.forEach { IOObjectRelease($0) } }

    func sample() -> DiskSample {
        let now = Date()
        if now.timeIntervalSince(volumesRefreshed) > 10 {
            volumes = DiskSampler.readVolumes()
            volumesRefreshed = now
        }
        if now.timeIntervalSince(driversRefreshed) > 60 {
            drivers.forEach { IOObjectRelease($0) }
            drivers = []
            IOKitHelpers.forEachService("IOBlockStorageDriver") { e in
                if !IOKitHelpers.hasAncestor(e, classContaining: "DiskImage") {
                    IOObjectRetain(e)
                    drivers.append(e)
                }
            }
            driversRefreshed = now
        }
        var read: UInt64 = 0, write: UInt64 = 0
        for d in drivers {
            guard let stats = IOKitHelpers.property(d, "Statistics") as? [String: Any] else { continue }
            read += (stats["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
            write += (stats["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
        }
        var out = DiskSample(volumes: volumes)
        if let p = previous {
            let dt = max(0.001, now.timeIntervalSince(p.at))
            out.readRate = read >= p.read ? Double(read - p.read) / dt : 0
            out.writeRate = write >= p.write ? Double(write - p.write) / dt : 0
        }
        previous = (read, write, now)
        return out
    }

    static func readVolumes() -> [DiskVolume] {
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
                                      .volumeAvailableCapacityKey, .volumeIsInternalKey, .volumeIsLocalKey, .volumeIsBrowsableKey,
                                      .volumeIsReadOnlyKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        var out: [DiskVolume] = []
        for url in urls {
            guard let v = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            guard v.volumeIsLocal ?? true, v.volumeIsBrowsable ?? true, let total = v.volumeTotalCapacity, total > 0 else { continue }
            // Mounted disk images and installers are read-only; they only add noise.
            if url.path != "/" && (v.volumeIsReadOnly ?? false) { continue }
            let avail = v.volumeAvailableCapacityForImportantUsage.map { UInt64(max(0, $0)) }
                ?? UInt64(v.volumeAvailableCapacity ?? 0)
            out.append(DiskVolume(name: v.volumeName ?? url.lastPathComponent, path: url.path, total: UInt64(total),
                                  available: min(avail, UInt64(total)), isInternal: v.volumeIsInternal ?? false))
        }
        // Root first, then by name.
        return out.sorted { a, b in
            if a.path == "/" { return true }
            if b.path == "/" { return false }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }
}

final class NetworkSampler {
    private var previous: (down: UInt64, up: UInt64, at: Date)?
    private var addressRefreshed = Date.distantPast
    private var primary: (name: String?, ip: String?) = (nil, nil)

    func sample() -> NetworkSample {
        let now = Date()
        let (down, up) = NetworkSampler.counters()
        var s = NetworkSample(totalDown: down, totalUp: up)
        if let p = previous {
            let dt = max(0.001, now.timeIntervalSince(p.at))
            s.downRate = down >= p.down ? Double(down - p.down) / dt : 0
            s.upRate = up >= p.up ? Double(up - p.up) / dt : 0
        }
        previous = (down, up, now)
        if now.timeIntervalSince(addressRefreshed) > 15 {
            primary = NetworkSampler.primaryAddress()
            addressRefreshed = now
        }
        s.primaryInterface = primary.name
        s.localIPv4 = primary.ip
        return s
    }

    /// 64-bit byte counters summed over non-loopback interfaces (NET_RT_IFLIST2).
    static func counters() -> (UInt64, UInt64) {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var len = 0
        guard sysctl(&mib, 6, nil, &len, nil, 0) == 0, len > 0 else { return (0, 0) }
        var buf = [UInt8](repeating: 0, count: len)
        guard sysctl(&mib, 6, &buf, &len, nil, 0) == 0 else { return (0, 0) }
        var ib: UInt64 = 0, ob: UInt64 = 0
        var off = 0
        let hdr2 = MemoryLayout<if_msghdr2>.size
        buf.withUnsafeBytes { raw in
            while off + 4 <= len {
                let msglen = Int(raw.loadUnaligned(fromByteOffset: off, as: UInt16.self))
                guard msglen > 0 else { break }
                let mtype = raw.loadUnaligned(fromByteOffset: off + 3, as: UInt8.self)
                if Int32(mtype) == RTM_IFINFO2 && off + hdr2 <= len {
                    let m = raw.loadUnaligned(fromByteOffset: off, as: if_msghdr2.self)
                    var name = [CChar](repeating: 0, count: Int(IF_NAMESIZE) + 1)
                    if if_indextoname(UInt32(m.ifm_index), &name) != nil {
                        let n = String(cString: name)
                        if !n.hasPrefix("lo") {
                            ib &+= m.ifm_data.ifi_ibytes
                            ob &+= m.ifm_data.ifi_obytes
                        }
                    }
                }
                off += msglen
            }
        }
        return (ib, ob)
    }

    static func primaryAddress() -> (String?, String?) {
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0, let first = ifap else { return (nil, nil) }
        defer { freeifaddrs(ifap) }
        var candidates: [(String, String)] = []
        var p: UnsafeMutablePointer<ifaddrs>? = first
        while let cur = p {
            let ifa = cur.pointee
            p = ifa.ifa_next
            guard let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            let flags = Int32(ifa.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_RUNNING != 0, flags & IFF_LOOPBACK == 0 else { continue }
            let name = String(cString: ifa.ifa_name)
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                candidates.append((name, String(cString: host)))
            }
        }
        let preferred = candidates.first { $0.0.hasPrefix("en") } ?? candidates.first { !$0.0.hasPrefix("utun") && !$0.0.hasPrefix("bridge") } ?? candidates.first
        return (preferred?.0, preferred?.1)
    }
}

final class GPUSampler {
    private var entry: io_object_t = 0
    private var name = "GPU"
    private var cores = 0

    init() {
        IOKitHelpers.forEachService("IOAccelerator") { e in
            guard entry == 0 else { return }
            IOObjectRetain(e)
            entry = e
            if let m = IOKitHelpers.property(e, "model") as? String { name = m }
            if let c = IOKitHelpers.property(e, "gpu-core-count") as? NSNumber { cores = c.intValue }
        }
    }

    deinit { if entry != 0 { IOObjectRelease(entry) } }

    var available: Bool { entry != 0 }

    func sample() -> GPUSample? {
        guard entry != 0, let ps = IOKitHelpers.property(entry, "PerformanceStatistics") as? [String: Any] else { return nil }
        func num(_ k: String) -> Double { (ps[k] as? NSNumber)?.doubleValue ?? 0 }
        return GPUSample(
            name: name,
            cores: cores,
            utilization: num("Device Utilization %") / 100,
            rendererUtilization: num("Renderer Utilization %") / 100,
            tilerUtilization: num("Tiler Utilization %") / 100,
            memoryUsed: UInt64(num("In use system memory")),
            memoryAllocated: UInt64(num("Alloc system memory"))
        )
    }
}

final class ProcessSampler {
    private var lastPS: [ProcessEntry] = []
    private var lastPSAt = Date.distantPast
    private var libprocPrev: [pid_t: (ticks: UInt64, at: Date)] = [:]

    func sample(backend: ProcessBackend, count: Int, sort: ProcessSortKey, minInterval: TimeInterval) -> [ProcessEntry] {
        let now = Date()
        var all: [ProcessEntry]
        switch backend {
        case .ps:
            if now.timeIntervalSince(lastPSAt) >= minInterval || lastPS.isEmpty {
                lastPS = ProcessSampler.runPS()
                lastPSAt = now
            }
            all = lastPS
        case .libproc:
            all = libproc(now: now)
        }
        switch sort {
        case .cpu: all.sort { $0.cpu > $1.cpu }
        case .memory: all.sort { $0.memory > $1.memory }
        }
        return Array(all.prefix(max(1, count)))
    }

    static func runPS() -> [ProcessEntry] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/ps")
        p.arguments = ["-Aceo", "pid=,pcpu=,rss=,comm="]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        var out: [ProcessEntry] = []
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
            // pid, pcpu and rss are numbers; the rest (which may contain spaces) is the name.
            var rest = Substring(line)
            var nums: [Substring] = []
            for _ in 0..<3 {
                rest = rest.drop { $0 == " " }
                let tok = rest.prefix { $0 != " " }
                nums.append(tok)
                rest = rest.dropFirst(tok.count)
            }
            let name = rest.drop { $0 == " " }
            guard let pid = Int32(nums[0]), let cpu = Double(nums[1].replacingOccurrences(of: ",", with: ".")), let rss = UInt64(nums[2]) else { continue }
            out.append(ProcessEntry(pid: pid, name: String(name), cpu: cpu, memory: rss * 1024))
        }
        return out
    }

    private func libproc(now: Date) -> [ProcessEntry] {
        let n = proc_listallpids(nil, 0)
        guard n > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(n) + 64)
        let got = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        var next: [pid_t: (ticks: UInt64, at: Date)] = [:]
        var out: [ProcessEntry] = []
        for pid in pids.prefix(Int(max(0, got))) where pid > 0 {
            var ti = proc_taskinfo()
            let size = Int32(MemoryLayout<proc_taskinfo>.size)
            guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &ti, size) == size else { continue }
            let ticks = ti.pti_total_user + ti.pti_total_system
            next[pid] = (ticks, now)
            var cpu = 0.0
            if let prev = libprocPrev[pid], ticks >= prev.ticks {
                let dt = max(0.001, now.timeIntervalSince(prev.at))
                cpu = Double(ticks - prev.ticks) * MachTime.nanosPerTick / 1e9 / dt * 100
            }
            out.append(ProcessEntry(pid: pid, name: ProcessInspector.name(of: pid) ?? "\(pid)", cpu: cpu, memory: ti.pti_resident_size))
        }
        libprocPrev = next
        return out
    }
}

enum PowerSampler {
    static func sample() -> BatterySample? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for src in list {
            guard let d = IOPSGetPowerSourceDescription(info, src)?.takeUnretainedValue() as? [String: Any] else { continue }
            guard (d[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }
            let cur = (d[kIOPSCurrentCapacityKey] as? NSNumber)?.doubleValue ?? 0
            let max = (d[kIOPSMaxCapacityKey] as? NSNumber)?.doubleValue ?? 100
            let charging = (d[kIOPSIsChargingKey] as? Bool) ?? false
            let onAC = (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            let key = charging ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey
            let t = (d[key] as? NSNumber)?.intValue
            return BatterySample(percent: max > 0 ? cur / max : 0, isCharging: charging, onAC: onAC,
                                 timeRemaining: (t ?? -1) > 0 ? t : nil)
        }
        return nil
    }
}

/// Reads SoC temperature sensors through the private IOHIDEventSystemClient API (resolved with dlsym,
/// so a missing symbol simply makes the sampler unavailable).
final class TemperatureSampler {
    private typealias CreateFn = @convention(c) (CFAllocator?) -> Unmanaged<AnyObject>?
    private typealias SetMatchFn = @convention(c) (AnyObject, CFDictionary) -> Int32
    private typealias CopySvcFn = @convention(c) (AnyObject) -> Unmanaged<CFArray>?
    private typealias CopyPropFn = @convention(c) (AnyObject, CFString) -> Unmanaged<AnyObject>?
    private typealias CopyEventFn = @convention(c) (AnyObject, Int64, Int32, Int64) -> Unmanaged<AnyObject>?
    private typealias GetFloatFn = @convention(c) (AnyObject, Int32) -> Double

    private var client: AnyObject?
    private var services: [(name: String, service: AnyObject)] = []
    private var copyEvent: CopyEventFn?
    private var getFloat: GetFloatFn?
    private var servicesRefreshed = Date.distantPast
    private var copyServices: CopySvcFn?
    private var copyProperty: CopyPropFn?

    init() {
        guard let h = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW),
              let c = dlsym(h, "IOHIDEventSystemClientCreate"), let sm = dlsym(h, "IOHIDEventSystemClientSetMatching"),
              let cs = dlsym(h, "IOHIDEventSystemClientCopyServices"), let cp = dlsym(h, "IOHIDServiceClientCopyProperty"),
              let ce = dlsym(h, "IOHIDServiceClientCopyEvent"), let gf = dlsym(h, "IOHIDEventGetFloatValue") else { return }
        let create = unsafeBitCast(c, to: CreateFn.self)
        let setMatch = unsafeBitCast(sm, to: SetMatchFn.self)
        copyServices = unsafeBitCast(cs, to: CopySvcFn.self)
        copyProperty = unsafeBitCast(cp, to: CopyPropFn.self)
        copyEvent = unsafeBitCast(ce, to: CopyEventFn.self)
        getFloat = unsafeBitCast(gf, to: GetFloatFn.self)
        guard let cl = create(kCFAllocatorDefault)?.takeRetainedValue() else { return }
        _ = setMatch(cl, ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5] as CFDictionary)
        client = cl
    }

    func sample() -> TemperatureSample {
        guard let client, let copyServices, let copyProperty, let copyEvent, let getFloat else { return TemperatureSample() }
        if Date().timeIntervalSince(servicesRefreshed) > 60 || services.isEmpty {
            let svcs = (copyServices(client)?.takeRetainedValue() as? [AnyObject]) ?? []
            services = svcs.map { s in ((copyProperty(s, "Product" as CFString)?.takeRetainedValue() as? String) ?? "Sensor", s) }
            servicesRefreshed = Date()
        }
        var sensors: [TemperatureSensor] = []
        var seen: [String: Int] = [:]
        for (name, s) in services {
            guard let ev = copyEvent(s, 15, 0, 0)?.takeRetainedValue() else { continue }
            let t = getFloat(ev, 15 << 16)
            guard t > -40, t < 150 else { continue }
            let n = seen[name, default: 0]
            seen[name] = n + 1
            sensors.append(TemperatureSensor(name: n == 0 ? name : "\(name) #\(n + 1)", celsius: t))
        }
        sensors.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return TemperatureSample(sensors: sensors, available: !sensors.isEmpty)
    }
}

enum SystemInfoReader {
    static let staticInfo: SystemInfoSample = {
        var s = SystemInfoSample()
        s.modelIdentifier = Sysctl.string("hw.model") ?? ""
        s.modelName = modelNames[s.modelIdentifier] ?? s.modelIdentifier
        s.chip = Sysctl.string("machdep.cpu.brand_string") ?? "Unknown CPU"
        let v = ProcessInfo.processInfo.operatingSystemVersion
        s.osVersion = "macOS \(v.majorVersion).\(v.minorVersion)" + (v.patchVersion > 0 ? ".\(v.patchVersion)" : "")
        var buf = [CChar](repeating: 0, count: 256)
        gethostname(&buf, buf.count)
        s.hostname = String(cString: buf).replacingOccurrences(of: ".local", with: "")
        s.user = NSUserName()
        s.logicalCPUs = Int(Sysctl.int("hw.logicalcpu") ?? 0)
        if (Sysctl.int("hw.nperflevels") ?? 1) > 1 {
            s.performanceCores = Int(Sysctl.int("hw.perflevel0.logicalcpu") ?? 0)
            s.efficiencyCores = Int(Sysctl.int("hw.perflevel1.logicalcpu") ?? 0)
        } else {
            s.performanceCores = s.logicalCPUs
        }
        s.memoryTotal = UInt64(Sysctl.int("hw.memsize") ?? 0)
        return s
    }()

    static func sample() -> SystemInfoSample {
        var s = staticInfo
        s.uptime = ProcessInfo.processInfo.systemUptime
        var la = [Double](repeating: 0, count: 3)
        getloadavg(&la, 3)
        s.loadAverage = la
        s.processCount = Int(max(0, proc_listallpids(nil, 0)))
        s.thermal = ThermalLevel(ProcessInfo.processInfo.thermalState)
        return s
    }

    static let modelNames: [String: String] = [
        "Mac13,1": "Mac Studio (2022)", "Mac13,2": "Mac Studio (2022)",
        "Mac14,13": "Mac Studio (2023)", "Mac14,14": "Mac Studio (2023)",
        "Mac15,14": "Mac Studio (2025)", "Mac16,9": "Mac Studio (2025)",
        "Mac14,3": "Mac mini (2023)", "Mac14,12": "Mac mini (2023)", "Macmini9,1": "Mac mini (M1)",
        "Mac16,10": "Mac mini (2024)", "Mac16,11": "Mac mini (2024)",
        "Mac14,8": "Mac Pro (2023)",
        "MacBookAir10,1": "MacBook Air (M1)", "Mac14,2": "MacBook Air (M2)", "Mac14,15": "MacBook Air 15\" (M2)",
        "Mac15,12": "MacBook Air 13\" (M3)", "Mac15,13": "MacBook Air 15\" (M3)",
        "Mac16,12": "MacBook Air 13\" (M4)", "Mac16,13": "MacBook Air 15\" (M4)",
        "MacBookPro17,1": "MacBook Pro 13\" (M1)", "MacBookPro18,1": "MacBook Pro 16\" (2021)",
        "MacBookPro18,2": "MacBook Pro 16\" (2021)", "MacBookPro18,3": "MacBook Pro 14\" (2021)",
        "MacBookPro18,4": "MacBook Pro 14\" (2021)", "Mac14,7": "MacBook Pro 13\" (M2)",
        "Mac14,5": "MacBook Pro 14\" (2023)", "Mac14,9": "MacBook Pro 14\" (2023)",
        "Mac14,6": "MacBook Pro 16\" (2023)", "Mac14,10": "MacBook Pro 16\" (2023)",
        "Mac15,3": "MacBook Pro 14\" (M3)", "Mac15,6": "MacBook Pro 14\" (M3 Pro)", "Mac15,8": "MacBook Pro 14\" (M3 Max)",
        "Mac15,7": "MacBook Pro 16\" (M3 Pro)", "Mac15,9": "MacBook Pro 16\" (M3 Max)",
        "Mac16,1": "MacBook Pro 14\" (M4)", "Mac16,6": "MacBook Pro 14\" (M4 Max)", "Mac16,8": "MacBook Pro 14\" (M4 Pro)",
        "Mac16,5": "MacBook Pro 16\" (M4 Max)", "Mac16,7": "MacBook Pro 16\" (M4 Pro)",
        "iMac21,1": "iMac 24\" (M1)", "iMac21,2": "iMac 24\" (M1)", "Mac15,4": "iMac 24\" (M3)", "Mac15,5": "iMac 24\" (M3)",
        "Mac16,2": "iMac 24\" (M4)", "Mac16,3": "iMac 24\" (M4)",
    ]
}
