import CoreLocation
import MapConductorCore
import MapLibre
import UIKit

func createMapLibrePolygons(
    id: String,
    points: [GeoPointProtocol],
    geodesic: Bool,
    fillColor: UIColor,
    strokeColor: UIColor,
    strokeWidth: Double,
    zIndex: Int = 0
) -> [MLNPolygonFeature] {
    let interpolated: [GeoPointProtocol] = (geodesic ? createInterpolatePoints(points, maxSegmentLength: 1000.0) : createLinearInterpolatePoints(points))
        .map { $0.normalize() }

    return splitByMeridian(interpolated, geodesic: geodesic).enumerated().map { index, ringPoints in
        let normalizedRing: [GeoPointProtocol]
        if let first = ringPoints.first, let last = ringPoints.last, GeoPoint.from(position: first) == GeoPoint.from(position: last) {
            normalizedRing = ringPoints
        } else if let first = ringPoints.first {
            normalizedRing = ringPoints + [first]
        } else {
            normalizedRing = ringPoints
        }
        let coordinates = normalizedRing.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        var coords = coordinates
        let polygon = MLNPolygonFeature(coordinates: &coords, count: UInt(coords.count))
        let fid = "polygon-\(id)-\(index)"
        polygon.identifier = fid as NSString
        polygon.attributes = [
            PolygonLayer.Prop.fillColor: fillColor,
            PolygonLayer.Prop.strokeColor: strokeColor,
            PolygonLayer.Prop.strokeWidth: strokeWidth,
            PolygonLayer.Prop.zIndex: zIndex,
            PolygonLayer.Prop.polygonId: id,
            "id": fid
        ]
        return polygon
    }
}
