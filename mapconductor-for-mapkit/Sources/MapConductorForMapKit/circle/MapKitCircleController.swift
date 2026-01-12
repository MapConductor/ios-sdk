import Combine
import CoreLocation
import MapKit
import MapConductorCore

@MainActor
final class MapKitCircleController: CircleController<MKPolygon, MapKitCircleOverlayRenderer> {
    private weak var mapView: MKMapView?

    private var circleStatesById: [String: CircleState] = [:]
    private var circleSubscriptions: [String: AnyCancellable] = [:]

    init(mapView: MKMapView?) {
        self.mapView = mapView
        let circleManager = CircleManager<MKPolygon>()
        let renderer = MapKitCircleOverlayRenderer(mapView: mapView)
        super.init(circleManager: circleManager, renderer: renderer)
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

        if oldIds != newIds {
            shouldSyncList = true
        }

        circleStatesById = newStatesById

        let removedIds = oldIds.subtracting(newIds)
        for id in removedIds {
            circleSubscriptions[id]?.cancel()
            circleSubscriptions.removeValue(forKey: id)
        }

        if shouldSyncList {
            Task { [weak self] in
                guard let self else { return }
                await self.add(data: circles.map { $0.state })
            }
        }

        for circle in circles {
            subscribeToCircle(circle.state)
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
        mapView = nil
        destroy()
    }
}
