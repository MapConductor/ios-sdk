# MapConductor KML Layer

`ios-kml` adds a tile-rendered KML overlay to MapConductor map views. It parses OGC KML 2.2
documents (and KMZ archives) into feature models, renders them through MapConductor's raster tile
layer pipeline, and provides hit-testing for feature selection.

It shares the tile-rendering architecture of `ios-geojson-layer`: rendering is tile based and
parsed features are supplied as lightweight data objects, so it scales to large KML datasets.

## Features

- Parses `Point`, `LineString`, `LinearRing`, `Polygon` (with `innerBoundaryIs` holes),
  and `MultiGeometry`.
- Reads KMZ archives transparently: ZIP input is detected by signature and the first `.kml`
  entry (conventionally `doc.kml`) is used as the document.
- Traverses nested `<Document>` and `<Folder>` containers with explicit context stacks —
  never recursion — so arbitrarily deep hierarchies cannot overflow the call stack.
- Follows `<NetworkLink>` references (KML documents hosted elsewhere on the internet) through
  `KMLLoader`, with relative-href resolution, cycle detection, and a document-count cap.
- Resolves KML styling: `LineStyle` (color, width), `PolyStyle` (color, fill, outline),
  and `IconStyle` (color), including shared `<Style>` / `<StyleMap>` references via `styleUrl`.
  KML `aabbggrr` colors are converted to `UIColor`.
- Reads `<name>`, `<description>`, and `<ExtendedData>` (`Data`/`SchemaData`) into feature
  properties.
- Supports static bulk features with `KMLFeature`.
- Supports reactive SwiftUI features with `KMLFeatureState`.
- Supports layer-level and feature-level styling with a pluggable `KMLStyleProvider`.
- Provides touch hit-testing through `KMLLayerState.processClick`.

## Installation

When developing inside the MapConductor SDK repository, add the local package:

```swift
dependencies: [
    .package(path: "../ios-kml"),
]
```

For published artifacts, use the configured MapConductor coordinates:

```swift
dependencies: [
    .package(url: "https://github.com/MapConductor/ios-kml", from: "1.0.0"),
]
```

Or with CocoaPods:

```ruby
pod "MapConductorKML"
```

The module depends on `MapConductorCore` (and links zlib for KMZ decompression).

## Basic Usage

Parse a KML file from the app bundle and render it inside any MapConductor map view content scope:

```swift
struct KMLExample: View {
    @StateObject private var layerState = KMLLayerState(
        // Fallback style used when a placemark carries no KML <Style>.
        layerStyle: KMLTileRenderer.LayerStyle(
            strokeColor: UIColor(red: 250 / 255, green: 36 / 255, blue: 29 / 255, alpha: 1.0),
            fillColor: UIColor(red: 250 / 255, green: 36 / 255, blue: 29 / 255, alpha: 96 / 255),
            strokeWidth: 3,
            pointRadius: 8
        )
    )
    @State private var features: [KMLFeature] = []

    var body: some View {
        MapLibreMapView(state: mapState) {
            KMLLayer(state: layerState, features: features)
        }
        .task {
            guard let url = Bundle.main.url(forResource: "sample", withExtension: "kml"),
                  let data = try? Data(contentsOf: url) else { return }
            features = (try? KMLParser.parse(data: data)) ?? []
        }
        .onAppear {
            layerState.onClick = { feature, position in
                // feature.properties holds <name>, <description>, and <ExtendedData> values
            }
        }
    }
}
```

### Loading from a URL / following NetworkLinks

`KMLParser` only reads the document you give it; `<NetworkLink>` references are collected but
not fetched. Use `KMLLoader` to fetch a KML/KMZ from a URL and merge every linked document into
one feature list:

```swift
let loader = KMLLoader(onDocumentError: { url, error in
    print("KML: skipped \(url): \(error)")
})

// From the network (http/https, redirects followed; KMZ detected automatically):
features = try await loader.load(url: "https://example.com/regions.kmz")

// From data you loaded yourself; relative NetworkLink hrefs resolve against baseURL:
features = try await loader.load(data: kmlData, baseURL: "https://example.com/sample.kml")
```

Linked documents are fetched iteratively with a queue and a visited set: cyclic references are
fetched only once, and at most `maxDocuments` (default 20) documents are read. Links with
`visibility` set to `0` are not followed, and refresh modes (`refreshInterval` etc.) are not
supported — each document is read once. If you need the raw link list instead, call
`KMLParser.parseDocument(data:)`, which returns a `KMLDocument` holding `features` and
`networkLinks`.

Call `KMLLayerState.processClick` from your map's `onMapClick` handler to hit-test features:

```swift
onMapClick: { clicked in
    layerState.processClick(geoPoint: clicked, pixelTolerance: 12, zoom: state.cameraPosition.zoom)
}
```

## Styling

Each `KMLFeature` produced by `KMLParser` carries the stroke/fill/width resolved from its KML
style. Feature-level values take precedence over the `KMLLayerState` defaults. To fully customize
resolution (for example, coloring by a property value), supply a `KMLStyleProvider`:

```swift
final class CategoryStyler: KMLStyleProvider {
    func style(
        for feature: KMLFeature,
        defaultStyle: KMLTileRenderer.LayerStyle
    ) -> KMLTileRenderer.LayerStyle {
        let isStation = feature.properties["category"] as? String == "station"
        return KMLTileRenderer.LayerStyle(
            strokeColor: defaultStyle.strokeColor,
            fillColor: isStation ? .green : defaultStyle.fillColor,
            strokeWidth: defaultStyle.strokeWidth,
            pointRadius: defaultStyle.pointRadius
        )
    }
}

layerState.styleProvider = CategoryStyler()
```

## License

Apache License 2.0. See the repository `LICENSE` file.
