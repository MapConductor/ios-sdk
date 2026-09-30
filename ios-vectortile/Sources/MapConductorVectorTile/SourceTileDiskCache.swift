import Foundation

/// Persistent cache for fetched source MVT/PBF bytes.
final class SourceTileDiskCache {
    private let directory: URL
    private let budgetBytes: Int
    private let queue = DispatchQueue(label: "mapconductor.vectortile.sources", attributes: .concurrent)
    private var writesSinceSweep = 0
    private static let sweepEvery = 32

    init?(directory: URL, budgetBytes: Int) {
        guard (try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )) != nil else { return nil }
        self.directory = directory
        self.budgetBytes = budgetBytes
    }

    private func file(_ key: String) -> URL {
        directory.appendingPathComponent("\(Digest.hex(key)).mvt")
    }

    func get(_ key: String) -> Data? {
        queue.sync {
            let url = file(key)
            guard let bytes = try? Data(contentsOf: url), !bytes.isEmpty else { return nil }
            try? FileManager.default.setAttributes(
                [.modificationDate: Date()], ofItemAtPath: url.path
            )
            return bytes
        }
    }

    func put(_ key: String, _ bytes: Data) {
        queue.async(flags: .barrier) {
            guard (try? bytes.write(to: self.file(key), options: .atomic)) != nil else { return }
            self.writesSinceSweep += 1
            if self.writesSinceSweep % SourceTileDiskCache.sweepEvery == 0 { self.sweep() }
        }
    }

    private func sweep() {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: keys
        ) else { return }

        var described = entries.compactMap { url -> (URL, Date, Int)? in
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  let modified = values.contentModificationDate,
                  let size = values.fileSize
            else { return nil }
            return (url, modified, size)
        }
        var total = described.reduce(0) { $0 + $1.2 }
        guard total > budgetBytes else { return }

        described.sort { $0.1 < $1.1 }
        for (url, _, size) in described {
            if total <= budgetBytes { break }
            if (try? FileManager.default.removeItem(at: url)) != nil { total -= size }
        }
    }
}

final class SourceFetchStats: @unchecked Sendable {
    private let lock = NSLock()
    private var values = [0, 0, 0, 0, 0, 0, 0]

    var memoryHits: Int {
        get { get(0) }
        set { set(0, newValue) }
    }
    var diskHits: Int {
        get { get(1) }
        set { set(1, newValue) }
    }
    var networkFetches: Int {
        get { get(2) }
        set { set(2, newValue) }
    }
    var sharedWaits: Int {
        get { get(3) }
        set { set(3, newValue) }
    }
    var cancelled: Int {
        get { get(4) }
        set { set(4, newValue) }
    }
    var queueWaitMs: Int {
        get { get(5) }
        set { set(5, newValue) }
    }
    /// Fetches refused because the network was off and the package had no answer.
    var blocked: Int {
        get { get(6) }
        set { set(6, newValue) }
    }

    private func get(_ index: Int) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return values[index]
    }

    private func set(_ index: Int, _ value: Int) {
        lock.lock()
        values[index] = value
        lock.unlock()
    }
}
