public protocol CircleOverlayRendererProtocol {
    associatedtype ActualCircle

    func onAdd(data: [CircleOverlayAddParams]) async -> [ActualCircle?]
    func onChange(data: [CircleOverlayChangeParams<ActualCircle>]) async -> [ActualCircle?]
    func onRemove(data: [CircleEntity<ActualCircle>]) async
    func onPostProcess() async
}

open class AbstractCircleOverlayRenderer<ActualCircle>: CircleOverlayRendererProtocol {
    public init() {}

    open func onPostProcess() async {}

    open func createCircle(state: CircleState) async -> ActualCircle? {
        fatalError("Override in subclass")
    }

    open func updateCircleProperties(
        circle: ActualCircle,
        current: CircleEntity<ActualCircle>,
        prev: CircleEntity<ActualCircle>
    ) async -> ActualCircle? {
        fatalError("Override in subclass")
    }

    open func removeCircle(entity: CircleEntity<ActualCircle>) async {
        fatalError("Override in subclass")
    }

    public func onAdd(data: [CircleOverlayAddParams]) async -> [ActualCircle?] {
        var results: [ActualCircle?] = []
        results.reserveCapacity(data.count)
        for params in data {
            results.append(await createCircle(state: params.state))
        }
        return results
    }

    public func onChange(data: [CircleOverlayChangeParams<ActualCircle>]) async -> [ActualCircle?] {
        var results: [ActualCircle?] = []
        results.reserveCapacity(data.count)
        for params in data {
            guard let circle = params.prev.circle else {
                results.append(nil)
                continue
            }
            results.append(
                await updateCircleProperties(
                    circle: circle,
                    current: params.current,
                    prev: params.prev
                )
            )
        }
        return results
    }

    public func onRemove(data: [CircleEntity<ActualCircle>]) async {
        for entity in data {
            await removeCircle(entity: entity)
        }
    }
}

public struct CircleOverlayAddParams {
    public let state: CircleState

    public init(state: CircleState) {
        self.state = state
    }
}

public struct CircleOverlayChangeParams<ActualCircle> {
    public let current: CircleEntity<ActualCircle>
    public let prev: CircleEntity<ActualCircle>

    public init(current: CircleEntity<ActualCircle>, prev: CircleEntity<ActualCircle>) {
        self.current = current
        self.prev = prev
    }
}
