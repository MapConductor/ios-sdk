import MapConductorGeoJSON
import UIKit

final class ExampleGeoJSONStyler: GeoJSONStyleProvider {
    struct RouteKey: Hashable {
        let companyName: String
        let lineName: String
    }

    private let routeColors: [RouteKey: UIColor]

    init(routeColors: [RouteKey: UIColor]) {
        self.routeColors = routeColors
    }

    func style(
        for feature: GeoJSONFeature,
        defaultStyle: GeoJSONTileRenderer.LayerStyle
    ) -> GeoJSONTileRenderer.LayerStyle {
        let baseStyle = DefaultGeoJSONStyleProvider.shared.style(
            for: feature,
            defaultStyle: defaultStyle
        )
        guard let companyName = feature.properties[Self.companyProperty] as? String,
              let lineName = feature.properties[Self.lineProperty] as? String,
              let color = routeColors[RouteKey(companyName: companyName, lineName: lineName)] else {
            return baseStyle
        }
        return GeoJSONTileRenderer.LayerStyle(
            strokeColor: color,
            fillColor: baseStyle.fillColor,
            strokeWidth: baseStyle.strokeWidth,
            pointRadius: baseStyle.pointRadius
        )
    }

    private static let companyProperty = "N02_004"
    private static let lineProperty = "N02_003"
}
