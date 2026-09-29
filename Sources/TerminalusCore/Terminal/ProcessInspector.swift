import Foundation
import Darwin

/// libproc helpers for inspecting the shell running in a PTY and its foreground job.
public enum ProcessInspector {
    public static let knownShells: Set<String> = ["zsh", "bash", "sh", "fish", "nu", "xonsh", "dash", "ksh", "tcsh", "csh", "elvish", "pwsh"]

    /// Current working directory of `pid`, or nil if it cannot be read (other user, exited…).
    public static func cwd(of pid: pid_t) -> String? {
        guard pid > 0 else { return nil }
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        let path = withUnsafePointer(to: &info.pvi_cdir.vip_path) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
        }
        return path.isEmpty ? nil : path
    }

    /// Foreground process group of the terminal whose master side is `fd`.
    public static func foregroundProcessGroup(ptyMaster fd: Int32) -> pid_t? {
        guard fd >= 0 else { return nil }
        let pg = tcgetpgrp(fd)
        return pg > 0 ? pg : nil
    }

    /// Short process name (up to 32 chars from the kernel; falls back to the executable name).
    public static func name(of pid: pid_t) -> String? {
        guard pid > 0 else { return nil }
        var buf = [CChar](repeating: 0, count: 256)
        if proc_name(pid, &buf, UInt32(buf.count)) > 0 {
            let n = String(cString: buf)
            if !n.isEmpty { return n }
        }
        return executablePath(of: pid).map { ($0 as NSString).lastPathComponent }
    }

    public static func executablePath(of pid: pid_t) -> String? {
        var buf = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let n = proc_pidpath(pid, &buf, UInt32(buf.count))
        return n > 0 ? String(cString: buf) : nil
    }

    /// argv of `pid` via KERN_PROCARGS2 (only for processes of the same user).
    public static func arguments(of pid: pid_t) -> [String]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buf = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buf, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }
        let argc = buf.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
        var i = MemoryLayout<Int32>.size
        while i < size && buf[i] != 0 { i += 1 }   // exec path
        while i < size && buf[i] == 0 { i += 1 }   // padding
        var args: [String] = []
        while args.count < Int(argc) && i < size {
            let start = i
            while i < size && buf[i] != 0 { i += 1 }
            args.append(String(decoding: buf[start..<i], as: UTF8.self))
            i += 1
        }
        return args
    }

    public static func isShell(_ pid: pid_t) -> Bool {
        guard let n = name(of: pid) else { return false }
        return knownShells.contains(n.trimmingCharacters(in: CharacterSet(charactersIn: "-")))
    }

    /// Wall-clock start time of a process.
    public static func startTime(of pid: pid_t) -> Date? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(info.pbi_start_tvsec) + TimeInterval(info.pbi_start_tvusec) / 1e6)
    }

    /// Direct children of `pid`.
    public static func children(of pid: pid_t) -> [pid_t] {
        let n = proc_listchildpids(pid, nil, 0)
        guard n > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(n) + 16)
        let got = proc_listchildpids(pid, &pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard got > 0 else { return [] }
        return Array(pids.prefix(Int(got))).filter { $0 > 0 }
    }

    /// Resident memory in bytes and total CPU time in seconds (same-user processes only).
    public static func taskInfo(of pid: pid_t) -> (rss: UInt64, cpuSeconds: Double, threads: Int)? {
        var ti = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &ti, size) == size else { return nil }
        let ticks = Double(ti.pti_total_user + ti.pti_total_system)
        return (ti.pti_resident_size, ticks * MachTime.nanosPerTick / 1e9, Int(ti.pti_threadnum))
    }

    /// The directory to follow for a session: the foreground job's cwd if it is a shell (nested bash
    /// etc.), otherwise the session shell's own cwd.
    public static func trackedDirectory(shellPid: pid_t, ptyMaster fd: Int32) -> String? {
        if let pg = foregroundProcessGroup(ptyMaster: fd), pg != shellPid, isShell(pg), let d = cwd(of: pg) {
            return d
        }
        return cwd(of: shellPid)
    }

    /// Name of the foreground job if it is not the session shell itself.
    public static func foregroundCommand(shellPid: pid_t, ptyMaster fd: Int32) -> (pid: pid_t, name: String)? {
        guard let pg = foregroundProcessGroup(ptyMaster: fd), pg != shellPid, let n = name(of: pg) else { return nil }
        return (pg, n)
    }
}

public enum MachTime {
    /// Nanoseconds per Mach absolute-time tick (125/3 on Apple silicon, 1 on Intel).
    public static let nanosPerTick: Double = {
        var tb = mach_timebase_info()
        mach_timebase_info(&tb)
        return tb.denom == 0 ? 1 : Double(tb.numer) / Double(tb.denom)
    }()
}
