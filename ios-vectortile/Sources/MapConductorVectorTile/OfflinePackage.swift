import Foundation
import MapConductorCore

/**
 A style and everything it needs to draw one area, on disk.

 Downloaded by ``OfflinePackageDownloader`` and read here. The layout is
 plain files the style's own URL templates map onto, so a package can be
 served to a map that draws vector styles itself (MapLibre, Mapbox,
 MapTiler) as well as read by the rasteriser for every other map:

 ```
 manifest.json                     what is in here and where it came from
 style.json                        the style, as downloaded
 index.json                        source URL -> relative path
 tiles/<source>/<z>/<x>/<y>.mvt
 glyphs/<fontstack>/<range>.pbf
 sprite.json  sprite.png  sprite@2x.json  sprite@2x.png
 ```

 android-vectortile reads and writes the same layout, so a package made on
 one platform serves the other.
 */
public final class OfflinePackage: @unchecked Sendable {
    /// South-west to north-east, degrees.
    public struct Bounds: Codable, Equatable, Sendable {
        public var south: Double
        public var west: Double
        public var north: Double
        public var east: Double

        public init(south: Double, west: Double, north: Double, east: Double) {
            self.south = south
            self.west = west
            self.north = north
            self.east = east
        }
    }

    public struct Manifest: Codable, Sendable {
        public var version: Int = OfflinePackage.formatVersion
        public var bounds: Bounds
        public var minZoom: Int
        public var maxZoom: Int
        public var styleDigest: String
        public var createdAt: Int64
        public var tiles: Int
        public var glyphs: Int
        public var sprites: Int
        public var bytes: Int64
        /// Source id -> the tile URL template the tiles were fetched from.
        public var sources: [String: String]
        public var glyphsTemplate: String?
        public var spriteBase: String?
    }

    public let directory: URL
    public let manifest: Manifest
    private let index: [String: String]

    private init(directory: URL, manifest: Manifest, index: [String: String]) {
        self.directory = directory
        self.manifest = manifest
        self.index = index
    }

    public static let formatVersion = 1
    static let manifestFile = "manifest.json"
    static let styleFile = "style.json"
    static let indexFile = "index.json"
    static let tilesDir = "tiles"
    static let glyphsDir = "glyphs"
    static let spriteFile = "sprite"

    /// The package in `directory`, or nil when there is none or it will not parse.
    public static func open(_ directory: URL) -> OfflinePackage? {
        guard
            let manifestData = try? Data(contentsOf: directory.appendingPathComponent(manifestFile)),
            let manifest = try? JSONDecoder().decode(Manifest.self, from: manifestData),
            let indexData = try? Data(contentsOf: directory.appendingPathComponent(indexFile)),
            let index = try? JSONDecoder().decode([String: String].self, from: indexData)
        else { return nil }
        return OfflinePackage(directory: directory, manifest: manifest, index: index)
    }

    /// Removes a package, whole.
    public static func delete(_ directory: URL) {
        try? FileManager.default.removeItem(at: directory)
    }

    static func create(directory: URL, manifest: Manifest, index: [String: String]) throws -> OfflinePackage {
        let encoder = JSONEncoder()
        try encoder.encode(manifest).write(to: directory.appendingPathComponent(manifestFile), options: .atomic)
        try encoder.encode(index).write(to: directory.appendingPathComponent(indexFile), options: .atomic)
        return OfflinePackage(directory: directory, manifest: manifest, index: index)
    }

    /// The style as it was downloaded, pointing at its original servers.
    public var styleJSON: String {
        (try? String(contentsOf: directory.appendingPathComponent(Self.styleFile), encoding: .utf8)) ?? ""
    }

    /// The bytes the package holds for a source URL, or nil when it has none.
    public func bytes(for url: String) -> Data? {
        guard let relative = index[url] else { return nil }
        return try? Data(contentsOf: directory.appendingPathComponent(relative))
    }

    /// Whether the package answers for this URL.
    public func contains(_ url: String) -> Bool {
        guard let relative = index[url] else { return false }
        return FileManager.default.fileExists(atPath: directory.appendingPathComponent(relative).path)
    }

