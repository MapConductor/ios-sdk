import Combine
import CoreLocation
import MapConductorCore
import MapLibre

@MainActor
final class MapLibrePolygonController: PolygonController<[MLNPolygonFeature], MapLibrePolygonOverlayRenderer> {
    private weak var mapView: MLNMapView?

    private var polygonSubscriptions: [String: AnyCancellable] = [:]
    private var polygonStatesById: [String: PolygonState] = [:]
    private var latestStates: [PolygonState] = []
    private var isStyleLoaded: Bool = false

    init(mapView: MLNMapView?) {
        self.mapView = mapView

        let polygonManager = PolygonManager<[MLNPolygonFeature]>()
        let layer = PolygonLayer(
            sourceId: "mapconductor-polygons-source-\(UUID().uuidString)",
            fillLayerId: "mapconductor-polygons-fill-\(UUID().uuidString)",
            lineLayerId: "mapconductor-polygons-line-\(UUID().uuidString)"
        )
        let renderer = MapLibrePolygonOverlayRenderer(
            mapView: mapView,
            polygonManager: polygonManager,
            polygonLayer: layer
        )

        super.init(polygonManager: polygonManager, renderer: renderer)
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

    func syncPolygons(_ polygons: [Polygon]) {
        let newIds = Set(polygons.map { $0.id })
        let oldIds = Set(polygonStatesById.keys)

        var newStatesById: [String: PolygonState] = [:]
        var shouldSyncList = false

        for polygon in polygons {
            let state = polygon.state
            if let existingState = polygonStatesById[state.id], existingState !== state {
                polygonSubscriptions[state.id]?.cancel()
                polygonSubscriptions.removeValue(forKey: state.id)
                shouldSyncList = true
            }
            newStatesById[state.id] = state
            if !polygonManager.hasEntity(state.id) {
                shouldSyncList = true
            }
        }

        polygonStatesById = newStatesById
        latestStates = polygons.map { $0.state }

        if oldIds != newIds {
            shouldSyncList = true
        }

        if isStyleLoaded, shouldSyncList {
            Task { [weak self] in
                guard let self else { return }
                await self.add(data: self.latestStates)
            }
        }

        for polygon in polygons {
            subscribeToPolygon(polygon.state)
        }

        let removedIds = oldIds.subtracting(newIds)
        for id in removedIds {
            polygonSubscriptions[id]?.cancel()
            polygonSubscriptions.removeValue(forKey: id)
        }
    }

    func handleTap(at coordinate: CLLocationCoordinate2D) -> Bool {
        let position = GeoPoint(latitude: coordinate.latitude, longitude: coordinate.longitude, altitude: 0)
        guard let hit = find(position: position) else { return false }
        let event = PolygonEvent(state: hit.state, clicked: position)
        dispatchClick(event: event)
        return true
    }

    private func subscribeToPolygon(_ state: PolygonState) {
        guard polygonSubscriptions[state.id] == nil else { return }
        polygonSubscriptions[state.id] = state.asFlow()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                guard self.polygonStatesById[state.id] != nil else { return }
                Task { [weak self] in
                    guard let self else { return }
                    await self.update(state: state)
                }
            }
    }

    func unbind() {
        polygonSubscriptions.values.forEach { $0.cancel() }
        polygonSubscriptions.removeAll()
        polygonStatesById.removeAll()
        latestStates.removeAll()
        isStyleLoaded = false
        renderer.unbind()
        mapView = nil
        destroy()
    }
}
