import Foundation

/// Fixed-capacity FIFO of recent samples, oldest first.
public struct RingBuffer<Element>: Sendable where Element: Sendable {
    public private(set) var capacity: Int
    private var storage: [Element] = []
    private var head = 0

    public init(capacity: Int) {
        self.capacity = max(1, capacity)
        storage.reserveCapacity(self.capacity)
    }

    public var count: Int { storage.count }
    public var isEmpty: Bool { storage.isEmpty }

    public mutating func append(_ e: Element) {
        if storage.count < capacity {
            storage.append(e)
        } else {
            storage[head] = e
            head = (head + 1) % capacity
        }
    }

    public var elements: [Element] {
        storage.count < capacity ? storage : Array(storage[head...] + storage[..<head])
    }

    public var last: Element? {
        guard !storage.isEmpty else { return nil }
        return storage.count < capacity ? storage.last : storage[(head + capacity - 1) % capacity]
    }

    public mutating func resize(_ newCapacity: Int) {
        let cap = max(1, newCapacity)
        guard cap != capacity else { return }
        let els = elements.suffix(cap)
        capacity = cap
        storage = Array(els)
        head = 0
    }
}
