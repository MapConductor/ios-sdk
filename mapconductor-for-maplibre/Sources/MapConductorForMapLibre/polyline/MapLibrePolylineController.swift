import Combine
import CoreLocation
import MapConductorCore
import MapLibre

@MainActor
final class MapLibrePolylineController: PolylineController<[MLNPolylineFeature], MapLibrePolylineOverlayRenderer> {
    private weak var mapView: MLNMapView?

    private var polylineSubscriptions: [String: AnyCancellable] = [:]
    private var polylineStatesById: [String: PolylineState] = [:]
    private var latestStates: [PolylineState] = []
    private var isStyleLoaded: Bool = false

    init(mapView: MLNMapView?) {
        self.mapView = mapView

        let polylineManager = PolylineManager<[MLNPolylineFeature]>()
        let layer = PolylineLayer(
            sourceId: "mapconductor-polylines-source-\(UUID().uuidString)",
            layerId: "mapconductor-polylines-layer-\(UUID().uuidString)"
        )
        let renderer = MapLibrePolylineOverlayRenderer(
            mapView: mapView,
            polylineManager: polylineManager,
            polylineLayer: layer
        )

        super.init(polylineManager: polylineManager, renderer: renderer)
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

    func syncPolylines(_ polylines: [Polyline]) {
        let newIds = Set(polylines.map { $0.id })
        let oldIds = Set(polylineStatesById.keys)

        var newStatesById: [String: PolylineState] = [:]
        var shouldSyncList = false

        for polyline in polylines {
            let state = polyline.state
            if let existingState = polylineStatesById[state.id], existingState !== state {
                polylineSubscriptions[state.id]?.cancel()
                polylineSubscriptions.removeValue(forKey: state.id)
                shouldSyncList = true
            }
            newStatesById[state.id] = state
            if !polylineManager.hasEntity(state.id) {
                shouldSyncList = true
            }
        }

        polylineStatesById = newStatesById
        latestStates = polylines.map { $0.state }

        if oldIds != newIds {
            shouldSyncList = true
        }

        if isStyleLoaded, shouldSyncList {
            Task { [weak self] in
                guard let self else { return }
                await self.add(data: self.latestStates)
            }
        }

        for polyline in polylines {
            subscribeToPolyline(polyline.state)
        }

        let removedIds = oldIds.subtracting(newIds)
        for id in removedIds {
            polylineSubscriptions[id]?.cancel()
            polylineSubscriptions.removeValue(forKey: id)
        }
    }

    func handleTap(at coordinate: CLLocationCoordinate2D) -> Bool {
        let position = GeoPoint(latitude: coordinate.latitude, longitude: coordinate.longitude, altitude: 0)
        guard let hit = findWithClosestPoint(position: position) else { return false }
        let event = PolylineEvent(state: hit.entity.state, clicked: hit.closestPoint)
        dispatchClick(event: event)
        return true
    }

    private func subscribeToPolyline(_ state: PolylineState) {
        guard polylineSubscriptions[state.id] == nil else { return }
        polylineSubscriptions[state.id] = state.asFlow()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                guard self.polylineStatesById[state.id] != nil else { return }
                Task { [weak self] in
                    guard let self else { return }
                    await self.update(state: state)
                }
            }
    }

    func unbind() {
        polylineSubscriptions.values.forEach { $0.cancel() }
        polylineSubscriptions.removeAll()
        polylineStatesById.removeAll()
        latestStates.removeAll()
        isStyleLoaded = false
        renderer.unbind()
        mapView = nil
        destroy()
    }
}
