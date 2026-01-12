import Combine
import CoreLocation
import MapKit
import MapConductorCore

@MainActor
final class MapKitGroundImageController: GroundImageController<MapKitGroundImageOverlay, MapKitGroundImageOverlayRenderer> {
    private weak var mapView: MKMapView?

    private var groundImageStatesById: [String: GroundImageState] = [:]
    private var groundImageSubscriptions: [String: AnyCancellable] = [:]

    init(mapView: MKMapView?) {
        self.mapView = mapView
        let manager = GroundImageManager<MapKitGroundImageOverlay>()
        let renderer = MapKitGroundImageOverlayRenderer(mapView: mapView)
        super.init(groundImageManager: manager, renderer: renderer)
    }

    func syncGroundImages(_ groundImages: [GroundImage]) {
        let newIds = Set(groundImages.map { $0.id })
        let oldIds = Set(groundImageStatesById.keys)

        var newStatesById: [String: GroundImageState] = [:]
        var shouldSyncList = false

        for groundImage in groundImages {
            let state = groundImage.state
            if let existingState = groundImageStatesById[state.id], existingState !== state {
                groundImageSubscriptions[state.id]?.cancel()
                groundImageSubscriptions.removeValue(forKey: state.id)
                shouldSyncList = true
            }
            newStatesById[state.id] = state
            if !groundImageManager.hasEntity(state.id) {
                shouldSyncList = true
            }
        }

        if oldIds != newIds {
            shouldSyncList = true
        }

        groundImageStatesById = newStatesById

        let removedIds = oldIds.subtracting(newIds)
        for id in removedIds {
            groundImageSubscriptions[id]?.cancel()
            groundImageSubscriptions.removeValue(forKey: id)
        }

        if shouldSyncList {
            Task { [weak self] in
                guard let self else { return }
                await self.add(data: groundImages.map { $0.state })
            }
        }

        for groundImage in groundImages {
            subscribeToGroundImage(groundImage.state)
        }
    }

    func handleTap(at coordinate: CLLocationCoordinate2D) -> Bool {
        let position = GeoPoint(latitude: coordinate.latitude, longitude: coordinate.longitude, altitude: 0)
        guard let hit = find(position: position) else { return false }
        let event = GroundImageEvent(state: hit.state, clicked: position)
        dispatchClick(event: event)
        return true
    }

    private func subscribeToGroundImage(_ state: GroundImageState) {
        guard groundImageSubscriptions[state.id] == nil else { return }
        groundImageSubscriptions[state.id] = state.asFlow()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                guard self.groundImageStatesById[state.id] != nil else { return }
                Task { [weak self] in
                    guard let self else { return }
                    await self.update(state: state)
                }
            }
    }

    func unbind() {
        groundImageSubscriptions.values.forEach { $0.cancel() }
        groundImageSubscriptions.removeAll()
        groundImageStatesById.removeAll()
        mapView = nil
        renderer.unbind()
        destroy()
    }
}
