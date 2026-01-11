public protocol GroundImageOverlayRendererProtocol {
    associatedtype ActualGroundImage

    func onAdd(data: [GroundImageOverlayAddParams]) async -> [ActualGroundImage?]
    func onChange(data: [GroundImageOverlayChangeParams<ActualGroundImage>]) async -> [ActualGroundImage?]
    func onRemove(data: [GroundImageEntity<ActualGroundImage>]) async
    func onPostProcess() async
}

open class AbstractGroundImageOverlayRenderer<ActualGroundImage>: GroundImageOverlayRendererProtocol {
    public init() {}

    open func onPostProcess() async {}

    open func createGroundImage(state: GroundImageState) async -> ActualGroundImage? {
        fatalError("Override in subclass")
    }

    open func updateGroundImageProperties(
        groundImage: ActualGroundImage,
        current: GroundImageEntity<ActualGroundImage>,
        prev: GroundImageEntity<ActualGroundImage>
    ) async -> ActualGroundImage? {
        fatalError("Override in subclass")
    }

    open func removeGroundImage(entity: GroundImageEntity<ActualGroundImage>) async {
        fatalError("Override in subclass")
    }

    public func onAdd(data: [GroundImageOverlayAddParams]) async -> [ActualGroundImage?] {
        var results: [ActualGroundImage?] = []
        results.reserveCapacity(data.count)
        for params in data {
            results.append(await createGroundImage(state: params.state))
        }
        return results
    }

    public func onChange(data: [GroundImageOverlayChangeParams<ActualGroundImage>]) async -> [ActualGroundImage?] {
        var results: [ActualGroundImage?] = []
        results.reserveCapacity(data.count)
        for params in data {
            guard let groundImage = params.prev.groundImage else {
                results.append(nil)
                continue
            }
            results.append(
                await updateGroundImageProperties(
                    groundImage: groundImage,
                    current: params.current,
                    prev: params.prev
                )
            )
        }
        return results
    }

    public func onRemove(data: [GroundImageEntity<ActualGroundImage>]) async {
        for entity in data {
            await removeGroundImage(entity: entity)
        }
    }
}

public struct GroundImageOverlayAddParams {
    public let state: GroundImageState

    public init(state: GroundImageState) {
        self.state = state
    }
}

public struct GroundImageOverlayChangeParams<ActualGroundImage> {
    public let current: GroundImageEntity<ActualGroundImage>
    public let prev: GroundImageEntity<ActualGroundImage>

    public init(current: GroundImageEntity<ActualGroundImage>, prev: GroundImageEntity<ActualGroundImage>) {
        self.current = current
        self.prev = prev
    }
}

