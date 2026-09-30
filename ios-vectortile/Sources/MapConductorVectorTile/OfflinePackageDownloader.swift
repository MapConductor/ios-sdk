import Foundation

/**
 Fetches everything a style needs to draw one area and writes an
 ``OfflinePackage``.

 What "everything" is comes from the renderer, not from guessing at the
 style: `plan` says which source tiles each display tile reads (including
 the shallower tile a magnified level reads from, so a source that stops at
 z14 is not asked for z15), and `neededGlyphs` says which font ranges the
 labels in those tiles use -- fetching every range a CJK font has would be
 eighty files per font, nearly all unused. The sprite comes in both
 resolutions, since the two platforms' rasterisers ask for different ones.
 */
public enum OfflinePackageDownloader {
    public enum Phase: String, Sendable { case planning, tiles, glyphs, sprite, done }

    public struct Progress: Equatable, Sendable, CustomStringConvertible {
        public let phase: Phase
        public let done: Int
        public let total: Int

        public var description: String { "\(phase.rawValue) \(done)/\(total)" }
    }

    /// A bounds and zoom range that would need more tiles than this is refused.
    public static let maxTiles = 20_000

    public enum DownloadError: Error, CustomStringConvertible {
        case zoomRange(Int, Int)
        case tooManyTiles(Int)
        case glyphTemplate(String)

        public var description: String {
            switch self {
            case .zoomRange(let a, let b): return "zoom range \(a)..\(b)"
            case .tooManyTiles(let max): return "more than \(max) tiles; shrink the area or the zoom range"
            case .glyphTemplate(let t): return "glyph template must name {fontstack} then {range}: \(t)"
            }
        }
    }

