public protocol PolygonOverlayRendererProtocol {
    associatedtype ActualPolygon

    func onAdd(data: [PolygonOverlayAddParams]) async -> [ActualPolygon?]
    func onChange(data: [PolygonOverlayChangeParams<ActualPolygon>]) async -> [ActualPolygon?]
    func onRemove(data: [PolygonEntity<ActualPolygon>]) async
    func onPostProcess() async
}

open class AbstractPolygonOverlayRenderer<ActualPolygon>: PolygonOverlayRendererProtocol {
    public init() {}

    open func onPostProcess() async {}

    open func createPolygon(state: PolygonState) async -> ActualPolygon? {
        fatalError("Override in subclass")
    }

    open func updatePolygonProperties(
        polygon: ActualPolygon,
        current: PolygonEntity<ActualPolygon>,
        prev: PolygonEntity<ActualPolygon>
    ) async -> ActualPolygon? {
        fatalError("Override in subclass")
    }

    open func removePolygon(entity: PolygonEntity<ActualPolygon>) async {
        fatalError("Override in subclass")
    }

    public func onAdd(data: [PolygonOverlayAddParams]) async -> [ActualPolygon?] {
        var results: [ActualPolygon?] = []
        results.reserveCapacity(data.count)
        for params in data {
            results.append(await createPolygon(state: params.state))
        }
        return results
    }

    public func onChange(data: [PolygonOverlayChangeParams<ActualPolygon>]) async -> [ActualPolygon?] {
        var results: [ActualPolygon?] = []
        results.reserveCapacity(data.count)
        for params in data {
            guard let polygon = params.prev.polygon else {
                results.append(nil)
                continue
            }
            results.append(
                await updatePolygonProperties(
                    polygon: polygon,
                    current: params.current,
                    prev: params.prev
                )
            )
        }
        return results
    }

    public func onRemove(data: [PolygonEntity<ActualPolygon>]) async {
        for entity in data {
            await removePolygon(entity: entity)
        }
    }
}

public struct PolygonOverlayAddParams {
    public let state: PolygonState

    public init(state: PolygonState) {
        self.state = state
    }
}

public struct PolygonOverlayChangeParams<ActualPolygon> {
    public let current: PolygonEntity<ActualPolygon>
    public let prev: PolygonEntity<ActualPolygon>

    public init(current: PolygonEntity<ActualPolygon>, prev: PolygonEntity<ActualPolygon>) {
        self.current = current
        self.prev = prev
    }
}
