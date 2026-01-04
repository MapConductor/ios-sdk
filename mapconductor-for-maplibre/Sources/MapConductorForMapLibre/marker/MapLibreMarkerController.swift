import Combine
import CoreGraphics
import CoreLocation
import MapLibre
import MapConductorCore

@MainActor
final class MapLibreMarkerController: AbstractMarkerController<MLNPointFeature, MapLibreMarkerOverlayRenderer> {
    private weak var mapView: MLNMapView?

    private var markerSubscriptions: [String: AnyCancellable] = [:]
    private var markerStatesById: [String: MarkerState] = [:]
    private var latestStates: [MarkerState] = []
    private var isStyleLoaded: Bool = false

    private var eventController: MapLibreMarkerEventController?
    let onUpdateInfoBubble: (String) -> Void

    init(mapView: MLNMapView?, onUpdateInfoBubble: @escaping (String) -> Void) {
        self.mapView = mapView
        self.onUpdateInfoBubble = onUpdateInfoBubble

        let markerManager = MarkerManager<MLNPointFeature>.defaultManager()
        let layer = MarkerLayer(
            sourceId: "mapconductor-markers-source-\(UUID().uuidString)",
            layerId: "mapconductor-markers-layer-\(UUID().uuidString)"
        )

        let renderer = MapLibreMarkerOverlayRenderer(
            mapView: mapView,
            markerManager: markerManager,
            markerLayer: layer
        )

        super.init(markerManager: markerManager, renderer: renderer)

        self.eventController = MapLibreMarkerEventController(mapView: mapView, markerController: self)
    }

    func onStyleLoaded(_ style: MLNStyle) {
        isStyleLoaded = true
        MCLog.marker("MapLibreMarkerController.onStyleLoaded")
        renderer.onStyleLoaded(style)
        if !latestStates.isEmpty {
            Task { [weak self] in
                guard let self else { return }
                await self.add(data: self.latestStates)
            }
        }
    }

    func handleTap(at point: CGPoint) -> Bool {
        eventController?.handleTap(at: point) ?? false
    }

    func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
        eventController?.handleLongPress(recognizer)
    }

    func syncMarkers(_ markers: [Marker]) {
        MCLog.marker("MapLibreMarkerController.syncMarkers count=\(markers.count) styleLoaded=\(isStyleLoaded)")
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

        markerStatesById = newStatesById
        latestStates = markers.map { $0.state }

        if oldIds != newIds {
            shouldSyncList = true
        }

        if isStyleLoaded, shouldSyncList {
            Task { [weak self] in
                guard let self else { return }
                MCLog.marker("MapLibreMarkerController.syncMarkers -> add()")
                await self.add(data: self.latestStates)
            }
        }

        for marker in markers {
            subscribeToMarker(marker.state)
            onUpdateInfoBubble(marker.id)
        }

        let removedIds = oldIds.subtracting(newIds)
        for id in removedIds {
            markerSubscriptions[id]?.cancel()
            markerSubscriptions.removeValue(forKey: id)
        }
    }

    private func subscribeToMarker(_ state: MarkerState) {
        guard markerSubscriptions[state.id] == nil else { return }
        MCLog.marker("MapLibreMarkerController.subscribe id=\(state.id)")
        markerSubscriptions[state.id] = state.asFlow()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                guard self.markerStatesById[state.id] != nil else { return }
                MCLog.marker("MapLibreMarkerController.asFlow emit id=\(state.id) anim=\(String(describing: state.getAnimation()))")
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
        latestStates.removeAll()
        isStyleLoaded = false
        eventController?.unbind()
        eventController = nil
        renderer.unbind()
        mapView = nil
        destroy()
    }
}
