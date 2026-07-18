import Foundation
import MapConductorCore
import UIKit

final class HolePolygonMapPageViewModel: ObservableObject {
    let initCameraPosition: MapCameraPosition
    let polygonState: PolygonState
    let holeVertexMarkers: [MarkerState]

    private var holes: [[GeoPoint]]

    init() {
        self.initCameraPosition = MapCameraPosition(
            position: GeoPoint(latitude: 43.06050568387817, longitude: 141.35374551567804),
            zoom: 11.0,
            bearing: 0.0,
            tilt: 0.0,
            paddings: nil
        )

        let worldPoints: [GeoPoint] = [
            GeoPoint(latitude: 85.0, longitude: 90.0),
            GeoPoint(latitude: 85.0, longitude: 0.1),
            GeoPoint(latitude: 85.0, longitude: -90.0),
            GeoPoint(latitude: 85.0, longitude: -179.9),
            GeoPoint(latitude: 0.0, longitude: -179.9),
            GeoPoint(latitude: -85.0, longitude: -179.9),
            GeoPoint(latitude: -85.0, longitude: -90.0),
            GeoPoint(latitude: -85.0, longitude: 0.1),
            GeoPoint(latitude: -85.0, longitude: 90.0),
            GeoPoint(latitude: -85.0, longitude: 179.9),
            GeoPoint(latitude: 0.0, longitude: 179.9),
            GeoPoint(latitude: 85.0, longitude: 179.9)
        ]

        self.holes = [
            [
                GeoPoint(latitude: 43.10086924222251, longitude: 141.35290903949243),
                GeoPoint(latitude: 43.04444342582366, longitude: 141.4118953480885),
                GeoPoint(latitude: 43.05060149394299, longitude: 141.30656265416695)
            ],
            [
                GeoPoint(latitude: 43.06035050410283, longitude: 141.31990479539704),
                GeoPoint(latitude: 43.038284739487004, longitude: 141.33324693662706),
                GeoPoint(latitude: 43.049062034871525, longitude: 141.28690055130158)
            ]
        ]

        self.polygonState = PolygonState(
            points: worldPoints,
            id: "hole_polygon",
            strokeColor: .red,
            strokeWidth: 2.0,
            fillColor: UIColor(red: 120.0 / 255.0, green: 120.0 / 255.0, blue: 128.0 / 255.0, alpha: 0.8),
            geodesic: false,
            holes: holes
        )

        let holeMarkerColors: [UIColor] = [
            UIColor(red: 0x25 / 255.0, green: 0x63 / 255.0, blue: 0xEB / 255.0, alpha: 1.0),
            UIColor(red: 0xF9 / 255.0, green: 0x73 / 255.0, blue: 0x16 / 255.0, alpha: 1.0)
        ]
        let defaultHoleMarkerColor = UIColor(red: 0x64 / 255.0, green: 0x74 / 255.0, blue: 0x8B / 255.0, alpha: 1.0)

        var markers: [MarkerState] = []
        for (holeIndex, hole) in holes.enumerated() {
            for (vertexIndex, point) in hole.enumerated() {
                markers.append(
                    MarkerState(
                        position: point,
                        id: "hole-\(holeIndex)-\(vertexIndex)",
                        extra: HoleVertex(holeIndex: holeIndex, vertexIndex: vertexIndex),
                        icon: DefaultMarkerIcon(
                            fillColor: holeIndex < holeMarkerColors.count ? holeMarkerColors[holeIndex] : defaultHoleMarkerColor,
                            strokeColor: .white,
                            label: "\(holeIndex + 1)-\(vertexIndex + 1)",
                            labelTextColor: .white
                        ),
                        clickable: false,
                        draggable: true,
                        onDrag: nil
                    )
                )
            }
        }

        self.holeVertexMarkers = markers
        self.holeVertexMarkers.forEach { marker in
            marker.onDrag = { [weak self] dragged in
                self?.onMarkerDrag(dragged)
            }
            marker.onDragEnd = { [weak self] dragged in
                self?.onMarkerDrag(dragged)
            }
        }
    }

    func onMarkerDrag(_ dragged: MarkerState) {
        guard let vertex = dragged.extra as? HoleVertex else { return }
        guard vertex.holeIndex >= 0 && vertex.holeIndex < holes.count else { return }

        let hole = holes[vertex.holeIndex]
        guard vertex.vertexIndex >= 0 && vertex.vertexIndex < hole.count else { return }

        holes[vertex.holeIndex][vertex.vertexIndex] = GeoPoint.from(position: dragged.position)
        polygonState.holes = holes
    }

    private struct HoleVertex {
        let holeIndex: Int
        let vertexIndex: Int
    }
}
