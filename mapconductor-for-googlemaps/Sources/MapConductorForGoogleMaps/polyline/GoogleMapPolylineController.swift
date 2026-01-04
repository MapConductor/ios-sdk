import Combine
import CoreLocation
import GoogleMaps
import MapConductorCore

@MainActor
final class GoogleMapPolylineController: PolylineController<GMSPolyline, GoogleMapPolylineOverlayRenderer> {
    private weak var mapView: GMSMapView?

    private var polylineStatesById: [String: PolylineState] = [:]
    private var polylineSubscriptions: [String: AnyCancellable] = [:]

    init(mapView: GMSMapView?) {
        self.mapView = mapView
        let polylineManager = PolylineManager<GMSPolyline>()
        let renderer = GoogleMapPolylineOverlayRenderer(mapView: mapView)
        super.init(polylineManager: polylineManager, renderer: renderer)
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

        if oldIds != newIds {
            shouldSyncList = true
        }

        polylineStatesById = newStatesById

        let removedIds = oldIds.subtracting(newIds)
        for id in removedIds {
            polylineSubscriptions[id]?.cancel()
            polylineSubscriptions.removeValue(forKey: id)
        }

        if shouldSyncList {
            Task { [weak self] in
                guard let self else { return }
                await self.add(data: polylines.map { $0.state })
            }
        }

        for polyline in polylines {
            subscribeToPolyline(polyline.state)
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
        mapView = nil
        destroy()
    }
}
