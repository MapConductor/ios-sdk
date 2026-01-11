import Combine
import CoreLocation
import MapConductorCore
import MapLibre

@MainActor
final class MapLibreGroundImageController {
    private weak var mapView: MLNMapView?
    private let renderer: MapLibreGroundImageOverlayRenderer
    private let groundImageManager: GroundImageManager<MapLibreGroundImageHandle>

    private var groundImageSubscriptions: [String: AnyCancellable] = [:]
    private var groundImageStatesById: [String: GroundImageState] = [:]
    private var latestStates: [GroundImageState] = []
    private var isStyleLoaded: Bool = false

    init(mapView: MLNMapView?) {
        self.mapView = mapView
        self.groundImageManager = GroundImageManager<MapLibreGroundImageHandle>()
        self.renderer = MapLibreGroundImageOverlayRenderer(mapView: mapView)
    }

    func onStyleLoaded(_ style: MLNStyle) {
        isStyleLoaded = true
        renderer.onStyleLoaded(style)
        if !latestStates.isEmpty {
            syncGroundImagesDirectly(latestStates)
        }
    }

    func syncGroundImages(_ groundImages: [GroundImage]) {
        let newIds = Set(groundImages.map { $0.id })
        let oldIds = Set(groundImageStatesById.keys)

        var newStatesById: [String: GroundImageState] = [:]
        var shouldSync = false

        for groundImage in groundImages {
            let state = groundImage.state
            if let existingState = groundImageStatesById[state.id], existingState !== state {
                groundImageSubscriptions[state.id]?.cancel()
                groundImageSubscriptions.removeValue(forKey: state.id)
                shouldSync = true
            }
            newStatesById[state.id] = state
            if !groundImageManager.hasEntity(state.id) {
                shouldSync = true
            }
        }

        if !shouldSync {
            for (id, newState) in newStatesById {
                if let entity = groundImageManager.getEntity(id) {
                    if entity.fingerPrint != newState.fingerPrint() {
                        shouldSync = true
                        break
                    }
                }
            }
        }

        groundImageStatesById = newStatesById
        latestStates = groundImages.map { $0.state }

        if oldIds != newIds {
            shouldSync = true
        }

        for groundImage in groundImages {
            subscribeToGroundImage(groundImage.state)
        }

        let removedIds = oldIds.subtracting(newIds)
        for id in removedIds {
            groundImageSubscriptions[id]?.cancel()
            groundImageSubscriptions.removeValue(forKey: id)
        }

        guard isStyleLoaded, shouldSync else { return }
        syncGroundImagesDirectly(latestStates)
    }

    func handleTap(at coordinate: CLLocationCoordinate2D) -> Bool {
        let position = GeoPoint(latitude: coordinate.latitude, longitude: coordinate.longitude, altitude: 0)
        guard let hit = groundImageManager.find(position: position) else { return false }
        let event = GroundImageEvent(state: hit.state, clicked: position)
        hit.state.onClick?(event)
        return true
    }

    private func syncGroundImagesDirectly(_ states: [GroundImageState]) {
        let previous = Set(groundImageManager.allEntities().map { $0.state.id })
        let newIds = Set(states.map { $0.id })

        for id in previous.subtracting(newIds) {
            if let entity = groundImageManager.getEntity(id) {
                renderer.removeGroundImageSync(entity: entity)
                _ = groundImageManager.removeEntity(id)
            }
        }

        for state in states {
            if let prevEntity = groundImageManager.getEntity(state.id) {
                if prevEntity.fingerPrint != state.fingerPrint() {
                    if let handle = prevEntity.groundImage {
                        let currentEntity = GroundImageEntity(groundImage: handle, state: state)
                        if let updatedHandle = renderer.updateGroundImageSync(
                            groundImage: handle,
                            current: currentEntity,
                            prev: prevEntity
                        ) {
                            groundImageManager.registerEntity(GroundImageEntity(groundImage: updatedHandle, state: state))
                        }
                    }
                }
            } else {
                if let handle = renderer.createGroundImageSync(state: state) {
                    groundImageManager.registerEntity(GroundImageEntity(groundImage: handle, state: state))
                }
            }
        }
    }

    private func subscribeToGroundImage(_ state: GroundImageState) {
        guard groundImageSubscriptions[state.id] == nil else { return }
        groundImageSubscriptions[state.id] = state.asFlow()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                guard self.groundImageStatesById[state.id] != nil else { return }
                guard self.isStyleLoaded else { return }
                self.syncGroundImagesDirectly(self.latestStates)
            }
    }

    func unbind() {
        let entities = groundImageManager.allEntities()
        for entity in entities {
            renderer.removeGroundImageSync(entity: entity)
        }
        groundImageSubscriptions.values.forEach { $0.cancel() }
        groundImageSubscriptions.removeAll()
        groundImageStatesById.removeAll()
        latestStates.removeAll()
        isStyleLoaded = false
        renderer.unbind()
        mapView = nil
        groundImageManager.destroy()
    }
}
