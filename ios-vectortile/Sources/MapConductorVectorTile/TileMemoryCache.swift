import Foundation

/// Strict byte/count limits. Hits promote entries; idle entries expire.
/// Unlike NSCache, insertion returns with the retained cost within budget.
final class TileMemoryCache<Value> {
    private final class Entry {
        let key: String
        let value: Value
        let cost: Int
        var accessed: TimeInterval
        weak var previous: Entry?
        var next: Entry?

        init(key: String, value: Value, cost: Int, accessed: TimeInterval) {
            self.key = key; self.value = value; self.cost = cost; self.accessed = accessed
        }
    }

    private let lock = NSLock()
    private let byteLimit: Int
    private let countLimit: Int
    private let ttl: TimeInterval
    private let clock: () -> TimeInterval
    private var entries: [String: Entry] = [:]
    private var newest: Entry?
    private var oldest: Entry?
    private var bytes = 0

    init(byteLimit: Int, countLimit: Int = 512, ttl: TimeInterval = 120,
         clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.byteLimit = max(0, byteLimit)
        self.countLimit = max(0, countLimit)
        self.ttl = ttl
        self.clock = clock
    }

    func value(for key: String) -> Value? {
        lock.lock(); defer { lock.unlock() }
        let now = clock()
        expire(now)
        guard let entry = entries[key] else { return nil }
        unlink(entry)
        entry.accessed = now
        prepend(entry)
        return entry.value
    }

    func insert(_ value: Value, for key: String, cost: Int) {
        lock.lock(); defer { lock.unlock() }
        let now = clock()
        expire(now)
        if let old = entries[key] { remove(old) }
        let cost = max(1, cost)
        guard cost <= byteLimit, countLimit > 0 else { return }
        while entries.count >= countLimit || bytes > byteLimit - cost {
            guard let entry = oldest else { break }
            remove(entry)
        }
        let entry = Entry(key: key, value: value, cost: cost, accessed: now)
        entries[key] = entry
        bytes += cost
        prepend(entry)
    }

    private func expire(_ now: TimeInterval) {
        while let entry = oldest, now - entry.accessed >= ttl { remove(entry) }
    }

    private func prepend(_ entry: Entry) {
        entry.previous = nil
        entry.next = newest
        newest?.previous = entry
        newest = entry
        if oldest == nil { oldest = entry }
    }

    private func unlink(_ entry: Entry) {
        if let previous = entry.previous { previous.next = entry.next } else { newest = entry.next }
        if let next = entry.next { next.previous = entry.previous } else { oldest = entry.previous }
        entry.previous = nil
        entry.next = nil
    }

    private func remove(_ entry: Entry) {
        unlink(entry)
        entries.removeValue(forKey: entry.key)
        bytes -= entry.cost
    }

    func removeAll() {
        lock.lock(); defer { lock.unlock() }
        // Break the chain iteratively rather than recursing through deinit.
        while let entry = oldest { remove(entry) }
    }

    var retainedCost: Int {
        lock.lock(); defer { lock.unlock() }
        expire(clock())
        return bytes
    }
}
