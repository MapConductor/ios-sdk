import CoreLocation
import Foundation
import MapConductorCore
import MapLibre
import UIKit

@MainActor
final class MapLibreMarkerEventController {
    private weak var mapView: MLNMapView?
    private let markerController: MapLibreMarkerController

    private var draggingMarkerId: String?

    init(mapView: MLNMapView?, markerController: MapLibreMarkerController) {
        self.mapView = mapView
        self.markerController = markerController
    }

    func handleTap(at point: CGPoint) -> Bool {
        guard let markerId = markerController.renderer.markerId(at: point),
              let state = markerController.getMarkerState(for: markerId),
              state.clickable else { return false }
        markerController.dispatchClick(state: state)
        return true
    }

    func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
        guard let mapView else { return }
        let point = recognizer.location(in: mapView)

        switch recognizer.state {
        case .began:
            guard let markerId = markerController.renderer.markerId(at: point),
                  let state = markerController.getMarkerState(for: markerId),
                  state.draggable else { return }
            draggingMarkerId = markerId
            mapView.isScrollEnabled = false
            markerController.dispatchDragStart(state: state)
            markerController.onUpdateInfoBubble(markerId)
        case .changed:
            guard let markerId = draggingMarkerId,
                  let state = markerController.getMarkerState(for: markerId) else { return }
            let coordinate = mapView.convert(point, toCoordinateFrom: mapView)
            state.position = GeoPoint(latitude: coordinate.latitude, longitude: coordinate.longitude, altitude: 0)
            markerController.dispatchDrag(state: state)
            markerController.onUpdateInfoBubble(markerId)
        case .ended:
            guard let markerId = draggingMarkerId,
                  let state = markerController.getMarkerState(for: markerId) else {
                mapView.isScrollEnabled = true
                draggingMarkerId = nil
                return
            }
            markerController.dispatchDragEnd(state: state)
            mapView.isScrollEnabled = true
            draggingMarkerId = nil
            markerController.onUpdateInfoBubble(markerId)
        case .cancelled, .failed:
            mapView.isScrollEnabled = true
            draggingMarkerId = nil
        default:
            break
        }
    }

    func unbind() {
        mapView?.isScrollEnabled = true
        mapView = nil
        draggingMarkerId = nil
    }
}
