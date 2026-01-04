public protocol PolylineOverlayRendererProtocol {
    associatedtype ActualPolyline

    func onAdd(data: [PolylineOverlayAddParams]) async -> [ActualPolyline?]
    func onChange(data: [PolylineOverlayChangeParams<ActualPolyline>]) async -> [ActualPolyline?]
    func onRemove(data: [PolylineEntity<ActualPolyline>]) async
    func onPostProcess() async
}

open class AbstractPolylineOverlayRenderer<ActualPolyline>: PolylineOverlayRendererProtocol {
    public init() {}

    open func onPostProcess() async {}

    open func createPolyline(state: PolylineState) async -> ActualPolyline? {
        fatalError("Override in subclass")
    }

    open func updatePolylineProperties(
        polyline: ActualPolyline,
        current: PolylineEntity<ActualPolyline>,
        prev: PolylineEntity<ActualPolyline>
    ) async -> ActualPolyline? {
        fatalError("Override in subclass")
    }

    open func removePolyline(entity: PolylineEntity<ActualPolyline>) async {
        fatalError("Override in subclass")
    }

    public func onAdd(data: [PolylineOverlayAddParams]) async -> [ActualPolyline?] {
        var results: [ActualPolyline?] = []
        results.reserveCapacity(data.count)
        for params in data {
            results.append(await createPolyline(state: params.state))
        }
        return results
    }

    public func onChange(data: [PolylineOverlayChangeParams<ActualPolyline>]) async -> [ActualPolyline?] {
        var results: [ActualPolyline?] = []
        results.reserveCapacity(data.count)
        for params in data {
            guard let polyline = params.prev.polyline else {
                results.append(nil)
                continue
            }
            results.append(
                await updatePolylineProperties(
                    polyline: polyline,
                    current: params.current,
                    prev: params.prev
                )
            )
        }
        return results
    }

    public func onRemove(data: [PolylineEntity<ActualPolyline>]) async {
        for entity in data {
            await removePolyline(entity: entity)
        }
    }
}

public struct PolylineOverlayAddParams {
    public let state: PolylineState

    public init(state: PolylineState) {
        self.state = state
    }
}

public struct PolylineOverlayChangeParams<ActualPolyline> {
    public let current: PolylineEntity<ActualPolyline>
    public let prev: PolylineEntity<ActualPolyline>

    public init(
        current: PolylineEntity<ActualPolyline>,
        prev: PolylineEntity<ActualPolyline>
    ) {
        self.current = current
        self.prev = prev
    }
}
