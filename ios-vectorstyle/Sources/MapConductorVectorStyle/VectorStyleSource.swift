import Foundation
import MapConductorCore

/**
 Which style the rules are applied to.

 A rule cannot be matched against anything until the style document is in
 hand: "roads" means whichever layers *this* style draws roads with, and only
 the document says. So every path here ends in text, and the one that has to
 go and get it says so.
 */
public enum VectorStyleSource: Equatable, Sendable {
    /// The document itself. The app already has it.
    case text(String)

    /**
     A `style.json` to fetch.

     Fetched by this module rather than by the map, because the rules have to
     be compiled against it before the map is given anything.
     */
    case url(String, headers: [String: String] = [:])

    /**
     Whatever the map is already drawing.

     For adjusting a basemap the app did not supply: a MapLibre, Mapbox or
     MapTiler design. The module reads the design's style URL from
     ``MapStyleHost/vectorStyleUrl`` and fetches it; a backend that has no
     such thing cannot be adjusted this way and says so.
     */
    case currentDesign

    /// What identifies this source, for deciding whether a style changed.
    public var key: String {
        switch self {
        case let .text(json): return "text:\(json.hashValue)"
        case let .url(url, _): return "url:\(url)"
        case .currentDesign: return "current"
        }
    }
}

/**
 What to do about an adjustment the map would not take.

 Only MapLibre here reaches this today: it exposes paint properties as typed
 `NSExpression`s rather than by name, so a raw style-spec key it has no
 mapping for cannot be set.
 */
public enum UnsupportedPolicy: Sendable {
    /**
     Say so and leave the rest applied. The default, because the alternative
     makes the map reload -- and not reloading is the point.
     */
    case report

    /**
     Hand the map the adjusted document instead, so everything applies.

     Correct, and expensive: the renderer drops its tiles, re-reads the
     document and the app's overlays are rebuilt.
     */
    case reload
}

/**
 Draws a style the map cannot read itself.

 The seam between this module and the rasteriser. Declared here and
 implemented in `MapConductorVectorTile`, which is what keeps an app using
 only MapLibre from linking a megabyte of renderer it will never call. An app
 that also targets Google Maps, MapKit, HERE or ArcGIS passes one in; one
 that does not, does not, and is told so rather than shown a blank map.
 */
public protocol VectorStyleRasteriser: AnyObject {
    /**
     Starts drawing `styleJSON` as raster tiles on `host`.

     - Parameter affects: which half of the split tile layers the adjustments
       reached, so a change to labels alone need not redraw the ground.
     */
    func install(host: MapStyleHost, styleJSON: String, affects: StyleAffects)
        -> VectorStyleRasterisation
}

/// A rasteriser's work in progress.
public protocol VectorStyleRasterisation: AnyObject {
    /**
     Draws a different style with the same tiles.

     The geometry has not changed, only the paint over it, so this costs a
     re-rasterise and no network.
     */
    func restyle(styleJSON: String, affects: StyleAffects)

    func dispose()
}
