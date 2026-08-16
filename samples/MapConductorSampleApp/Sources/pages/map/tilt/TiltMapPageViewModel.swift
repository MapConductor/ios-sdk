import Foundation
import MapConductorCore
import UIKit

@MainActor
final class TiltMapPageViewModel: ObservableObject {
    static let initialCameraPosition = MapCameraPosition(
        position: GeoPoint(
            latitude: 48.858140690309604,
            longitude: 2.2945027576710344
        ),
        zoom: 17.0,
        bearing: 270.0
    )

    let initCameraPosition = TiltMapPageViewModel.initialCameraPosition

    /// 中心 1 個 + 同心円 5 本（各 8 個、45 度おき）= 41 個。
    ///
    /// Android / react の Tilt ページ（`TiltMapPageViewModel.kt` / `TiltPage.tsx`）と
    /// **同じ定数**にしてある。3 プラットフォームを並べて見比べるページなので、
    /// カメラもマーカーの配置も揃っていないと比較にならない。
    let markerStates: [MarkerState] = TiltMapPageViewModel.makeRingMarkers()

    /// 各マーカーの真下に置く小さな円。
    ///
    /// 円は地面に貼り付き、マーカーは画面固定サイズで描かれる。**傾けたり回したりして
    /// ピンの先端がこの円から外れたら、おかしいのはマーカー側**だと一目で分かる。
    /// Open Mobile Maps のアンカーの不具合をこれで特定したので、常設の検証装置として残す。
    let anchorCircleStates: [CircleState] = TiltMapPageViewModel.makeAnchorCircles()

    @Published private(set) var tilt: Double = 0.0
    @Published private(set) var disableSlider = false

    private var currentPosition: MapCameraPosition
    private var isEditingTilt = false

    init() {
        // UI テストからの初期 tilt 指定。スライダーの adjust は SwiftUI の
        // onEditingChanged が走らず disableSlider に弾かれることがあるので、
        // 負の tilt（見上げの疑似表現）の検証はこちらから入れる。
        // 例: MAPCONDUCTOR_SAMPLE_TILT=-45
        let requestedTilt = ProcessInfo.processInfo.environment["MAPCONDUCTOR_SAMPLE_TILT"]
            .flatMap(Double.init)
            .map { min(max($0, -60.0), 60.0) }
        let start = TiltMapPageViewModel.initialCameraPosition
        currentPosition = requestedTilt.map { start.copy(tilt: $0) } ?? start
        tilt = currentPosition.tilt
    }

    func onMapViewChanged(_ state: any MapViewStateProtocol) {
        state.moveCameraTo(cameraPosition: currentPosition)
    }

    func setTilt(_ angle: Double, state: any MapViewStateProtocol) {
        guard !disableSlider else { return }

        tilt = angle
        currentPosition = currentPosition.copy(tilt: angle)
        state.moveCameraTo(cameraPosition: currentPosition)
    }

    func setTiltEditing(_ isEditing: Bool) {
        isEditingTilt = isEditing
    }

    func onMapCameraMoveStart(_ position: MapCameraPosition) {
        guard !isEditingTilt else { return }
        disableSlider = true
    }

    func onMapCameraMoveEnd(_ position: MapCameraPosition) {
        currentPosition = position
        if !isEditingTilt {
            tilt = position.tilt
        }
        disableSlider = false
    }
}

// MARK: - サンプルのマーカー

private extension TiltMapPageViewModel {
    /// リングの間隔。ズーム 17 では 60m がちょうど画面に収まる
    /// （傾けたときに手前と奥で見え方が変わるのを見るページなので、収まっていることが要件）。
    static let ringSpacingMeters = 60.0
    static let markersPerRing = 8

    static let centerColor = UIColor(red: 0.067, green: 0.094, blue: 0.153, alpha: 1.0)

    /// 内側から外側へ。Android / react と同じ並び。
    static let ringColors: [UIColor] = [
        UIColor(red: 0.906, green: 0.298, blue: 0.235, alpha: 1.0),
        UIColor(red: 0.902, green: 0.494, blue: 0.133, alpha: 1.0),
        UIColor(red: 0.945, green: 0.769, blue: 0.059, alpha: 1.0),
        UIColor(red: 0.180, green: 0.800, blue: 0.443, alpha: 1.0),
        UIColor(red: 0.204, green: 0.596, blue: 0.859, alpha: 1.0),
    ]

    static let anchorRadiusMeters = 2.5

    static func makeRingMarkers() -> [MarkerState] {
        let center = initialCameraPosition.position
        var markers: [MarkerState] = [
            MarkerState(
                position: GeoPoint.from(position: center),
                id: "tilt-center",
                icon: ColorDefaultIcon(fillColor: centerColor),
                onClick: { $0.animate(.Bounce) }
            )
        ]
        for (ringIndex, color) in ringColors.enumerated() {
            let distance = Double(ringIndex + 1) * ringSpacingMeters
            for step in 0..<markersPerRing {
                let heading = Double(step) * (360.0 / Double(markersPerRing))
                markers.append(
                    MarkerState(
                        position: Spherical.computeOffset(
                            origin: center,
                            distance: distance,
                            heading: heading
                        ),
                        id: "tilt-ring\(ringIndex + 1)-\(Int(heading))",
                        icon: ColorDefaultIcon(fillColor: color),
                        onClick: { $0.animate(.Bounce) }
                    )
                )
            }
        }
        return markers
    }

    static func makeAnchorCircles() -> [CircleState] {
        makeRingMarkers().map { marker in
            CircleState(
                center: marker.position,
                radiusMeters: anchorRadiusMeters,
                geodesic: true,
                clickable: false,
                strokeColor: .black,
                strokeWidth: 1.0,
                fillColor: UIColor(red: 1.0, green: 0.0, blue: 1.0, alpha: 1.0),
                id: "anchor-\(marker.id)"
            )
        }
    }
}
