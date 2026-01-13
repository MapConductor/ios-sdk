import Combine
import MapKit
import MapConductorCore

@MainActor
final class MapKitRasterLayerController: RasterLayerController<MKTileOverlay, MapKitRasterLayerOverlayRenderer> {
    private weak var mapView: MKMapView?

    private var rasterStatesById: [String: RasterLayerState] = [:]
    private var rasterSubscriptions: [String: AnyCancellable] = [:]

    init(mapView: MKMapView?) {
        self.mapView = mapView
        let rasterManager = RasterLayerManager<MKTileOverlay>()
        let renderer = MapKitRasterLayerOverlayRenderer(mapView: mapView)
        super.init(rasterLayerManager: rasterManager, renderer: renderer)
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

        if oldIds != newIds {
            shouldSyncList = true
        }

        let removedIds = oldIds.subtracting(newIds)
        for id in removedIds {
            rasterSubscriptions[id]?.cancel()
            rasterSubscriptions.removeValue(forKey: id)
        }

        if shouldSyncList {
            Task { [weak self] in
                guard let self else { return }
                await self.add(data: layers.map { $0.state })
            }
        }

        for layer in layers {
            subscribeToRasterLayer(layer.state)
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
        mapView = nil
        destroy()
    }
}
