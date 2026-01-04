import Foundation

open class PolygonController<ActualPolygon, Renderer: PolygonOverlayRendererProtocol>: OverlayControllerProtocol
where Renderer.ActualPolygon == ActualPolygon {
    public typealias StateType = PolygonState
    public typealias EntityType = PolygonEntity<ActualPolygon>
    public typealias EventType = PolygonEvent

    public let polygonManager: PolygonManager<ActualPolygon>
    open var renderer: Renderer

    public let zIndex: Int = 3
    private let semaphore = AsyncSemaphore(1)

    public var clickListener: ((PolygonEvent) -> Void)?

    public init(
        polygonManager: PolygonManager<ActualPolygon>,
        renderer: Renderer,
        clickListener: ((PolygonEvent) -> Void)? = nil
    ) {
        self.polygonManager = polygonManager
        self.renderer = renderer
        self.clickListener = clickListener
    }

    public func dispatchClick(event: PolygonEvent) {
        event.state.onClick?(event)
        clickListener?(event)
    }

    open func add(data: [PolygonState]) async {
        if polygonManager.isDestroyed { return }
        await semaphore.withPermit {
            if polygonManager.isDestroyed { return }
            var previous = Set(polygonManager.allEntities().map { $0.state.id })
            var added: [PolygonOverlayAddParams] = []
            var updated: [PolygonOverlayChangeParams<ActualPolygon>] = []
            var removed: [PolygonEntity<ActualPolygon>] = []

            for state in data {
                if previous.contains(state.id), let prevEntity = polygonManager.getEntity(state.id) {
                    updated.append(
                        PolygonOverlayChangeParams(
                            current: PolygonEntity(polygon: prevEntity.polygon, state: state),
                            prev: prevEntity
                        )
                    )
                    previous.remove(state.id)
                } else {
                    added.append(PolygonOverlayAddParams(state: state))
                    previous.remove(state.id)
                }
            }

            for remainId in previous {
                if let removedEntity = polygonManager.removeEntity(remainId) {
                    removed.append(removedEntity)
                }
            }

            if !removed.isEmpty {
                await renderer.onRemove(data: removed)
            }

            if !added.isEmpty {
                let actualPolygons = await renderer.onAdd(data: added)
                for (index, polygon) in actualPolygons.enumerated() {
                    guard let polygon else { continue }
                    let entity = PolygonEntity(polygon: polygon, state: added[index].state)
                    polygonManager.registerEntity(entity)
                }
            }

            if !updated.isEmpty {
                let actualPolygons = await renderer.onChange(data: updated)
                for (index, polygon) in actualPolygons.enumerated() {
                    guard let polygon else { continue }
                    let params = updated[index]
                    let entity = PolygonEntity(polygon: polygon, state: params.current.state)
                    polygonManager.registerEntity(entity)
                }
            }

            await renderer.onPostProcess()
        }
    }

    open func update(state: PolygonState) async {
        if polygonManager.isDestroyed { return }
        await semaphore.withPermit {
            guard let prevEntity = polygonManager.getEntity(state.id) else { return }
            let currentFinger = state.fingerPrint()
            let prevFinger = prevEntity.fingerPrint
            if currentFinger == prevFinger { return }

            let entity = PolygonEntity(polygon: prevEntity.polygon, state: state)
            let params = PolygonOverlayChangeParams(current: entity, prev: prevEntity)
            let polygons = await renderer.onChange(data: [params])

            if polygons.count == 1, let actualPolygon = polygons[0] {
                let updated = PolygonEntity(polygon: actualPolygon, state: state)
                polygonManager.registerEntity(updated)
            }
            await renderer.onPostProcess()
        }
    }

    open func clear() async {
        if polygonManager.isDestroyed { return }
        await semaphore.withPermit {
            let entities = polygonManager.allEntities()
            await renderer.onRemove(data: entities)
            polygonManager.clear()
        }
    }

    open func find(position: GeoPointProtocol) -> PolygonEntity<ActualPolygon>? {
        polygonManager.find(position: position)
    }

    open func onCameraChanged(mapCameraPosition: MapCameraPosition) async {}

    open func destroy() {
        polygonManager.destroy()
    }
}
