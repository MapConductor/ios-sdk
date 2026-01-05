import Combine
import MapConductorCore
import MapLibre

@MainActor
final class MapLibreRasterLayerController: RasterLayerController<MapLibreRasterLayer, MapLibreRasterLayerOverlayRenderer> {
    private weak var mapView: MLNMapView?

    private var rasterStatesById: [String: RasterLayerState] = [:]
    private var latestStates: [RasterLayerState] = []
    private var isStyleLoaded: Bool = false
    private var pendingUpdate: Task<Void, Never>?

    init(mapView: MLNMapView?) {
        self.mapView = mapView
        let rasterManager = RasterLayerManager<MapLibreRasterLayer>()
        let renderer = MapLibreRasterLayerOverlayRenderer(mapView: mapView)
        super.init(rasterLayerManager: rasterManager, renderer: renderer)
    }

    func onStyleLoaded(_ style: MLNStyle) {
        isStyleLoaded = true
        renderer.onStyleLoaded(style)

        // Add initial layers if they were set before style loaded
        if !latestStates.isEmpty {
            syncLayersDirectly(latestStates)
        }
    }

    func syncRasterLayers(_ layers: [RasterLayer]) {
        let newIds = Set(layers.map { $0.id })
        let oldIds = Set(rasterStatesById.keys)

        var newStatesById: [String: RasterLayerState] = [:]
        var shouldSync = false

        for layer in layers {
            let state = layer.state
            if let existingState = rasterStatesById[state.id], existingState !== state {
                shouldSync = true
            }
            newStatesById[state.id] = state
            if !rasterLayerManager.hasEntity(state.id) {
                shouldSync = true
            }
        }

        // Check if properties changed
        if !shouldSync {
            for (id, newState) in newStatesById {
                if let entity = rasterLayerManager.getEntity(id) {
                    if entity.fingerPrint != newState.fingerPrint() {
                        shouldSync = true
                        break
                    }
                }
            }
        }

        rasterStatesById = newStatesById
        latestStates = layers.map { $0.state }

        if oldIds != newIds {
            shouldSync = true
        }

        guard isStyleLoaded, shouldSync else { return }

        // Perform synchronous update directly on main thread
        // Bypass async/await entirely to avoid object lifetime issues
        syncLayersDirectly(layers.map { $0.state })
    }

    private func syncLayersDirectly(_ states: [RasterLayerState]) {
        let previous = Set(rasterLayerManager.allEntities().map { $0.state.id })
        let newIds = Set(states.map { $0.id })

        // Remove layers that are no longer in the list
        for id in previous.subtracting(newIds) {
            if let entity = rasterLayerManager.getEntity(id) {
                renderer.removeLayerSync(entity: entity)
                _ = rasterLayerManager.removeEntity(id)
            }
        }

        // Add or update layers
        for state in states {
            if let prevEntity = rasterLayerManager.getEntity(state.id) {
                // Update existing layer
                if prevEntity.fingerPrint != state.fingerPrint() {
                    if let updatedLayer = renderer.updateLayerSync(
                        layer: prevEntity.layer!,
                        current: RasterLayerEntity(layer: prevEntity.layer, state: state),
                        prev: prevEntity
                    ) {
                        let entity = RasterLayerEntity(layer: updatedLayer, state: state)
                        rasterLayerManager.registerEntity(entity)
                    }
                }
            } else {
                // Add new layer
                if let newLayer = renderer.createLayerSync(state: state) {
                    let entity = RasterLayerEntity(layer: newLayer, state: state)
                    rasterLayerManager.registerEntity(entity)
                }
            }
        }
    }

    // Override to prevent async calls from camera changes
    override func onCameraChanged(mapCameraPosition: MapCameraPosition) async {
        // Raster layers don't need to respond to camera changes
        // Empty implementation prevents async Task creation
    }

    func unbind() {
        pendingUpdate?.cancel()
        pendingUpdate = nil
        rasterStatesById.removeAll()
        latestStates.removeAll()
        isStyleLoaded = false
        renderer.unbind()
        mapView = nil
        destroy()
    }
}
