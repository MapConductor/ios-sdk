import CoreGraphics
import CoreLocation
import MapKit
import MapConductorCore

final class MapKitViewHolder: MapViewHolderProtocol {
    let mapView: MKMapView
    let map: MKMapView

    init(mapView: MKMapView) {
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
