import CoreLocation
import MapConductorCore
import MapLibre

func createMapLibreLines(
    id: String,
    points: [GeoPointProtocol],
    geodesic: Bool,
    strokeColor: UIColor,
    strokeWidth: Double,
    zIndex: Int = 0
) -> [MLNPolylineFeature] {
    let interpolated: [GeoPointProtocol] = (geodesic ? createInterpolatePoints(points, maxSegmentLength: 1000.0) : createLinearInterpolatePoints(points))
        .map { $0.normalize() }

    return splitByMeridian(interpolated, geodesic: geodesic).enumerated().map { index, linePoints in
        let coordinates = linePoints.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        var coords = coordinates
        let feature = MLNPolylineFeature(coordinates: &coords, count: UInt(coords.count))
        let fid = "polyline-\(id)-\(index)"
        feature.identifier = fid as NSString
        feature.attributes = [
            PolylineLayer.Prop.strokeColor: strokeColor,
            PolylineLayer.Prop.strokeWidth: strokeWidth,
            PolylineLayer.Prop.zIndex: zIndex,
            PolylineLayer.Prop.polylineId: id,
            "id": fid
        ]
        return feature
    }
}