    /**
     Where a file the package does not have would come from.

     The relative path is the one the served style asks for, so it maps back
     through the same templates the package was fetched with. Nil for a path
     that is not in the package's vocabulary.
     */
    public func upstreamURL(forRelativePath relativePath: String) -> String? {
        let segments = relativePath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        if segments.count == 5, segments[0] == Self.tilesDir, segments[4].hasSuffix(".mvt") {
            guard let template = manifest.sources[segments[1]] else { return nil }
            return template
                .replacingOccurrences(of: "{z}", with: segments[2])
                .replacingOccurrences(of: "{x}", with: segments[3])
                .replacingOccurrences(of: "{y}", with: String(segments[4].dropLast(4)))
        }
        if segments.count == 3, segments[0] == Self.glyphsDir, segments[2].hasSuffix(".pbf") {
            guard let template = manifest.glyphsTemplate else { return nil }
            let fontstack = segments[1].addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? segments[1]
            return template
                .replacingOccurrences(of: "{fontstack}", with: fontstack)
                .replacingOccurrences(of: "{range}", with: String(segments[2].dropLast(4)))
        }
        if segments.count == 1, segments[0].hasPrefix(Self.spriteFile) {
            guard let base = manifest.spriteBase else { return nil }
            return base + segments[0].dropFirst(Self.spriteFile.count)
        }
        return nil
    }

    /**
     The style rewritten to read from `baseUrl`, for a map that draws the
     style itself. Every source becomes a tile template under
     `tiles/<source>/`, the glyphs and the sprite move under the same root,
     and a TileJSON `url` is dropped in favour of the tiles it named.
     */
    public func styleServed(by baseUrl: String) -> String {
        guard
            var style = try? JSONSerialization.jsonObject(with: Data(styleJSON.utf8)) as? [String: Any]
        else { return styleJSON }
        var sources = style["sources"] as? [String: Any] ?? [:]
        for (id, value) in sources {
            guard var source = value as? [String: Any], manifest.sources[id] != nil else { continue }
            source.removeValue(forKey: "url")
            source["tiles"] = ["\(baseUrl)/\(Self.tilesDir)/\(id)/{z}/{x}/{y}.mvt"]
            sources[id] = source
        }
        style["sources"] = sources
        if manifest.glyphsTemplate != nil { style["glyphs"] = "\(baseUrl)/\(Self.glyphsDir)/{fontstack}/{range}.pbf" }
        if manifest.spriteBase != nil { style["sprite"] = "\(baseUrl)/\(Self.spriteFile)" }
        guard let data = try? JSONSerialization.data(withJSONObject: style) else { return styleJSON }
        return String(decoding: data, as: UTF8.self)
    }

    /**
     How the fetches of one provider have gone so far: what the package
     answered, what went to the network, and what was refused offline.
     */
    public struct Stats: Equatable, Sendable, CustomStringConvertible {
        public var packageHits = 0
        public var networkFetches = 0
        public var blocked = 0

        public var description: String { "package=\(packageHits) network=\(networkFetches) blocked=\(blocked)" }
    }

    /**
     A `fetchTile` for ``VectorTileProvider``: the package first, then --
     while ``online`` -- the network, and otherwise nothing.

     "Nothing" is thrown rather than returned: a nil from a fetch means "there
     is no such tile" and is remembered as such, whereas a tile the network
     was not allowed to fetch is there to be had the moment it is.
     */
    public final class Fetcher: @unchecked Sendable {
        private let package: OfflinePackage
        private let upstream: (URL) -> Data?
        private let onStats: ((Stats) -> Void)?
        private let lock = NSLock()
        private var counters = Stats()
        private var _online: Bool

        public var online: Bool {
            get { lock.lock(); defer { lock.unlock() }; return _online }
            set { lock.lock(); _online = newValue; lock.unlock() }
        }

        public var stats: Stats {
            lock.lock()
            defer { lock.unlock() }
            return counters
        }

        /// - Parameter upstream: how the network is reached; nil for plain
        ///   HTTP with `headers`.
        public init(
            package: OfflinePackage,
            online: Bool = true,
            headers: [String: String] = [:],
            upstream: ((URL) -> Data?)? = nil,
            onStats: ((Stats) -> Void)? = nil
        ) {
            self.package = package
            self._online = online
            self.upstream = upstream ?? { url in VectorTileProvider.get(url, headers: headers, cancellation: nil) }
            self.onStats = onStats
        }

        public func fetch(_ url: URL) throws -> Data? {
            if let packaged = package.bytes(for: url.absoluteString) {
                bump { $0.packageHits += 1 }
                return packaged
            }
            if !online {
                bump { $0.blocked += 1 }
                throw OfflineUnavailableError(url: url.absoluteString)
            }
            bump { $0.networkFetches += 1 }
            return upstream(url)
        }

        private func bump(_ change: (inout Stats) -> Void) {
            lock.lock()
            change(&counters)
            let snapshot = counters
            lock.unlock()
            onStats?(snapshot)
        }
    }
}

/// A fetch refused because the network is off and the package has no answer.
public struct OfflineUnavailableError: Error, CustomStringConvertible {
    public let url: String

    public init(url: String) { self.url = url }

    public var description: String { "offline: \(url)" }
}
