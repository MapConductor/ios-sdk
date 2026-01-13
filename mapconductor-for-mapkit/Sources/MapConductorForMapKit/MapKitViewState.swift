import Combine
import Foundation
import MapConductorCore

public final class MapKitViewState: MapViewState<MapKitMapDesignType> {
    private let stateId: String

    @Published private var _cameraPosition: MapCameraPosition
    @Published private var _mapDesignType: MapKitMapDesignType

    private var controller: (any MapViewControllerProtocol)?
    private var mapViewHolder: AnyMapViewHolder?

    public override var id: String { stateId }

    public override var cameraPosition: MapCameraPosition { _cameraPosition }

    public override var mapDesignType: MapKitMapDesignType {
        get { _mapDesignType }
        set { _mapDesignType = newValue }
    }

    public init(
        id: String,
        mapDesignType: MapKitMapDesignType = MapKitMapDesign.Standard,
        cameraPosition: MapCameraPosition = .Default
    ) {
        self.stateId = id
        self._mapDesignType = mapDesignType
        self._cameraPosition = cameraPosition
        super.init()
    }

    public convenience init(
        mapDesignType: MapKitMapDesignType = MapKitMapDesign.Standard,
        cameraPosition: MapCameraPosition = .Default
    ) {
        self.init(id: UUID().uuidString, mapDesignType: mapDesignType, cameraPosition: cameraPosition)
    }

    public override func moveCameraTo(cameraPosition: MapCameraPosition, durationMillis: Long? = 0) {
        let resolved = resolveCameraPosition(cameraPosition)
        if let controller = controller {
            if let durationMillis, durationMillis > 0 {
                controller.animateCamera(position: resolved, duration: durationMillis)
            } else {
                controller.moveCamera(position: resolved)
            }
        } else {
            _cameraPosition = resolved
        }
    }

    public override func moveCameraTo(position: GeoPoint, durationMillis: Long? = 0) {
        let updated = cameraPosition.copy(position: position)
        moveCameraTo(cameraPosition: updated, durationMillis: durationMillis)
    }

    public override func getMapViewHolder() -> AnyMapViewHolder? {
        mapViewHolder
    }

    func setController(_ controller: (any MapViewControllerProtocol)?) {
        self.controller = controller
        if let controller = controller {
            controller.moveCamera(position: cameraPosition)
        }
    }

    func setMapViewHolder(_ holder: AnyMapViewHolder?) {
        mapViewHolder = holder
    }

    func updateCameraPosition(_ cameraPosition: MapCameraPosition) {
        _cameraPosition = cameraPosition
    }

    private func resolveCameraPosition(_ target: MapCameraPosition) -> MapCameraPosition {
        let isUnspecified = target.zoom == 0.0 && target.bearing == 0.0 && target.tilt == 0.0
        if isUnspecified {
            return cameraPosition.copy(position: target.position)
        }
        return target
    }
}
