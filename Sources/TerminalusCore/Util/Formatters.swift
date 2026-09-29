import Foundation

public enum Fmt {
    /// 1536 → "1.5 KB" (base 1024, compact).
    public static func bytes(_ v: Double, decimals: Int = 1) -> String {
        let units = ["B", "KB", "MB", "GB", "TB", "PB"]
        var x = max(0, v)
        var i = 0
        while x >= 1024 && i < units.count - 1 {
            x /= 1024
            i += 1
        }
        if i == 0 { return "\(Int(x)) B" }
        let d = x >= 100 ? 0 : decimals
        return String(format: "%.\(d)f %@", x, units[i])
    }

    public static func bytes(_ v: UInt64, decimals: Int = 1) -> String { bytes(Double(v), decimals: decimals) }

    public static func rate(_ bytesPerSecond: Double, unit: NetworkUnit = .bytes) -> String {
        switch unit {
        case .bytes:
            return bytes(bytesPerSecond) + "/s"
        case .bits:
            let units = ["b", "Kb", "Mb", "Gb", "Tb"]
            var x = max(0, bytesPerSecond * 8)
            var i = 0
            while x >= 1000 && i < units.count - 1 {
                x /= 1000
                i += 1
            }
            return String(format: i == 0 ? "%.0f %@/s" : "%.1f %@/s", x, units[i])
        }
    }

    public static func percent(_ fraction: Double, decimals: Int = 0) -> String {
        String(format: "%.\(decimals)f%%", max(0, fraction) * 100)
    }

    /// 3725 → "1h 2m", 42 → "42s".
    public static func duration(_ seconds: Double) -> String {
        let s = Int(max(0, seconds))
        let d = s / 86_400, h = (s % 86_400) / 3600, m = (s % 3600) / 60, sec = s % 60
        if d > 0 { return "\(d)d \(h)h" }
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m \(sec)s" }
        return "\(sec)s"
    }

    /// Stopwatch style: "0:07", "12:03", "1:02:03".
    public static func stopwatch(_ seconds: Double) -> String {
        let s = Int(max(0, seconds))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }

    public static func temperature(_ celsius: Double, unit: TemperatureUnit) -> String {
        switch unit {
        case .celsius: String(format: "%.0f°C", celsius)
        case .fahrenheit: String(format: "%.0f°F", celsius * 9 / 5 + 32)
        }
    }
}
