import Foundation
import MapConductorCore
import UIKit

final class PolygonMapPageViewModel: ObservableObject {
    let initCameraPosition: MapCameraPosition
    let polygonVertexMarkers: [MarkerState]
    let polygonState: PolygonState

    @Published var fillOpacity: Double
    @Published var strokeWidth: Double

    private var polygonVertices: [GeoPoint]

    init() {
        let initialFillOpacity = 0.3
        let initialStrokeWidth = 3.0

        self.polygonVertices = [
            GeoPoint(latitude: 41.79883, longitude: 140.75675),
            GeoPoint(latitude: 41.799240000000005, longitude: 140.75875000000002),
            GeoPoint(latitude: 41.797650000000004, longitude: 140.75905),
            GeoPoint(latitude: 41.79637, longitude: 140.76018000000002),
            GeoPoint(latitude: 41.79567, longitude: 140.75845),
            GeoPoint(latitude: 41.794470000000004, longitude: 140.75714000000002),
            GeoPoint(latitude: 41.795010000000005, longitude: 140.75611),
            GeoPoint(latitude: 41.79477000000001, longitude: 140.75484),
            GeoPoint(latitude: 41.79576, longitude: 140.75475),
            GeoPoint(latitude: 41.796150000000004, longitude: 140.75364000000002),
            GeoPoint(latitude: 41.79744, longitude: 140.75454000000002),
            GeoPoint(latitude: 41.79909000000001, longitude: 140.75465)
        ]

        self.initCameraPosition = MapCameraPosition(
            position: GeoPoint(latitude: 41.796855, longitude: 140.756910),
            zoom: 16.0,
            bearing: 0.0,
            tilt: 0.0,
            paddings: nil
        )

        let initialVertices = polygonVertices
        self.polygonState = PolygonState(
            points: initialVertices,
            id: "example_polygon",
            strokeColor: UIColor.red,
            strokeWidth: initialStrokeWidth,
            fillColor: UIColor.blue.withAlphaComponent(initialFillOpacity),
            geodesic: false
        )

        let markers = initialVertices.enumerated().map { index, point in
            MarkerState(
                position: point,
                id: "vertex_\(index)",
                extra: index,
                icon: DefaultMarkerIcon(
                    fillColor: UIColor.yellow,
                    strokeColor: UIColor.black,
                    scale: 0.7,
                ),
                draggable: true,
                onDrag: nil
            )
        }

        self.fillOpacity = initialFillOpacity
        self.strokeWidth = initialStrokeWidth

        self.polygonVertexMarkers = markers
        self.polygonVertexMarkers.forEach { marker in
            marker.onDrag = { [weak self] dragged in
                self?.onMarkerDrag(dragged)
            }
        }
    }

    func onMarkerDrag(_ dragged: MarkerState) {
        guard let index = dragged.extra as? Int else { return }
        guard index >= 0 && index < polygonVertices.count else { return }
        polygonVertices[index] = GeoPoint.from(position: dragged.position)
        polygonState.points = polygonVertices
    }
}
