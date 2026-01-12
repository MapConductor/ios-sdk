import Combine
import CoreLocation
import MapKit
import MapConductorCore

@MainActor
final class MapKitPolygonController: PolygonController<MKPolygon, MapKitPolygonOverlayRenderer> {
    private weak var mapView: MKMapView?

    private var polygonStatesById: [String: PolygonState] = [:]
    private var polygonSubscriptions: [String: AnyCancellable] = [:]

    init(mapView: MKMapView?) {
        self.mapView = mapView
        let polygonManager = PolygonManager<MKPolygon>()
        let renderer = MapKitPolygonOverlayRenderer(mapView: mapView)
        super.init(polygonManager: polygonManager, renderer: renderer)
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

        if oldIds != newIds {
            shouldSyncList = true
        }

        polygonStatesById = newStatesById

        let removedIds = oldIds.subtracting(newIds)
        for id in removedIds {
            polygonSubscriptions[id]?.cancel()
            polygonSubscriptions.removeValue(forKey: id)
        }

        if shouldSyncList {
            Task { [weak self] in
                guard let self else { return }
                await self.add(data: polygons.map { $0.state })
            }
        }

        for polygon in polygons {
            subscribeToPolygon(polygon.state)
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
        mapView = nil
        destroy()
    }
}
