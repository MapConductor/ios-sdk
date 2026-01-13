import CoreGraphics
import CoreLocation
import MapKit
import MapConductorCore
import SwiftUI
import UIKit

@MainActor
final class InfoBubbleController {
    private weak var mapView: MKMapView?
    private let container: UIView
    private let markerController: MapKitMarkerController

    private var infoBubblesById: [String: InfoBubble] = [:]
    private var infoBubbleHosts: [String: UIHostingController<AnyView>] = [:]

    init(mapView: MKMapView?, container: UIView, markerController: MapKitMarkerController) {
        self.mapView = mapView
        self.container = container
        self.markerController = markerController
    }

    func syncInfoBubbles(_ bubbles: [InfoBubble]) {
        var newBubbles: [String: InfoBubble] = [:]
        for bubble in bubbles {
            newBubbles[bubble.marker.id] = bubble
        }
        infoBubblesById = newBubbles
        syncInfoBubbleViews()
    }

    private func syncInfoBubbleViews() {
        for (id, bubble) in infoBubblesById {
            let host = infoBubbleHosts[id] ?? UIHostingController(rootView: bubble.content)
            host.rootView = bubble.content
            host.view.backgroundColor = .clear
            host.view.isUserInteractionEnabled = true
            if host.view.superview == nil {
                container.addSubview(host.view)
            }
            infoBubbleHosts[id] = host
        }

        let activeIds = Set(infoBubblesById.keys)
        let existingIds = Set(infoBubbleHosts.keys)
        for id in existingIds.subtracting(activeIds) {
            removeInfoBubbleView(for: id)
        }
    }

    func removeInfoBubbleView(for id: String) {
        if let host = infoBubbleHosts.removeValue(forKey: id) {
            host.view.removeFromSuperview()
        }
    }

    func updateAllLayouts() {
        guard mapView != nil else { return }
        for id in infoBubblesById.keys {
            updateInfoBubblePosition(for: id)
        }
    }

    func updateInfoBubblePosition(for id: String) {
        guard let mapView = mapView,
              let bubble = infoBubblesById[id],
              let host = infoBubbleHosts[id] else { return }

        // Prefer the marker state provided by the current SwiftUI content (`bubble.marker`).
        // MapKit marker entities can be updated asynchronously (e.g. when the MarkerState instance is replaced
        // but the id stays the same), and using the controller's entity state here can lag by one update.
        let bubbleMarkerState = bubble.marker
        let markerStateForIcon = markerController.getMarkerState(for: id) ?? bubbleMarkerState
        let coordinate = CLLocationCoordinate2D(
            latitude: bubbleMarkerState.position.latitude,
            longitude: bubbleMarkerState.position.longitude
        )
        let coordinatePoint = mapView.convert(coordinate, toPointTo: mapView)
        updateInfoBubblePosition(for: id, bubble: bubble, host: host, markerStateForIcon: markerStateForIcon, coordinatePoint: coordinatePoint)
    }

    func updateInfoBubblePosition(for id: String, coordinatePoint: CGPoint) {
        guard let bubble = infoBubblesById[id],
              let host = infoBubbleHosts[id] else { return }
        let markerStateForIcon = markerController.getMarkerState(for: id) ?? bubble.marker
        updateInfoBubblePosition(for: id, bubble: bubble, host: host, markerStateForIcon: markerStateForIcon, coordinatePoint: coordinatePoint)
    }

    private func updateInfoBubblePosition(
        for id: String,
        bubble: InfoBubble,
        host: UIHostingController<AnyView>,
        markerStateForIcon: MarkerState,
        coordinatePoint: CGPoint
    ) {
        let bitmapIcon = markerController.getIcon(for: markerStateForIcon)
        let iconSize = bitmapIcon.size
        let iconAnchor = bitmapIcon.anchor
        let infoAnchor = bitmapIcon.infoAnchor
        let tailOffset = bubble.tailOffset

        let targetSize = host.sizeThatFits(in: CGSize(width: 260, height: 1000))
        host.view.bounds = CGRect(origin: .zero, size: targetSize)

        let x = coordinatePoint.x +
            (-tailOffset.x * targetSize.width) +
            ((0.5 - iconAnchor.x) * iconSize.width) +
            ((infoAnchor.x - 0.5) * iconSize.width)
        let y = coordinatePoint.y +
            (-tailOffset.y * targetSize.height) +
            ((0.5 - iconAnchor.y) * iconSize.height) +
            ((infoAnchor.y - 0.5) * iconSize.height)

        host.view.frame = CGRect(
            origin: alignToPixel(CGPoint(x: x, y: y), scale: UIScreen.main.scale),
            size: targetSize
        )
    }

    private func alignToPixel(_ point: CGPoint, scale: CGFloat) -> CGPoint {
        guard scale > 0 else { return point }
        return CGPoint(
            x: (point.x * scale).rounded() / scale,
            y: (point.y * scale).rounded() / scale
        )
    }

    func unbind() {
        infoBubbleHosts.values.forEach { $0.view.removeFromSuperview() }
        infoBubbleHosts.removeAll()
        infoBubblesById.removeAll()
    }
}
