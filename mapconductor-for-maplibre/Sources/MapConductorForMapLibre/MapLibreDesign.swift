import Foundation
import MapConductorCore

public protocol MapLibreMapDesignTypeProtocol: MapDesignTypeProtocol where Identifier == String {
    var styleJsonURL: String { get }
}

public typealias MapLibreMapDesignType = any MapLibreMapDesignTypeProtocol

public struct MapLibreDesign: MapLibreMapDesignTypeProtocol, Hashable {
    public let id: String
    public let styleJsonURL: String

    public init(id: String, styleJsonURL: String) {
        self.id = id
        self.styleJsonURL = styleJsonURL
    }

    public func getValue() -> String {
        "mapDesign_id=\(id),style=\(styleJsonURL)"
    }

    public static let DemoTiles = MapLibreDesign(
        id: "demo",
        styleJsonURL: "https://demotiles.maplibre.org/style.json"
    )

    public static let MapTilerTonerJa = MapLibreDesign(
        id: "maptiler-toner-ja",
        styleJsonURL: "https://tile.openstreetmap.jp/styles/maptiler-toner-ja/style.json"
    )

    public static let MapTilerTonerEn = MapLibreDesign(
        id: "maptiler-toner-en",
        styleJsonURL: "https://tile.openstreetmap.jp/styles/maptiler-toner-en/style.json"
    )

    public static let OsmBright = MapLibreDesign(
        id: "osm-bright",
        styleJsonURL: "https://tile.openstreetmap.jp/styles/osm-bright/style.json"
    )

    public static let OsmBrightEn = MapLibreDesign(
        id: "osm-bright-en",
        styleJsonURL: "https://tile.openstreetmap.jp/styles/osm-bright-en/style.json"
    )

    public static let OsmBrightJa = MapLibreDesign(
        id: "osm-bright-ja",
        styleJsonURL: "https://tile.openstreetmap.jp/styles/osm-bright-ja/style.json"
    )

    public static let MapTilerBasicEn = MapLibreDesign(
        id: "maptiler-basic-en",
        styleJsonURL: "https://tile.openstreetmap.jp/styles/maptiler-basic-en/style.json"
    )

    public static let OpenMapTiles = MapLibreDesign(
        id: "openmaptiles",
        styleJsonURL: "https://tile.openstreetmap.jp/styles/openmaptiles/style.json"
    )

    public static let MapTilerBasicJa = MapLibreDesign(
        id: "maptiler-basic-ja",
        styleJsonURL: "https://tile.openstreetmap.jp/styles/maptiler-basic-ja/style.json"
    )
}
