import Combine
import CoreLocation
import GoogleMaps
import MapConductorCore

@MainActor
final class GoogleMapMarkerController: AbstractMarkerController<GMSMarker, GoogleMapMarkerOverlayRenderer> {
    private weak var mapView: GMSMapView?

    private var markerStatesById: [String: MarkerState] = [:]
    private var markerSubscriptions: [String: AnyCancellable] = [:]

    private let onUpdateInfoBubble: (String) -> Void

    init(mapView: GMSMapView?, onUpdateInfoBubble: @escaping (String) -> Void) {
        self.mapView = mapView
        self.onUpdateInfoBubble = onUpdateInfoBubble

        let markerManager = MarkerManager<GMSMarker>.defaultManager()
        let renderer = GoogleMapMarkerOverlayRenderer(mapView: mapView, markerManager: markerManager)
        super.init(markerManager: markerManager, renderer: renderer)
    }

    func syncMarkers(_ markers: [Marker]) {
        MCLog.marker("GoogleMapMarkerController.syncMarkers count=\(markers.count)")
        let newIds = Set(markers.map { $0.id })
        let oldIds = Set(markerStatesById.keys)

        var newStatesById: [String: MarkerState] = [:]
        var shouldSyncList = false

        for marker in markers {
            let state = marker.state
            if let existingState = markerStatesById[state.id], existingState !== state {
                markerSubscriptions[state.id]?.cancel()
                markerSubscriptions.removeValue(forKey: state.id)
                // State instance changed: ensure controller updates entity reference.
                shouldSyncList = true
            }
            newStatesById[state.id] = state
            if !markerManager.hasEntity(state.id) {
                shouldSyncList = true
            }
        }

        if oldIds != newIds {
            shouldSyncList = true
        }

        markerStatesById = newStatesById

        let removedIds = oldIds.subtracting(newIds)
        for id in removedIds {
            markerSubscriptions[id]?.cancel()
            markerSubscriptions.removeValue(forKey: id)
        }

        if shouldSyncList {
            Task { [weak self] in
                guard let self else { return }
                MCLog.marker("GoogleMapMarkerController.syncMarkers -> add()")
                await self.add(data: markers.map { $0.state })
            }
        }

        for marker in markers {
            subscribeToMarker(marker.state)
            onUpdateInfoBubble(marker.id)
        }
    }

    private func subscribeToMarker(_ state: MarkerState) {
        guard markerSubscriptions[state.id] == nil else { return }
        MCLog.marker("GoogleMapMarkerController.subscribe id=\(state.id)")
        markerSubscriptions[state.id] = state.asFlow()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                guard self.markerStatesById[state.id] != nil else { return }
                MCLog.marker("GoogleMapMarkerController.asFlow emit id=\(state.id) anim=\(String(describing: state.getAnimation()))")
                Task { [weak self] in
                    guard let self else { return }
                    await self.update(state: state)
                    self.onUpdateInfoBubble(state.id)
                }
            }
    }

    func getMarkerState(for id: String) -> MarkerState? {
        markerManager.getEntity(id)?.state
    }

    func getIcon(for state: MarkerState) -> BitmapIcon {
        let resolvedIcon = state.icon ?? DefaultMarkerIcon()
        return resolvedIcon.toBitmapIcon()
    }

    func unbind() {
        markerSubscriptions.values.forEach { $0.cancel() }
        markerSubscriptions.removeAll()
        markerStatesById.removeAll()
        renderer.unbind()
        mapView = nil
        destroy()
    }
}
