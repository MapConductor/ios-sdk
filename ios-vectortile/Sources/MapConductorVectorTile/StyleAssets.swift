import Foundation

/**
 Glyph ranges and sprite sheets kept on disk between launches.

 These are the slowest part of a cold start and the least likely to change: a
 glyph range is a 0.4-1.3 second round trip, a low zoom wants dozens of them,
 and the bytes for a given range never change. Keeping them means the second
 launch draws labelled tiles immediately instead of drawing them bare and
 handing them over a moment later.

 Deliberately the caller's choice of directory rather than something this
 module digs out for itself: apps have their own opinions about cache location
 and lifetime, and a library helping itself to disk behind their back is not a
 favour.
 */
public final class StyleAssetCache {
    private let directory: URL
    private let queue = DispatchQueue(label: "mapconductor.vectortile.assets", attributes: .concurrent)

    public init?(directory: URL) {
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true
            )
        } catch {
            return nil
        }
        self.directory = directory
    }

    /// A file name that cannot collide and cannot escape the directory.
    ///
    /// URLs carry slashes, query strings and characters a file system will not
    /// take, so the key is hashed rather than sanitised — sanitising is how two
    /// different URLs end up sharing one entry.
    private func path(for key: String) -> URL {
        directory.appendingPathComponent(Digest.hex(key))
    }

    public func get(_ key: String) -> Data? {
        queue.sync { try? Data(contentsOf: path(for: key)) }
    }

    public func put(_ key: String, _ value: Data) {
        queue.async(flags: .barrier) {
            // A partial write must not be read back as a whole asset.
            try? value.write(to: self.path(for: key), options: .atomic)
        }
    }
}

/// A stable short hash, used for cache keys.
///
/// FNV-1a rather than a cryptographic digest: these are file names, not
/// signatures, and the whole point is to be cheap.
enum Digest {
    static func hex(_ values: String...) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for value in values {
            for byte in value.utf8 {
                hash ^= UInt64(byte)
                hash = hash &* 0x1_0000_01b3
            }
            // Separator, so ("ab", "c") and ("a", "bc") differ.
            hash ^= 0xff
            hash = hash &* 0x1_0000_01b3
        }
        return String(hash, radix: 16)
    }
}
