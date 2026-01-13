import CoreGraphics
import CoreLocation
import GoogleMaps
import MapConductorCore
import SwiftUI
import UIKit

@MainActor
final class InfoBubbleController {
    private weak var mapView: GMSMapView?
    private let container: UIView
    private let markerController: GoogleMapMarkerController

    private var infoBubblesById: [String: InfoBubble] = [:]
    private var infoBubbleHosts: [String: UIHostingController<AnyView>] = [:]

    init(mapView: GMSMapView?, container: UIView, markerController: GoogleMapMarkerController) {
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

        let markerState = bubble.marker
        let coordinate = CLLocationCoordinate2D(
            latitude: markerState.position.latitude,
            longitude: markerState.position.longitude
        )
        let point = mapView.projection.point(for: coordinate)

        let bitmapIcon = markerController.getIcon(for: markerState)
        let iconSize = bitmapIcon.size
        let iconAnchor = bitmapIcon.anchor
        let infoAnchor = bitmapIcon.infoAnchor
        let tailOffset = bubble.tailOffset

        let targetSize = host.sizeThatFits(in: CGSize(width: 260, height: 1000))
        host.view.bounds = CGRect(origin: .zero, size: targetSize)

        let x = point.x +
            (-tailOffset.x * targetSize.width) +
            ((0.5 - iconAnchor.x) * iconSize.width) +
            ((infoAnchor.x - 0.5) * iconSize.width)
        let y = point.y +
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
