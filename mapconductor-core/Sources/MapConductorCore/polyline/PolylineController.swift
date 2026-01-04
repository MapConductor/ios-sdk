import Foundation

open class PolylineController<ActualPolyline, Renderer: PolylineOverlayRendererProtocol>: OverlayControllerProtocol
where Renderer.ActualPolyline == ActualPolyline {
    public typealias StateType = PolylineState
    public typealias EntityType = PolylineEntity<ActualPolyline>
    public typealias EventType = PolylineEvent

    public let polylineManager: PolylineManager<ActualPolyline>
    open var renderer: Renderer

    public let zIndex: Int = 5
    private let semaphore = AsyncSemaphore(1)
    private var currentCameraPosition: MapCameraPosition?

    public var clickListener: ((PolylineEvent) -> Void)?

    public init(
        polylineManager: PolylineManager<ActualPolyline>,
        renderer: Renderer,
        clickListener: ((PolylineEvent) -> Void)? = nil
    ) {
        self.polylineManager = polylineManager
        self.renderer = renderer
        self.clickListener = clickListener
    }

    public func dispatchClick(event: PolylineEvent) {
        event.state.onClick?(event)
        clickListener?(event)
    }

    open func add(data: [PolylineState]) async {
        if polylineManager.isDestroyed { return }
        await semaphore.withPermit {
            if polylineManager.isDestroyed { return }
            var previous = Set(polylineManager.allEntities().map { $0.state.id })
            var added: [PolylineOverlayAddParams] = []
            var updated: [PolylineOverlayChangeParams<ActualPolyline>] = []
            var removed: [PolylineEntity<ActualPolyline>] = []

            for state in data {
                if previous.contains(state.id), let prevEntity = polylineManager.getEntity(state.id) {
                    updated.append(
                        PolylineOverlayChangeParams(
                            current: PolylineEntity(polyline: prevEntity.polyline, state: state),
                            prev: prevEntity
                        )
                    )
                    previous.remove(state.id)
                } else {
                    added.append(PolylineOverlayAddParams(state: state))
                    previous.remove(state.id)
                }
            }

            for remainId in previous {
                if let removedEntity = polylineManager.removeEntity(remainId) {
                    removed.append(removedEntity)
                }
            }

            if !removed.isEmpty {
                await renderer.onRemove(data: removed)
            }

            if !added.isEmpty {
                let actualPolylines = await renderer.onAdd(data: added)
                for (index, polyline) in actualPolylines.enumerated() {
                    guard let polyline else { continue }
                    let entity = PolylineEntity(polyline: polyline, state: added[index].state)
                    polylineManager.registerEntity(entity)
                }
            }

            if !updated.isEmpty {
                let actualPolylines = await renderer.onChange(data: updated)
                for (index, polyline) in actualPolylines.enumerated() {
                    guard let polyline else { continue }
                    let params = updated[index]
                    let entity = PolylineEntity(polyline: polyline, state: params.current.state)
                    polylineManager.registerEntity(entity)
                }
            }

            await renderer.onPostProcess()
        }
    }

    open func update(state: PolylineState) async {
        if polylineManager.isDestroyed { return }
        await semaphore.withPermit {
            guard let prevEntity = polylineManager.getEntity(state.id) else { return }
            let currentFinger = state.fingerPrint()
            let prevFinger = prevEntity.fingerPrint
            if currentFinger == prevFinger { return }

            let entity = PolylineEntity(polyline: prevEntity.polyline, state: state)
            let params = PolylineOverlayChangeParams(current: entity, prev: prevEntity)
            let polylines = await renderer.onChange(data: [params])

            if polylines.count == 1, let actualPolyline = polylines[0] {
                let updated = PolylineEntity(polyline: actualPolyline, state: state)
                polylineManager.registerEntity(updated)
            }

            await renderer.onPostProcess()
        }
    }

    open func clear() async {
        if polylineManager.isDestroyed { return }
        await semaphore.withPermit {
            let entities = polylineManager.allEntities()
            await renderer.onRemove(data: entities)
            await renderer.onPostProcess()
            polylineManager.clear()
        }
    }

    open func find(position: GeoPointProtocol) -> PolylineEntity<ActualPolyline>? {
        polylineManager.find(position: position, cameraPosition: currentCameraPosition)?.entity
    }

    public func findWithClosestPoint(position: GeoPointProtocol) -> PolylineHitResult<ActualPolyline>? {
        polylineManager.find(position: position, cameraPosition: currentCameraPosition)
    }

    open func onCameraChanged(mapCameraPosition: MapCameraPosition) async {
        currentCameraPosition = mapCameraPosition
    }

    open func destroy() {
        polylineManager.destroy()
    }
}
