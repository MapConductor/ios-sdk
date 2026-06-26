import Foundation
import MapConductorCore
import UIKit

final class CirclePageViewModel: ObservableObject {
    let initCameraPosition: MapCameraPosition
    let circleCenter: GeoPoint
    let centerMarker: MarkerState
    let edgeMarker: MarkerState
    let circleState: CircleState

    @Published var fillOpacity: Double
    @Published var strokeWidth: Double
    @Published var message: String
    // Incremented on drag or camera move to trigger label position recalculation in the View
    @Published var labelUpdateTick: Int = 0

    private let colors: [UIColor]
    private var fillColorIndex = 0

    init() {
        let initialFillOpacity = 0.3
        let initialStrokeWidth = 3.0
        let center = GeoPoint(latitude: 21.382314, longitude: -157.933097)

        let edge = Spherical.computeOffset(
            origin: center,
            distance: 1000.0,
            heading: 90.0
        )

        self.circleCenter = center
        self.initCameraPosition = MapCameraPosition(
            position: center,
            zoom: 12.0,
            bearing: 0.0,
            tilt: 0.0,
            paddings: nil
        )

        self.colors = [
            UIColor.blue,
            UIColor.red,
            UIColor.green,
            UIColor.cyan,
            UIColor.lightGray,
            UIColor.magenta
        ]

        self.centerMarker = MarkerState(
            position: center,
            id: "center_marker",
            icon: DefaultMarkerIcon(
                fillColor: UIColor.red,
                strokeColor: UIColor.white,
                label: "C"
            ),
            draggable: false
        )

        self.edgeMarker = MarkerState(
            position: edge,
            id: "edge_marker",
            icon: DefaultMarkerIcon(
                fillColor: UIColor.orange,
                strokeColor: UIColor.white,
                label: "E"
            ),
            draggable: true
        )

        self.circleState = CircleState(
            center: center,
            radiusMeters: Spherical.computeDistanceBetween(
                from: center,
                to: edge
            ),
            strokeColor: UIColor.blue.withAlphaComponent(0.5),
            strokeWidth: initialStrokeWidth,
            fillColor: UIColor.blue.withAlphaComponent(initialFillOpacity),
            id: "circle",
            onClick: nil
        )

        self.fillOpacity = initialFillOpacity
        self.strokeWidth = initialStrokeWidth
        self.message = "Tap the circle or drag the edge marker."

        self.edgeMarker.onDragStart = { [weak self] dragged in
            self?.onMarkerMove(dragged)
        }
        self.edgeMarker.onDrag = { [weak self] dragged in
            self?.onMarkerMove(dragged)
        }
        self.edgeMarker.onDragEnd = { [weak self] dragged in
            self?.onMarkerMove(dragged)
        }
        self.circleState.onClick = { [weak self] event in
            self?.onCircleClick(event)
        }
    }

    func onCircleClick(_ event: CircleEvent) {
        fillColorIndex = (fillColorIndex + 1) % colors.count
        updateCircleFillColor()
        message = "Circle clicked - Radius: \(Int(radiusMeters))m"
    }

    func onMarkerMove(_ dragged: MarkerState) {
        edgeMarker.position = dragged.position
        circleState.radiusMeters = radiusMeters
        labelUpdateTick += 1
    }

    func onCameraMove(_ camera: MapCameraPosition) {
        labelUpdateTick += 1
    }

    func updateCircleFillColor() {
        circleState.fillColor = colors[fillColorIndex].withAlphaComponent(fillOpacity)
    }

    func updateCircleStrokeWidth() {
        circleState.strokeWidth = strokeWidth
    }

    private var radiusMeters: Double {
        Spherical.computeDistanceBetween(from: circleCenter, to: edgeMarker.position)
    }
}
