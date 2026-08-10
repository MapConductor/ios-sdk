import Foundation
import MapConductorCore

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
