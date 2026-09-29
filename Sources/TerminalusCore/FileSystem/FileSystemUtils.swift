import Foundation
import CoreServices

/// fnmatch-based glob list matched against file names (not full paths).
public struct GlobMatcher: Sendable {
    public let patterns: [String]

    public init(_ patterns: [String]) {
        self.patterns = patterns.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    public func matches(_ name: String) -> Bool {
        for p in patterns where fnmatch(p, name, 0) == 0 { return true }
        return false
    }
}

/// Recursive FSEvents watcher. Reports the set of directories whose contents changed, debounced.
public final class FSEventsWatcher: @unchecked Sendable {
    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "terminalus.fsevents")
    private let onChange: (Set<String>) -> Void
    private var pending = Set<String>()
    private var flushScheduled = false
    private let debounce: TimeInterval
    private let fileEvents: Bool
    public private(set) var paths: [String] = []

    /// With `fileEvents` false the stream reports directories (cheap, used for the tree); with true it
    /// reports individual files, which are mapped to their parent directories.
    public init(debounce: TimeInterval = 0.25, fileEvents: Bool = false, onChange: @escaping (Set<String>) -> Void) {
        self.debounce = debounce
        self.fileEvents = fileEvents
        self.onChange = onChange
    }

    deinit { stopStream() }

    /// Watches `paths` (recursively), replacing any previous watch.
    public func watch(_ newPaths: [String]) {
        let unique = Array(Set(newPaths)).sorted()
        guard unique != paths else { return }
        stopStream()
        paths = unique
        guard !unique.isEmpty else { return }
        var ctx = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, pathsPtr, flagsPtr, _ in
            guard let info else { return }
            let me = Unmanaged<FSEventsWatcher>.fromOpaque(info).takeUnretainedValue()
            let arr = unsafeBitCast(pathsPtr, to: NSArray.self)
            var dirs = Set<String>()
            for i in 0..<count {
                guard var p = arr[i] as? String else { continue }
                if p.count > 1 && p.hasSuffix("/") { p.removeLast() }
                if !me.fileEvents {
                    dirs.insert(p)
                    continue
                }
                let flags = Int(flagsPtr[i])
                let isDir = flags & kFSEventStreamEventFlagItemIsDir != 0
                let structural = flags & (kFSEventStreamEventFlagItemCreated | kFSEventStreamEventFlagItemRemoved | kFSEventStreamEventFlagItemRenamed) != 0
                let mustScan = flags & kFSEventStreamEventFlagMustScanSubDirs != 0
                if mustScan {
                    dirs.insert(p)
                    continue
                }
                if structural || !isDir {
                    dirs.insert((p as NSString).deletingLastPathComponent)
                }
                if isDir && structural {
                    dirs.insert(p)
                }
            }
            me.enqueue(dirs)
        }
        var flags = UInt32(kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagWatchRoot | kFSEventStreamCreateFlagUseCFTypes)
        if fileEvents { flags |= UInt32(kFSEventStreamCreateFlagFileEvents) }
        guard let s = FSEventStreamCreate(kCFAllocatorDefault, callback, &ctx, unique as CFArray,
                                          FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.3, flags) else { return }
        FSEventStreamSetDispatchQueue(s, queue)
        FSEventStreamStart(s)
        stream = s
    }

    public func stop() {
        stopStream()
        paths = []
    }

    private func stopStream() {
        guard let s = stream else { return }
        FSEventStreamStop(s)
        FSEventStreamInvalidate(s)
        FSEventStreamRelease(s)
        stream = nil
    }

    private func enqueue(_ dirs: Set<String>) {
        pending.formUnion(dirs)
        guard !flushScheduled else { return }
        flushScheduled = true
        queue.asyncAfter(deadline: .now() + debounce) { [weak self] in
            guard let self else { return }
            let batch = self.pending
            self.pending.removeAll()
            self.flushScheduled = false
            if !batch.isEmpty { self.onChange(batch) }
        }
    }
}
