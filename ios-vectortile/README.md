# MapConductor Vector Tile

## Description

MapConductor Vector Tile draws a MapLibre vector style on **any** map implementation, by rasterising the style to tiles on the device and serving them through the SDK's local tile server.

The backend only ever sees an ordinary raster layer. That is what makes it work on MapKit, Google Maps, HERE, ArcGIS, TomTom and the rest — none of which can render a vector style themselves.

The renderer is a Rust core shared with the Android and web modules, so the same style and the same source tile produce a byte-identical PNG on all three platforms.

## Setup

https://docs-ios.mapconductor.com/setup/

------------------------------------------------------------------------

## Usage

Unlike the Android module there is no SwiftUI wrapper: you hold a `VectorTileProvider`, register its two tile routes, and point two `RasterLayerState`s at them.

### Creating the provider

```swift
import MapConductorCore
import MapConductorVectorTile

let cacheDirectory = FileManager.default
    .urls(for: .cachesDirectory, in: .userDomainMask)
    .first?
    .appendingPathComponent("vectortile")

let provider = try VectorTileProvider(
    styleJSON: styleText,
    tileSize: 512,
    assetCacheDirectory: cacheDirectory
)
```

`styleJSON` is the text of a `style.json`. Fetching it is the caller's job — the provider does not decide how your app does network I/O.

### Registering the two routes

```swift
let server = TileServerRegistry.get()
server.register(routeId: groundRoute, provider: provider.groundTiles)
server.register(routeId: labelRoute, provider: provider.labelTiles)

ground = RasterLayerState(
    source: .urlTemplate(
        template: server.urlTemplate(
            routeId: groundRoute, tileSize: 512, cacheKey: "static"
        ),
        tileSize: 512,
        maxZoom: 22,
        attributionRules: provider.attributions().map { AttributionRule(attribution: $0) }
    ),
    zIndex: 0
)
```

### Replacing the labels when glyphs arrive

Glyph ranges arrive after the tiles that need them — a range is a round trip and a low-zoom tile wants dozens — so tiles are drawn with whatever is loaded and the overlay is replaced once more lands.

```swift
provider.onGlyphsLoaded = { [weak self] in
    Task { @MainActor in self?.handOverLabels() }
}
```

Give the replacement overlay a new `cacheKey` so the map refetches it, and a `zIndex` above the ground. Only the overlay changes, so the worst a handover can cost is a moment of the labels being redrawn, never a bare map.

### Tearing down

```swift
server.unregister(routeId: groundRoute)
server.unregister(routeId: labelRoute)
provider.close()
```

`ios-sdk/samples/MapConductorSampleApp` has the whole flow in `VectorTilePageViewModel`.

------------------------------------------------------------------------

## How it draws

The style is served as **two** stacked raster layers, not one:

- **`groundTiles`** — fills, lines and circles, the half no font arriving can change
- **`labelTiles`** — labels and icons on a transparent ground, replaced on its own when glyph ranges land

To the map and the user they read as one layer. The halves render in parallel, and a glyph range landing redraws only the transparent one.

### Tile size

Only 512 and 1024 are usable. MapKit's tile grid is built from 256, and a size that is not a power-of-two multiple of it draws a blank map — 768 was tried and drew nothing at all.

Raising `tileSize` is not a lever for label size. Apparent size works out to the style's own value times `tileSize / 512`, but the number of tiles across the screen scales the same way, so doubling it is exactly a one-step zoom: the map gets bigger and the text keeps its size *relative to the map*. Text too small relative to the map is the style's `text-size`, and nothing here can change that.

------------------------------------------------------------------------

## API Reference

### VectorTileProvider.init

| Parameter | Type | Default | Description |
|---|---|---|---|
| `styleJSON` | `String` | — | The text of a `style.json` |
| `tileSize` | `Int` | `512` | Output tile size in pixels |
| `headers` | `[String: String]` | empty | Sent with every source tile request — auth tokens, API keys |
| `cacheBytes` | `Int` | 16 MiB | In-memory tile cache budget |
| `renderMode` | `RenderMode` | `.auto` | Which rasteriser to use |
| `assetCacheDirectory` | `URL?` | `nil` | Where to keep glyphs, sprites and rendered tiles between launches; nil disables all three |
| `renderedCacheBytes` | `Int` | 48 MiB | On-disk budget for rendered tiles |
| `renderScale` | `Int?` | display scale | Pixels drawn per point of screen |
| `fetchTile` | `((URL) -> Data?)?` | `nil` | Override how source tiles are fetched |

Throws if the style cannot be parsed.

### VectorTileProvider

| Member | Description |
|---|---|
| `groundTiles` | Tile provider for fills, lines and circles |
| `labelTiles` | Tile provider for labels and icons, on a transparent ground |
| `onGlyphsLoaded` | Called when a glyph range lands and the label overlay is worth replacing |
| `attributions()` | Credits the style's sources ask to be shown |
| `diagnostics()` | Reasons the style may not render as intended |
| `setStyle(_:)` | Replaces the paint without refetching: the geometry is unchanged, only the paint applied to it, so recolouring costs a re-rasterise and no network traffic. The caller still has to make the map drop its *raster* tiles — pass a new `cacheKey` to `urlTemplate` |
| `renderMode` | Which rasteriser was actually obtained |
| `gpuRenders` / `gpuFallbacks` | Counters for how the GPU path is faring |
| `close()` | Releases the renderer and its caches |

### RenderMode

| Value | Description |
|---|---|
| `.cpu` | `tiny-skia`. Always available, and the only path that draws every layer type the renderer supports. |
| `.gpu` | Metal — rather than OpenGL ES, which has been deprecated on iOS since 12. Roughly twice as fast per tile and, the reason it exists, it spends the map's time on a processor the rest of the app is not competing for. |
| `.auto` | `.gpu` where it initialises, `.cpu` otherwise. |

------------------------------------------------------------------------

## License

Apache License 2.0. See [LICENSE](./LICENSE).
