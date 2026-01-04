import Combine
import MapConductorCore
import MapLibre

@MainActor
final class MapLibreRasterLayerController: RasterLayerController<MapLibreRasterLayer, MapLibreRasterLayerOverlayRenderer> {
    private weak var mapView: MLNMapView?

    private var rasterSubscriptions: [String: AnyCancellable] = [:]
    private var rasterStatesById: [String: RasterLayerState] = [:]
    private var latestStates: [RasterLayerState] = []
    private var isStyleLoaded: Bool = false

    init(mapView: MLNMapView?) {
        self.mapView = mapView
        let rasterManager = RasterLayerManager<MapLibreRasterLayer>()
        let renderer = MapLibreRasterLayerOverlayRenderer(mapView: mapView)
        super.init(rasterLayerManager: rasterManager, renderer: renderer)
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

    func syncRasterLayers(_ layers: [RasterLayer]) {
        let newIds = Set(layers.map { $0.id })
        let oldIds = Set(rasterStatesById.keys)

        var newStatesById: [String: RasterLayerState] = [:]
        var shouldSyncList = false

        for layer in layers {
            let state = layer.state
            if let existingState = rasterStatesById[state.id], existingState !== state {
                rasterSubscriptions[state.id]?.cancel()
                rasterSubscriptions.removeValue(forKey: state.id)
                shouldSyncList = true
            }
            newStatesById[state.id] = state
            if !rasterLayerManager.hasEntity(state.id) {
                shouldSyncList = true
            }
        }

        rasterStatesById = newStatesById
        latestStates = layers.map { $0.state }

        if oldIds != newIds {
            shouldSyncList = true
        }

        if isStyleLoaded, shouldSyncList {
            Task { [weak self] in
                guard let self else { return }
                await self.add(data: self.latestStates)
            }
        }

        for layer in layers {
            subscribeToRasterLayer(layer.state)
        }

        let removedIds = oldIds.subtracting(newIds)
        for id in removedIds {
            rasterSubscriptions[id]?.cancel()
            rasterSubscriptions.removeValue(forKey: id)
        }
    }

    private func subscribeToRasterLayer(_ state: RasterLayerState) {
        guard rasterSubscriptions[state.id] == nil else { return }
        rasterSubscriptions[state.id] = state.asFlow()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                guard self.rasterStatesById[state.id] != nil else { return }
                Task { [weak self] in
                    guard let self else { return }
                    await self.update(state: state)
                }
            }
    }

    func unbind() {
        rasterSubscriptions.values.forEach { $0.cancel() }
        rasterSubscriptions.removeAll()
        rasterStatesById.removeAll()
        latestStates.removeAll()
        isStyleLoaded = false
        renderer.unbind()
        mapView = nil
        destroy()
    }
}
