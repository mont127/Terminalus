import Foundation
import Darwin
import IOKit

enum Sysctl {
    static func int(_ name: String) -> Int64? {
        var v: Int64 = 0
        var s = MemoryLayout<Int64>.size
        guard sysctlbyname(name, &v, &s, nil, 0) == 0 else { return nil }
        return s == 4 ? Int64(Int32(truncatingIfNeeded: v)) : v
    }

    static func string(_ name: String) -> String? {
        var s = 0
        guard sysctlbyname(name, nil, &s, nil, 0) == 0, s > 0 else { return nil }
        var buf = [CChar](repeating: 0, count: s)
        guard sysctlbyname(name, &buf, &s, nil, 0) == 0 else { return nil }
        return String(cString: buf)
    }
}

enum IOKitHelpers {
    /// Calls `body` with every service matching `className`. Objects are released after the call.
    static func forEachService(_ className: String, _ body: (io_object_t) -> Void) {
        var it: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(className), &it) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(it) }
        var e = IOIteratorNext(it)
        while e != 0 {
            body(e)
            IOObjectRelease(e)
            e = IOIteratorNext(it)
        }
    }

    static func property(_ entry: io_object_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }

    static func className(_ entry: io_object_t) -> String {
        var buf = [CChar](repeating: 0, count: 128)
        IOObjectGetClass(entry, &buf)
        return String(cString: buf)
    }

    /// True if any ancestor (service plane, up to `depth` levels) has a class name containing `fragment`.
    static func hasAncestor(_ entry: io_object_t, classContaining fragment: String, depth: Int = 8) -> Bool {
        var current = entry
        IOObjectRetain(current)
        defer { IOObjectRelease(current) }
        for _ in 0..<depth {
            var parent: io_object_t = 0
            guard IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent) == KERN_SUCCESS else { return false }
            IOObjectRelease(current)
            current = parent
            if className(current).contains(fragment) { return true }
        }
        return false
    }
}
