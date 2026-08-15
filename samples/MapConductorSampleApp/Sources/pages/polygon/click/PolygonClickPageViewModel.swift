import Foundation
import MapConductorCore

final class PolygonClickPageViewModel: ObservableObject {
    let initCameraPosition: MapCameraPosition

    @Published private(set) var markerState: MarkerState?
    @Published private(set) var message: String = ""

    /// クリックの配送カウンタ（UI テスト用）。
    ///
    /// **`message` では二重配送を検出できない。** ポリゴンと地図の両方に配送されても
    /// 後勝ちで片方しか残らないため、種別ごとに数える。`cascadeReadout` として公開する。
    @Published private(set) var mapClickCount = 0
    @Published private(set) var polygonClickCount = 0

    var cascadeReadout: String { "map=\(mapClickCount) polygon=\(polygonClickCount)" }

    init() {
        self.initCameraPosition = MapCameraPosition(
            position: GeoPoint(latitude: 36.73030, longitude: -120.24512),
            zoom: 5.0,
            bearing: 0.0,
            tilt: 0.0,
            paddings: nil
        )
    }

    func onMapClicked(_ clicked: GeoPoint) {
        mapClickCount += 1
        message = "Outside"
        markerState = MarkerState(
            position: clicked,
            id: "clicked"
        )
    }

    func onPolygonClicked(_ event: PolygonEvent) {
        polygonClickCount += 1
        let latLng = GeoPoint.from(position: event.clicked).toUrlValue()
        message = "Inside\n\(latLng)"
        markerState = MarkerState(
            position: GeoPoint.from(position: event.clicked),
            id: "clicked"
        )
    }
}
