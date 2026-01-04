import Combine
import CoreLocation
import MapConductorCore
import MapLibre

@MainActor
final class MapLibreCircleController: CircleController<MLNPointFeature, MapLibreCircleOverlayRenderer> {
    private weak var mapView: MLNMapView?

    private var circleSubscriptions: [String: AnyCancellable] = [:]
    private var circleStatesById: [String: CircleState] = [:]
    private var latestStates: [CircleState] = []
    private var isStyleLoaded: Bool = false

    init(mapView: MLNMapView?) {
        self.mapView = mapView

        let circleManager = CircleManager<MLNPointFeature>()
        let layer = CircleLayer(
            sourceId: "mapconductor-circles-source-\(UUID().uuidString)",
            layerId: "mapconductor-circles-layer-\(UUID().uuidString)"
        )
        let renderer = MapLibreCircleOverlayRenderer(
            mapView: mapView,
            circleManager: circleManager,
            circleLayer: layer
        )

        super.init(circleManager: circleManager, renderer: renderer)
    }

    func onStyleLoaded(_ style: MLNStyle) {
        isStyleLoaded = true
        renderer.onStyleLoaded(style)
        if !latestStates.isEmpty {
            Task { [weak self] in
                guard let self else { return }
                await self.add(data: self.latestStates)
            }
        }
    }

    func syncCircles(_ circles: [Circle]) {
        let newIds = Set(circles.map { $0.id })
        let oldIds = Set(circleStatesById.keys)

        var newStatesById: [String: CircleState] = [:]
        var shouldSyncList = false

        for circle in circles {
            let state = circle.state
            if let existingState = circleStatesById[state.id], existingState !== state {
                circleSubscriptions[state.id]?.cancel()
                circleSubscriptions.removeValue(forKey: state.id)
                shouldSyncList = true
            }
            newStatesById[state.id] = state
            if !circleManager.hasEntity(state.id) {
                shouldSyncList = true
            }
        }

        circleStatesById = newStatesById
        latestStates = circles.map { $0.state }

        if oldIds != newIds {
            shouldSyncList = true
        }

        if isStyleLoaded, shouldSyncList {
            Task { [weak self] in
                guard let self else { return }
                await self.add(data: self.latestStates)
            }
        }

        for circle in circles {
            subscribeToCircle(circle.state)
        }

        let removedIds = oldIds.subtracting(newIds)
        for id in removedIds {
            circleSubscriptions[id]?.cancel()
            circleSubscriptions.removeValue(forKey: id)
        }
    }

    func handleTap(at coordinate: CLLocationCoordinate2D) -> Bool {
        let position = GeoPoint(latitude: coordinate.latitude, longitude: coordinate.longitude, altitude: 0)
        guard let hit = find(position: position) else { return false }
        let event = CircleEvent(state: hit.state, clicked: position)
        dispatchClick(event: event)
        return true
    }

    private func subscribeToCircle(_ state: CircleState) {
        guard circleSubscriptions[state.id] == nil else { return }
        circleSubscriptions[state.id] = state.asFlow()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                guard self.circleStatesById[state.id] != nil else { return }
                Task { [weak self] in
                    guard let self else { return }
                    await self.update(state: state)
                }
            }
    }

    func unbind() {
        circleSubscriptions.values.forEach { $0.cancel() }
        circleSubscriptions.removeAll()
        circleStatesById.removeAll()
        latestStates.removeAll()
        isStyleLoaded = false
        renderer.unbind()
        mapView = nil
        destroy()
    }
}
