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

        // Android の HolePolygonMapPage と同じく、札幌周辺だけを覆う外周を使う。
        // 世界外周を 10 km 間隔で補間すると、hole のドラッグごとに数千頂点の
        // ArcGIS geometry を再構築することになり、ドラッグへの追従が遅れる。
        let outerPoints: [GeoPoint] = [
            GeoPoint(latitude: 44.2, longitude: 140.0),
            GeoPoint(latitude: 44.2, longitude: 142.8),
            GeoPoint(latitude: 42.0, longitude: 142.8),
            GeoPoint(latitude: 42.0, longitude: 140.0)
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
            points: outerPoints,
            id: "sapporo-hole",
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

        if ProcessInfo.processInfo.environment["MAPCONDUCTOR_SAMPLE_HOLE_AUTODRIFT"] == "1" {
            startAutoDrift()
        }
    }

    deinit {
        driftTimer?.invalidate()
    }

    /// テスト用: 環境変数 MAPCONDUCTOR_SAMPLE_HOLE_AUTODRIFT=1 のとき、穴 0 の三角形を
    /// 東西に往復移動させる（頂点ドラッグと同じ「state の in-place 変更」経路を通す）。
    /// UI テストがスクリーンショット比較で「穴が動いて再描画されるか」を機械検証するために使う。
    private var driftTimer: Timer?
    private var driftTick = 0
    private var baseHole0: [GeoPoint] = []

    private func startAutoDrift() {
        NSLog("[MapConductor][Sample] hole autodrift starting")
        baseHole0 = holes[0]
        driftTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else {
                NSLog("[MapConductor][Sample] hole autodrift tick skipped (view model gone)")
                return
            }
            self.driftTick += 1
            NSLog("[MapConductor][Sample] hole autodrift tick=%d", self.driftTick)
            // 単調に東へ移動（スクリーンショット間隔と往復周期のエイリアシングを避ける）。
            // 1 tick あたり 0.008°（ズーム 11 で約 12px）。
            let offset = 0.008 * Double(self.driftTick)
            self.holes[0] = self.baseHole0.map {
                GeoPoint(latitude: $0.latitude, longitude: $0.longitude + offset)
            }
            self.polygonState.holes = self.holes
            // マーカーもドラッグ相当に追従させる（marker update 経路のちらつき検証用）。
            for (vertexIndex, point) in self.holes[0].enumerated() {
                if let marker = self.holeVertexMarkers.first(where: { $0.id == "hole-0-\(vertexIndex)" }) {
                    marker.position = point
                }
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
