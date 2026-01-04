import Foundation

open class CircleController<ActualCircle, Renderer: CircleOverlayRendererProtocol>: OverlayControllerProtocol
where Renderer.ActualCircle == ActualCircle {
    public typealias StateType = CircleState
    public typealias EntityType = CircleEntity<ActualCircle>
    public typealias EventType = CircleEvent

    public let circleManager: CircleManager<ActualCircle>
    open var renderer: Renderer

    public let zIndex: Int = 3
    private let semaphore = AsyncSemaphore(1)

    public var clickListener: ((CircleEvent) -> Void)?

    public init(
        circleManager: CircleManager<ActualCircle>,
        renderer: Renderer,
        clickListener: ((CircleEvent) -> Void)? = nil
    ) {
        self.circleManager = circleManager
        self.renderer = renderer
        self.clickListener = clickListener
    }

    public func dispatchClick(event: CircleEvent) {
        event.state.onClick?(event)
        clickListener?(event)
    }

    open func add(data: [CircleState]) async {
        if circleManager.isDestroyed { return }
        await semaphore.withPermit {
            if circleManager.isDestroyed { return }
            var previous = Set(circleManager.allEntities().map { $0.state.id })
            var added: [CircleOverlayAddParams] = []
            var updated: [CircleOverlayChangeParams<ActualCircle>] = []
            var removed: [CircleEntity<ActualCircle>] = []

            for state in data {
                if previous.contains(state.id), let prevEntity = circleManager.getEntity(state.id) {
                    updated.append(
                        CircleOverlayChangeParams(
                            current: CircleEntity(circle: prevEntity.circle, state: state),
                            prev: prevEntity
                        )
                    )
                    previous.remove(state.id)
                } else {
                    added.append(CircleOverlayAddParams(state: state))
                    previous.remove(state.id)
                }
            }

            for remainId in previous {
                if let removedEntity = circleManager.removeEntity(remainId) {
                    removed.append(removedEntity)
                }
            }

            if !removed.isEmpty {
                await renderer.onRemove(data: removed)
            }

            if !added.isEmpty {
                let actualCircles = await renderer.onAdd(data: added)
                for (index, circle) in actualCircles.enumerated() {
                    guard let circle else { continue }
                    let entity = CircleEntity(circle: circle, state: added[index].state)
                    circleManager.registerEntity(entity)
                }
            }

            if !updated.isEmpty {
                let actualCircles = await renderer.onChange(data: updated)
                for (index, circle) in actualCircles.enumerated() {
                    guard let circle else { continue }
                    let params = updated[index]
                    let entity = CircleEntity(circle: circle, state: params.current.state)
                    circleManager.registerEntity(entity)
                }
            }

            await renderer.onPostProcess()
        }
    }

    open func update(state: CircleState) async {
        if circleManager.isDestroyed { return }
        await semaphore.withPermit {
            guard let prevEntity = circleManager.getEntity(state.id) else { return }
            let currentFinger = state.fingerPrint()
            let prevFinger = prevEntity.fingerPrint
            if currentFinger == prevFinger { return }

            let entity = CircleEntity(circle: prevEntity.circle, state: state)
            let params = CircleOverlayChangeParams(current: entity, prev: prevEntity)
            let circles = await renderer.onChange(data: [params])

            if circles.count == 1, let actualCircle = circles[0] {
                let updated = CircleEntity(circle: actualCircle, state: state)
                circleManager.registerEntity(updated)
            }
            await renderer.onPostProcess()
        }
    }

    open func clear() async {
        if circleManager.isDestroyed { return }
        await semaphore.withPermit {
            let entities = circleManager.allEntities()
            await renderer.onRemove(data: entities)
            circleManager.clear()
        }
    }

    open func find(position: GeoPointProtocol) -> CircleEntity<ActualCircle>? {
        circleManager.find(position: position)
    }

    open func onCameraChanged(mapCameraPosition: MapCameraPosition) async {
        await renderer.onPostProcess()
    }

    open func destroy() {
        circleManager.destroy()
    }
}
