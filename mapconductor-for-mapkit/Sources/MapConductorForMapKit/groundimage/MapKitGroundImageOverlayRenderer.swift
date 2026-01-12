import CoreLocation
import MapKit
import MapConductorCore
import UIKit

// Custom MKOverlay for ground images
final class MapKitGroundImageOverlay: NSObject, MKOverlay {
    let coordinate: CLLocationCoordinate2D
    let boundingMapRect: MKMapRect
    let image: UIImage
    let opacity: CGFloat
    let stateId: String

    init(bounds: GeoRectBounds, image: UIImage, opacity: Double, stateId: String) {
        guard let sw = bounds.southWest, let ne = bounds.northEast else {
            fatalError("GroundImage bounds must have southWest and northEast")
        }

        let swWrapped = GeoPoint.from(position: sw.wrap())
        let neWrapped = GeoPoint.from(position: ne.wrap())

        let swCoord = CLLocationCoordinate2D(latitude: swWrapped.latitude, longitude: swWrapped.longitude)
        let neCoord = CLLocationCoordinate2D(latitude: neWrapped.latitude, longitude: neWrapped.longitude)

        let swPoint = MKMapPoint(swCoord)
        let nePoint = MKMapPoint(neCoord)

        self.boundingMapRect = MKMapRect(
            x: min(swPoint.x, nePoint.x),
            y: min(swPoint.y, nePoint.y),
            width: abs(nePoint.x - swPoint.x),
            height: abs(nePoint.y - swPoint.y)
        )

        self.coordinate = CLLocationCoordinate2D(
            latitude: (swWrapped.latitude + neWrapped.latitude) / 2.0,
            longitude: (swWrapped.longitude + neWrapped.longitude) / 2.0
        )

        self.image = image
        self.opacity = CGFloat(opacity)
        self.stateId = stateId

        super.init()
    }
}

// Custom MKOverlayRenderer for ground images
final class MapKitGroundImageRenderer: MKOverlayRenderer {
    private let groundImageOverlay: MapKitGroundImageOverlay

    init(overlay: MapKitGroundImageOverlay) {
        self.groundImageOverlay = overlay
        super.init(overlay: overlay)
    }

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let image = groundImageOverlay.image.cgImage else { return }

        let rect = self.rect(for: groundImageOverlay.boundingMapRect)

        context.saveGState()
        context.setAlpha(groundImageOverlay.opacity)

        // Flip the image vertically (CoreGraphics draws upside down)
        context.translateBy(x: rect.origin.x, y: rect.origin.y + rect.size.height)
        context.scaleBy(x: 1.0, y: -1.0)

        let drawRect = CGRect(x: 0, y: 0, width: rect.width, height: rect.height)
        context.draw(image, in: drawRect)

        context.restoreGState()
    }
}

@MainActor
final class MapKitGroundImageOverlayRenderer: AbstractGroundImageOverlayRenderer<MapKitGroundImageOverlay> {
    private weak var mapView: MKMapView?
    private var renderersByStateId: [String: MapKitGroundImageRenderer] = [:]
    private var overlaysByStateId: [String: MapKitGroundImageOverlay] = [:]

    init(mapView: MKMapView?) {
        self.mapView = mapView
        super.init()
    }

    override func createGroundImage(state: GroundImageState) async -> MapKitGroundImageOverlay? {
        guard let mapView else { return nil }

        let overlay = MapKitGroundImageOverlay(
            bounds: state.bounds,
            image: state.image,
            opacity: state.opacity,
            stateId: state.id
        )

        let renderer = MapKitGroundImageRenderer(overlay: overlay)
        renderersByStateId[state.id] = renderer
        overlaysByStateId[state.id] = overlay

        mapView.addOverlay(overlay, level: .aboveLabels)

        return overlay
    }

    override func updateGroundImageProperties(
        groundImage: MapKitGroundImageOverlay,
        current: GroundImageEntity<MapKitGroundImageOverlay>,
        prev: GroundImageEntity<MapKitGroundImageOverlay>
    ) async -> MapKitGroundImageOverlay? {
        guard let mapView else { return groundImage }
        let finger = current.fingerPrint
        let prevFinger = prev.fingerPrint

        // If bounds, image, or opacity changed, we need to recreate the overlay
        if finger.bounds != prevFinger.bounds || finger.image != prevFinger.image || finger.opacity != prevFinger.opacity {
            mapView.removeOverlay(groundImage)
            renderersByStateId.removeValue(forKey: prev.state.id)
            overlaysByStateId.removeValue(forKey: prev.state.id)
            return await createGroundImage(state: current.state)
        }

        return groundImage
    }

    override func removeGroundImage(entity: GroundImageEntity<MapKitGroundImageOverlay>) async {
        guard let mapView, let groundImage = entity.groundImage else { return }
        mapView.removeOverlay(groundImage)
        renderersByStateId.removeValue(forKey: entity.state.id)
        overlaysByStateId.removeValue(forKey: entity.state.id)
    }

    func renderer(for overlay: MKOverlay) -> MKOverlayRenderer? {
        guard let groundImageOverlay = overlay as? MapKitGroundImageOverlay,
              let renderer = renderersByStateId[groundImageOverlay.stateId] else {
            return nil
        }
        return renderer
    }

    func unbind() {
        renderersByStateId.removeAll()
        overlaysByStateId.removeAll()
        mapView = nil
    }
}
