import CoreGraphics
import CoreLocation
import GoogleMaps
import MapConductorCore

final class GoogleMapViewHolder: MapViewHolderProtocol {
    let mapView: GMSMapView
    let map: GMSMapView

    init(mapView: GMSMapView) {
        self.mapView = mapView
        self.map = mapView
    }

    func toScreenOffset(position: GeoPointProtocol) -> CGPoint? {
        let coordinate = CLLocationCoordinate2D(latitude: position.latitude, longitude: position.longitude)
        return mapView.projection.point(for: coordinate)
    }

    func fromScreenOffset(offset: CGPoint) async -> GeoPoint? {
        fromScreenOffsetSync(offset: offset)
    }

    func fromScreenOffsetSync(offset: CGPoint) -> GeoPoint? {
        let coordinate = mapView.projection.coordinate(for: offset)
        return GeoPoint(latitude: coordinate.latitude, longitude: coordinate.longitude, altitude: 0)
    }
}
