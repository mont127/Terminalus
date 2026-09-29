import Foundation

/// Coalesces bursts of calls into one call after `delay` of quiet, on `queue`.
public final class Debouncer: @unchecked Sendable {
    private let delay: TimeInterval
    private let queue: DispatchQueue
    private var work: DispatchWorkItem?
    private let lock = NSLock()

    public init(delay: TimeInterval, queue: DispatchQueue = .main) {
        self.delay = delay
        self.queue = queue
    }

    public func call(_ block: @escaping () -> Void) {
        lock.lock()
        work?.cancel()
        let item = DispatchWorkItem(block: block)
        work = item
        lock.unlock()
        queue.asyncAfter(deadline: .now() + delay, execute: item)
    }

    public func cancel() {
        lock.lock()
        work?.cancel()
        work = nil
        lock.unlock()
    }
}

/// Watches a single file for writes, renames and deletes. Re-arms after atomic saves (editors that
/// write a temp file and rename it over the original).
public final class FileWatcher: @unchecked Sendable {
    private let url: URL
    private let queue = DispatchQueue(label: "terminalus.filewatcher")
    private var source: DispatchSourceFileSystemObject?
    private let onChange: () -> Void
    private var retryWork: DispatchWorkItem?

    public init(url: URL, onChange: @escaping () -> Void) {
        self.url = url
        self.onChange = onChange
        queue.async { self.arm() }
    }

    deinit { source?.cancel() }

    private func arm() {
        source?.cancel()
        source = nil
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else {
            // File missing (mid-rename or deleted): retry shortly.
            let w = DispatchWorkItem { [weak self] in self?.arm() }
            retryWork = w
            queue.asyncAfter(deadline: .now() + 1, execute: w)
            return
        }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .extend, .rename, .delete, .attrib], queue: queue)
        src.setEventHandler { [weak self] in
            guard let self, let s = self.source else { return }
            let ev = s.data
            self.onChange()
            if ev.contains(.rename) || ev.contains(.delete) {
                self.queue.asyncAfter(deadline: .now() + 0.1) { self.arm() }
            }
        }
        src.setCancelHandler { close(fd) }
        source = src
        src.resume()
    }

    public func stop() {
        queue.sync {
            retryWork?.cancel()
            source?.cancel()
            source = nil
        }
    }
}
