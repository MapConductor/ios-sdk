import Foundation
import MapConductorCore

final class RasterLayerPageViewModel: ObservableObject {
    let initCameraPosition: MapCameraPosition
    let rasterLayerState: RasterLayerState

    init() {
        let center = GeoPoint(latitude: 35.681236, longitude: 139.767125)
        self.initCameraPosition = MapCameraPosition(
            position: center,
            zoom: 5.0,
            bearing: 0.0,
            tilt: 0.0,
            paddings: nil
        )

        let source = RasterSource.urlTemplate(
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
        self.rasterLayerState = RasterLayerState(source: source)
    }
}