    /**
     - Parameters:
       - styleJSON: the style, with absolute source, glyph and sprite URLs
       - bounds: the area, in degrees
       - minZoom: the shallowest display zoom to cover; 0 costs one tile
       - maxZoom: the deepest display zoom; sources deeper than their own
         `maxzoom` are magnified from it, so this can exceed the data's zoom
       - directory: where the package goes; anything there is replaced
       - fetch: how bytes are got; nil for plain HTTP with `headers`
     */
    public static func download(
        styleJSON: String,
        bounds: OfflinePackage.Bounds,
        minZoom: Int = 0,
        maxZoom: Int = 14,
        directory: URL,
        headers: [String: String] = [:],
        parallelism: Int = 8,
        fetch: ((URL) -> Data?)? = nil,
        onProgress: @escaping @Sendable (Progress) -> Void = { _ in }
    ) async throws -> OfflinePackage {
        guard minZoom >= 0, minZoom <= maxZoom, maxZoom <= 22 else { throw DownloadError.zoomRange(minZoom, maxZoom) }
        let get: (URL) -> Data? = fetch ?? { url in VectorTileProvider.get(url, headers: headers, cancellation: nil) }
        let renderer = try VectorTileRenderer(styleJSON: styleJSON, displayTileSize: VectorTileProvider.defaultTileSize)
        defer { renderer.close() }

        let files = FileManager.default
        try? files.removeItem(at: directory)
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(styleJSON.utf8).write(to: directory.appendingPathComponent(OfflinePackage.styleFile), options: .atomic)

        // --- plan: which source tiles, for which display tiles ---
        onProgress(Progress(phase: .planning, done: 0, total: 0))
        struct DisplayTile { let z: UInt8; let x: UInt32; let y: UInt32; let urls: [String?] }
        var displayTiles: [DisplayTile] = []
        var wanted: [(url: String, relative: String)] = []
        var wantedSet = Set<String>()
        for z in minZoom...maxZoom {
            let n = 1 << z
            let x0 = min(max(tileX(bounds.west, z), 0), n - 1)
            let x1 = min(max(tileX(bounds.east, z), 0), n - 1)
            let y0 = min(max(tileY(bounds.north, z), 0), n - 1)
            let y1 = min(max(tileY(bounds.south, z), 0), n - 1)
            for x in min(x0, x1)...max(x0, x1) {
                for y in min(y0, y1)...max(y0, y1) {
                    try Task.checkCancellation()
                    let json = try renderer.plan(z: UInt8(z), x: UInt32(x), y: UInt32(y))
                    let plan = (try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]]) ?? []
                    var urls: [String?] = []
                    for entry in plan {
                        // Neighbours wanted only for label placement at the
                        // edge are left out: they lie outside the area, and
                        // a package is what is inside it.
                        if entry["labelsOnly"] as? Bool ?? false {
                            urls.append(nil)
                            continue
                        }
                        guard let url = entry["url"] as? String else {
                            urls.append(nil)
                            continue
                        }
                        urls.append(url)
                        if wantedSet.insert(url).inserted {
                            let relative = "\(OfflinePackage.tilesDir)/\(entry["sourceId"] as? String ?? "source")/"
                                + "\(entry["z"] ?? 0)/\(entry["x"] ?? 0)/\(entry["y"] ?? 0).mvt"
                            wanted.append((url, relative))
                            if wanted.count > maxTiles { throw DownloadError.tooManyTiles(maxTiles) }
                        }
                    }
                    displayTiles.append(DisplayTile(z: UInt8(z), x: UInt32(x), y: UInt32(y), urls: urls))
                }
            }
        }

        // --- tiles ---
        let total = wanted.count
        onProgress(Progress(phase: .tiles, done: 0, total: total))
        let index = Index()
        let width = max(1, parallelism)
        try await withThrowingTaskGroup(of: Void.self) { group in
            var next = 0
            var running = 0
            func launch(_ item: (url: String, relative: String)) {
                group.addTask {
                    try Task.checkCancellation()
                    if let target = VectorTileProvider.parse(item.url), let data = get(target), !data.isEmpty {
                        try write(directory: directory, relative: item.relative, data: data)
                        index.record(url: item.url, relative: item.relative, bytes: data.count)
                    }
                    onProgress(Progress(phase: .tiles, done: index.done(), total: total))
                }
            }
            while next < wanted.count, running < width {
                launch(wanted[next]); next += 1; running += 1
            }
            while running > 0 {
                try await group.next()
                running -= 1
                if next < wanted.count { launch(wanted[next]); next += 1; running += 1 }
            }
        }

        // --- glyphs: what the fetched tiles' labels need ---
        let glyphTemplate = try renderer.glyphsURLTemplate()
        let glyphMatcher = try glyphTemplate.map(templateRegex)
        var glyphCount = 0
        onProgress(Progress(phase: .glyphs, done: 0, total: displayTiles.count))
        if let glyphMatcher {
            for (i, tile) in displayTiles.enumerated() {
                try Task.checkCancellation()
                let data: [Data?] = tile.urls.map { url in
                    guard let url, let relative = index.relative(for: url) else { return nil }
                    return try? Data(contentsOf: directory.appendingPathComponent(relative))
                }
                let needed = (try? renderer.neededGlyphs(z: tile.z, x: tile.x, y: tile.y, tiles: data)) ?? []
                for url in needed {
                    if index.relative(for: url) != nil { continue }
                    guard
                        let match = glyphMatcher.firstMatch(in: url, range: NSRange(url.startIndex..., in: url)),
                        let fontstackRange = Range(match.range(at: 1), in: url),
                        let rangeRange = Range(match.range(at: 2), in: url)
                    else { continue }
                    let fontstack = String(url[fontstackRange]).removingPercentEncoding ?? String(url[fontstackRange])
                    let range = String(url[rangeRange])
                    guard let target = VectorTileProvider.parse(url), let pbf = get(target), !pbf.isEmpty else { continue }
                    let relative = "\(OfflinePackage.glyphsDir)/\(fontstack)/\(range).pbf"
                    try write(directory: directory, relative: relative, data: pbf)
                    index.record(url: url, relative: relative, bytes: pbf.count)
                    glyphCount += 1
                    // Fed back so the next tile asks only for what is still missing.
                    _ = try? renderer.addGlyphs(pbf)
                }
                onProgress(Progress(phase: .glyphs, done: i + 1, total: displayTiles.count))
            }
        }

        // --- sprite, both resolutions ---
        onProgress(Progress(phase: .sprite, done: 0, total: 2))
        var spriteCount = 0
        for ratio in 1...2 {
            guard let urls = try? renderer.spriteURLs(pixelRatio: UInt32(ratio)) else { continue }
            let suffix = ratio > 1 ? "@2x" : ""
            for (url, ext) in [(urls.json, "json"), (urls.png, "png")] {
                guard let target = VectorTileProvider.parse(url), let data = get(target), !data.isEmpty else { continue }
                let relative = "\(OfflinePackage.spriteFile)\(suffix).\(ext)"
                try write(directory: directory, relative: relative, data: data)
                index.record(url: url, relative: relative, bytes: data.count)
                spriteCount += 1
            }
            onProgress(Progress(phase: .sprite, done: ratio, total: 2))
        }

        let style = (try? JSONSerialization.jsonObject(with: Data(styleJSON.utf8)) as? [String: Any]) ?? [:]
        var templates: [String: String] = [:]
        for (id, value) in style["sources"] as? [String: Any] ?? [:] {
            if let source = value as? [String: Any], let tiles = source["tiles"] as? [String], let first = tiles.first {
                templates[id] = first
            }
        }
        let snapshot = index.snapshot()
        let manifest = OfflinePackage.Manifest(
            bounds: bounds,
            minZoom: minZoom,
            maxZoom: maxZoom,
            styleDigest: Digest.hex(styleJSON),
            createdAt: Int64(Date().timeIntervalSince1970 * 1000),
            tiles: snapshot.entries.values.filter { $0.hasPrefix("\(OfflinePackage.tilesDir)/") }.count,
            glyphs: glyphCount,
            sprites: spriteCount,
            bytes: snapshot.bytes,
            sources: templates,
            glyphsTemplate: glyphTemplate,
            spriteBase: style["sprite"] as? String
        )
        onProgress(Progress(phase: .done, done: total, total: total))
        return try OfflinePackage.create(directory: directory, manifest: manifest, index: snapshot.entries)
    }

    /// The URL -> path map being built, from several tasks at once.
    private final class Index: @unchecked Sendable {
        private let lock = NSLock()
        private var entries: [String: String] = [:]
        private var bytes: Int64 = 0
        private var completed = 0

        func record(url: String, relative: String, bytes: Int) {
            lock.lock()
            entries[url] = relative
            self.bytes += Int64(bytes)
            lock.unlock()
        }

        func done() -> Int {
            lock.lock()
            defer { lock.unlock() }
            completed += 1
            return completed
        }

        func relative(for url: String) -> String? {
            lock.lock()
            defer { lock.unlock() }
            return entries[url]
        }

        func snapshot() -> (entries: [String: String], bytes: Int64) {
            lock.lock()
            defer { lock.unlock() }
            return (entries, bytes)
        }
    }

    private static func write(directory: URL, relative: String, data: Data) throws {
        let file = directory.appendingPathComponent(relative)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try data.write(to: file, options: .atomic)
    }

    /// `{fontstack}` and `{range}` as capture groups; everything else literal.
    private static func templateRegex(_ template: String) throws -> NSRegularExpression {
        guard
            let fontstack = template.range(of: "{fontstack}"),
            let range = template.range(of: "{range}"),
            fontstack.upperBound <= range.lowerBound
        else { throw DownloadError.glyphTemplate(template) }
        let head = NSRegularExpression.escapedPattern(for: String(template[..<fontstack.lowerBound]))
        let middle = NSRegularExpression.escapedPattern(for: String(template[fontstack.upperBound..<range.lowerBound]))
        let tail = NSRegularExpression.escapedPattern(for: String(template[range.upperBound...]))
        return try NSRegularExpression(pattern: "^\(head)(.+)\(middle)(\\d+-\\d+)\(tail)$")
    }

    private static func tileX(_ lon: Double, _ z: Int) -> Int {
        Int(floor((lon + 180.0) / 360.0 * Double(1 << z)))
    }

    private static func tileY(_ lat: Double, _ z: Int) -> Int {
        let clamped = min(max(lat, -85.05112878), 85.05112878)
        let rad = clamped * .pi / 180
        return Int(floor((1.0 - log(tan(rad) + 1.0 / cos(rad)) / .pi) / 2.0 * Double(1 << z)))
    }
}
