import CoreGraphics
import CoreLocation
import MapLibre
import MapConductorCore

final class MapLibreViewHolder: MapViewHolderProtocol {
    let mapView: MLNMapView
    let map: MLNMapView

    init(mapView: MLNMapView) {
        self.mapView = mapView
        self.map = mapView
    }

    func toScreenOffset(position: GeoPointProtocol) -> CGPoint? {
        let coordinate = CLLocationCoordinate2D(latitude: position.latitude, longitude: position.longitude)
        return mapView.convert(coordinate, toPointTo: mapView)
    }

    func fromScreenOffset(offset: CGPoint) async -> GeoPoint? {
        fromScreenOffsetSync(offset: offset)
    }

    func fromScreenOffsetSync(offset: CGPoint) -> GeoPoint? {
        let coordinate = mapView.convert(offset, toCoordinateFrom: mapView)
        return GeoPoint(latitude: coordinate.latitude, longitude: coordinate.longitude, altitude: 0)
    }
}
