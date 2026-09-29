import Foundation

/// Parses the payload of OSC 7 (`file://host/percent-encoded/path`).
public struct OSC7Location: Equatable, Sendable {
    public var host: String
    public var path: String
    public var isLocal: Bool

    public init?(_ raw: String) {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("/") {
            host = ""
            path = s.removingPercentEncoding ?? s
            isLocal = true
            return
        }
        guard s.lowercased().hasPrefix("file://") else { return nil }
        let rest = s.dropFirst("file://".count)
        let slash = rest.firstIndex(of: "/") ?? rest.endIndex
        host = String(rest[rest.startIndex..<slash])
        let encodedPath = String(rest[slash...])
        guard !encodedPath.isEmpty else { return nil }
        path = encodedPath.removingPercentEncoding ?? encodedPath
        isLocal = OSC7Location.isLocalHost(host)
    }

    public static func isLocalHost(_ host: String) -> Bool {
        if host.isEmpty || host == "localhost" || host == "127.0.0.1" || host == "::1" { return true }
        let h = host.lowercased()
        let names = localHostNames
        if names.contains(h) { return true }
        // "mymac" vs "mymac.local"
        let short = h.split(separator: ".").first.map(String.init) ?? h
        return names.contains { $0.split(separator: ".").first.map(String.init) == short }
    }

    // gethostname() only: ProcessInfo.hostName does a blocking DNS lookup.
    private static let localHostNames: Set<String> = {
        var names = Set<String>()
        var buf = [CChar](repeating: 0, count: 256)
        if gethostname(&buf, buf.count) == 0 {
            let h = String(cString: buf).lowercased()
            names.insert(h)
            if !h.hasSuffix(".local") { names.insert(h + ".local") }
        }
        return names
    }()
}
