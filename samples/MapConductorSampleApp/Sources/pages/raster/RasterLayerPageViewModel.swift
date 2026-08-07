import Foundation
import MapConductorCore

struct GsiLayer: Identifiable {
    let id: String
    let displayName: String
    let source: RasterLayerSource
}

enum DefaultGsiLayers {
    static let nasa = GsiLayer(
        id: "nasa",
        displayName: "Relief map",
        source: .urlTemplate(
            template: "https://gibs.earthdata.nasa.gov/wmts/epsg3857/best/" +
                "MODIS_Terra_CorrectedReflectance_TrueColor/default/2024-01-01/" +
                "GoogleMapsCompatible_Level9/{z}/{y}/{x}.jpg",
            tileSize: 256,
            minZoom: 5,
            maxZoom: 15,
            attributionRules: [
                AttributionRule(
                    attribution: "NASA Global Imagery Browse Services（GIBS / EOSDIS）"
                )
            ]
        )
    )

    static let standard = GsiLayer(
        id: "standard",
        displayName: "Standard map (電子国土基本図)",
        source: .urlTemplate(
            template: "https://cyberjapandata.gsi.go.jp/xyz/std/{z}/{x}/{y}.png",
            tileSize: 256,
            minZoom: 5,
            maxZoom: 18,
            attributionRules: [
                AttributionRule(
                    attribution: "<a href=\"https://maps.gsi.go.jp/development/ichiran.html\">地理院タイル</a>"
                ),
                AttributionRule(
                    attribution: "The bathymetric contours are derived from those contained within " +
                        "the GEBCO Digital Atlas, published by the BODC on behalf of IOC and IHO " +
                        "(2003) (<a href=\"https://www.gebco.net\">https://www.gebco.net</a>)",
                    minZoom: 5,
                    maxZoom: 8
                ),
                AttributionRule(
                    attribution: "海上保安庁許可第292502号（水路業務法第25条に基づく類似刊行物）",
                    minZoom: 5,
                    maxZoom: 8
                ),
                AttributionRule(
                    attribution: "Shoreline data is derived from: United States. National Imagery " +
                        "and Mapping Agency. &quot;Vector Map Level 0 (VMAP0).&quot; Bethesda, MD: " +
                        "Denver, CO: The Agency; USGS Information Services, 1997.",
                    minZoom: 5,
                    maxZoom: 8
                )
            ]
        )
    )

    static let all = [nasa, standard]
}

final class RasterLayerPageViewModel: ObservableObject {
    let initCameraPosition: MapCameraPosition
    let availableLayers: [GsiLayer]
    let rasterLayerState: RasterLayerState

    @Published private(set) var opacity: Double
    @Published private(set) var selectedLayer: GsiLayer

    init(
        layers: [GsiLayer] = DefaultGsiLayers.all,
        initialLayer: GsiLayer = DefaultGsiLayers.nasa
    ) {
        precondition(!layers.isEmpty, "At least one GSI layer must be injected")
        precondition(Set(layers.map(\.id)).count == layers.count, "Injected GSI layer IDs must be unique")
        precondition(layers.contains { $0.id == initialLayer.id }, "The initial GSI layer must be included")

        let selectedLayer = layers.first { $0.id == initialLayer.id }!
        let initialOpacity = 0.75

        self.availableLayers = layers
        self.selectedLayer = selectedLayer
        self.opacity = initialOpacity
        self.initCameraPosition = MapCameraPosition(
            position: GeoPoint(latitude: 35.6812, longitude: 139.7671),
            zoom: 7.0,
            bearing: 0.0,
            tilt: 0.0,
            paddings: nil
        )
        self.rasterLayerState = RasterLayerState(
            source: selectedLayer.source,
            opacity: initialOpacity,
            id: "rasterLayer"
        )
    }

    func selectLayer(_ layer: GsiLayer) {
        guard let selected = availableLayers.first(where: { $0.id == layer.id }) else {
            assertionFailure("Unknown GSI layer: \(layer.id)")
            return
        }
        selectedLayer = selected
        rasterLayerState.source = selected.source
    }

    func setOpacity(_ value: Double) {
        let resolved = min(max(value, 0.0), 1.0)
        opacity = resolved
        rasterLayerState.opacity = resolved
    }
}
