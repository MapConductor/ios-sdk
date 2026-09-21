import Foundation

/**
 Stores rendered PNG tiles on disk, keyed by style and coordinates.

 This does not make the first view of an area faster — nothing can, the tiles
 have to be fetched and rasterised once. What it removes is paying that cost
 *again* on the next launch. Within a single session the map SDK already caches
 raster tiles itself, so this is specifically about surviving process death.

 Entries are content-addressed, so a restyle simply misses rather than needing
 explicit invalidation.
 */
final class TileDiskCache {
    private let directory: URL
    private let budgetBytes: Int
    private let queue = DispatchQueue(label: "mapconductor.vectortile.tiles", attributes: .concurrent)

    /// Writes since the last sweep. Eviction is amortised rather than paid on
    /// every write: listing a directory costs more than the write did.
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
        directory.appendingPathComponent("\(key).png")
    }

    func get(_ key: String) -> Data? {
        queue.sync {
            let path = file(key)
            guard let bytes = try? Data(contentsOf: path), !bytes.isEmpty else { return nil }
            // Touch, so the sweep evicts genuinely cold entries rather than
            // whichever happened to be written first.
            try? FileManager.default.setAttributes(
                [.modificationDate: Date()], ofItemAtPath: path.path
            )
            return bytes
        }
    }

    func put(_ key: String, _ bytes: Data) {
        queue.async(flags: .barrier) {
            // Atomic write: two threads rendering the same tile must not leave
            // a half-written file behind for a third to read.
            guard (try? bytes.write(to: self.file(key), options: .atomic)) != nil else { return }
            self.writesSinceSweep += 1
            if self.writesSinceSweep % TileDiskCache.sweepEvery == 0 { self.sweep() }
        }
    }

    /// Drops the least recently used files until the budget is met.
    ///
    /// Called on the barrier queue, so it already has exclusive access.
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

    /**
     Waits for writes already queued to reach disk.

     Writes are queued rather than paid for on the render thread, which means a
     provider closed straight after drawing — or an app put into the background
     — can drop the tile it just made. Not a hypothetical: the test that stands
     in for a second launch started missing as soon as the tiles got bigger.
     */
    func flush() {
        queue.sync(flags: .barrier) {}
    }

    func clear() {
        queue.async(flags: .barrier) {
            guard let entries = try? FileManager.default.contentsOfDirectory(
                at: self.directory, includingPropertiesForKeys: nil
            ) else { return }
            for url in entries { try? FileManager.default.removeItem(at: url) }
        }
    }
}
