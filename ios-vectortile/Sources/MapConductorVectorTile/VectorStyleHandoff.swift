import Foundation
import MapConductorCore

/**
 Hands a style to a map that draws vector styles itself.

 The style document is served by the SDK's local tile server and the map is
 told, through its ``VectorStyleSupport``, to make it its basemap. Nothing is
 rasterised: on MapLibre, Mapbox and MapTiler this is the whole of what
 "vector tile layer as basemap" has to do, and it is the path an offline
 package will take. A map without the capability cannot use this; it gets
 ``VectorTileProvider`` and raster layers instead.

 The document id is the content and nothing else. The map only re-reads a
 style whose URL changed, so a changed style has to change the URL; but a
 host that rebuilds its overlay content on a design change hands the style
 over again from the rebuilt content, and if that minted a fresh URL it would
 be a fresh design, another rebuild, and so on. Same content, same URL, and
 the second handoff is a no-op.
 */
public final class VectorStyleHandoff {
    public let documentId: String
    public let url: String
    /// The credits the style's sources ask for, in style order, without duplicates.
    public let attributions: [String]
    public let support: VectorStyleSupport

    private let server: LocalTileServer
    private var disposed = false

    /// The files route serving the package, when there is one.
    public let filesRoute: String?

    /**
     - Parameters:
       - offlinePackage: a package the map reads its tiles, glyphs and sprite
         from through the local server, which answers from the package and --
         while `online` -- fetches upstream for the rest. The route carries the
         mode: a map remembers a tile it was told does not exist, so going back
         online has to change the URLs to be noticed.
       - headers: sent with upstream fetches made for the package
     */
    public init(
        styleJSON: String,
        support: VectorStyleSupport,
        server: LocalTileServer = TileServerRegistry.get(),
        offlinePackage: OfflinePackage? = nil,
        online: Bool = true,
        headers: [String: String] = [:]
    ) {
        self.support = support
        self.server = server
        let served: String
        if let offlinePackage {
            let route = "vectortile-package-\(offlinePackage.manifest.styleDigest.prefix(12))-\(online ? "online" : "offline")"
            filesRoute = route
            var fallback: (@Sendable (String) -> Data?)?
            if online {
                fallback = { relative in
                    guard
                        let upstream = offlinePackage.upstreamURL(forRelativePath: relative),
                        let target = VectorTileProvider.parse(upstream)
                    else { return nil }
                    return VectorTileProvider.get(target, headers: headers, cancellation: nil)
                }
            }
            server.registerFiles(routeId: route, directory: offlinePackage.directory, fallback: fallback)
            served = offlinePackage.styleServed(by: server.filesUrl(routeId: route))
        } else {
            filesRoute = nil
            served = styleJSON
        }
        documentId = "vectortile-style-\(Self.digest(served))"
        url = server.documentUrl(id: documentId)
        attributions = Self.attributions(ofStyle: styleJSON)
        server.registerDocument(id: documentId, contentType: "application/json", body: Data(served.utf8))
        support.showStyle(url: url, attributionRules: attributions.map { AttributionRule(attribution: $0) })
    }

    /// Restores the map's previous design and stops serving the document.
    public func dispose() {
        guard !disposed else { return }
        disposed = true
        support.clearStyle()
        server.unregisterDocument(id: documentId)
        if let filesRoute { server.unregisterFiles(routeId: filesRoute) }
    }

    /**
     The `attribution` of every source in a style. A style that will not
     parse credits nothing here; the map will refuse it anyway, more visibly.
     */
    public static func attributions(ofStyle json: String) -> [String] {
        guard
            let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
            let sources = object["sources"] as? [String: Any]
        else { return [] }
        var seen = Set<String>()
        var result: [String] = []
        for key in sources.keys.sorted() {
            guard
                let source = sources[key] as? [String: Any],
                let attribution = source["attribution"] as? String,
                !attribution.trimmingCharacters(in: .whitespaces).isEmpty,
                seen.insert(attribution).inserted
            else { continue }
            result.append(attribution)
        }
        return result
    }

    /// FNV-1a over the UTF-8 bytes: stable across launches, which `hashValue` is not.
    private static func digest(_ text: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 16)
    }
}
