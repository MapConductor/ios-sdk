import Foundation
import MapConductorCore

@MainActor
final class TiltMapPageViewModel: ObservableObject {
    let initCameraPosition = MapCameraPosition(
        position: GeoPoint(
            latitude: 48.858140690309604,
            longitude: 2.2945027576710344
        ),
        zoom: 17.0,
        bearing: 270.0
    )

    @Published private(set) var tilt: Double = 0.0
    @Published private(set) var disableSlider = false

    private var currentPosition: MapCameraPosition
    private var isEditingTilt = false

    init() {
        currentPosition = initCameraPosition
        tilt = initCameraPosition.tilt
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
