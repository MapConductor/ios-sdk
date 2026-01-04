import Combine

public struct RasterLayerFingerPrint: Equatable, Hashable {
    public let id: Int
    public let source: Int
    public let opacity: Int
    public let visible: Int
    public let extra: Int
}

public struct RasterLayerEvent {
    public let state: RasterLayerState

    public init(state: RasterLayerState) {
        self.state = state
    }
}

public typealias OnRasterLayerEventHandler = (RasterLayerEvent) -> Void

public final class RasterLayerState: ObservableObject, Identifiable, Equatable, Hashable {
    public let id: String

    @Published public var source: RasterSource
    @Published public var opacity: Double
    @Published public var visible: Bool
    @Published public var extra: Any?

    public init(
        source: RasterSource,
        opacity: Double = 1.0,
        visible: Bool = true,
        id: String? = nil,
        extra: Any? = nil
    ) {
        let resolvedId = id ?? RasterLayerState.makeRasterLayerId(
            source: source,
            opacity: opacity,
            visible: visible,
            extra: extra
        )
        self.id = resolvedId
        self.source = source
        self.opacity = opacity
        self.visible = visible
        self.extra = extra
    }

    public func copy(
        source: RasterSource? = nil,
        opacity: Double? = nil,
        visible: Bool? = nil,
        id: String? = nil,
        extra: Any? = nil
    ) -> RasterLayerState {
        RasterLayerState(
            source: source ?? self.source,
            opacity: opacity ?? self.opacity,
            visible: visible ?? self.visible,
            id: id ?? self.id,
            extra: extra ?? self.extra
        )
    }

    public func fingerPrint() -> RasterLayerFingerPrint {
        RasterLayerFingerPrint(
            id: javaHash(id),
            source: javaHash(source),
            opacity: javaHash(opacity),
            visible: javaHash(visible),
            extra: javaHash(extra)
        )
    }

    public func asFlow() -> AnyPublisher<RasterLayerFingerPrint, Never> {
        let combined = Publishers.CombineLatest3($source, $opacity, $visible)
        return combined
            .map { [id] source, opacity, visible in
                RasterLayerFingerPrint(
                    id: javaHash(id),
                    source: javaHash(source),
                    opacity: javaHash(opacity),
                    visible: javaHash(visible),
                    extra: 0
                )
            }
            .combineLatest($extra)
            .map { finger, extra in
                RasterLayerFingerPrint(
                    id: finger.id,
                    source: finger.source,
                    opacity: finger.opacity,
                    visible: finger.visible,
                    extra: javaHash(extra)
                )
            }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    public static func == (lhs: RasterLayerState, rhs: RasterLayerState) -> Bool {
        lhs.hashCode() == rhs.hashCode()
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(hashCode())
    }

    public func hashCode() -> Int {
        var result: Int32 = Int32(truncatingIfNeeded: javaHash(source))
        result = result &* 31 &+ Int32(truncatingIfNeeded: javaHash(opacity))
        result = result &* 31 &+ Int32(truncatingIfNeeded: javaHash(visible))
        result = result &* 31 &+ Int32(truncatingIfNeeded: javaHash(extra))
        return Int(result)
    }

    private static func makeRasterLayerId(
        source: RasterSource,
        opacity: Double,
        visible: Bool,
        extra: Any?
    ) -> String {
        let hashCodes = [
            javaHash(source),
            javaHash(opacity),
            javaHash(visible),
            javaHash(extra)
        ]
        return rasterLayerId(hashCodes: hashCodes)
    }
}

private func rasterLayerId(hashCodes: [Int]) -> String {
    var result: Int32 = 0
    for hash in hashCodes {
        result = result &* 31 &+ Int32(truncatingIfNeeded: hash)
    }
    return String(result)
}

private func javaHash(_ value: Bool) -> Int {
    value ? 1231 : 1237
}

private func javaHash(_ value: Double) -> Int {
    let bits = value.bitPattern
    let combined = bits ^ (bits >> 32)
    return Int(Int32(truncatingIfNeeded: combined))
}

private func javaHash(_ value: String) -> Int {
    var result: Int32 = 0
    for scalar in value.unicodeScalars {
        result = result &* 31 &+ Int32(truncatingIfNeeded: scalar.value)
    }
    return Int(result)
}

private func javaHash(_ value: Any?) -> Int {
    if value == nil { return 0 }

    if let value = value as? String {
        return javaHash(value)
    }

    if let value = value as? Bool {
        return javaHash(value)
    }

    if let value = value as? Double {
        return javaHash(value)
    }

    if let value = value as? Float {
        return javaHash(Double(value))
    }

    if let value = value as? Int {
        return Int(Int32(truncatingIfNeeded: value))
    }

    if let value = value as? Int64 {
        let combined = value ^ (value >> 32)
        return Int(Int32(truncatingIfNeeded: combined))
    }

    if let value = value as? UInt64 {
        let combined = value ^ (value >> 32)
        return Int(Int32(truncatingIfNeeded: combined))
    }

    if let value = value as? AnyHashable {
        return value.hashValue
    }

    return 0
}

private func javaHash(_ source: RasterSource) -> Int {
    switch source {
    case let .urlTemplate(template, tileSize, minZoom, maxZoom, attribution, scheme):
        let hashCodes = [
            javaHash("urlTemplate"),
            javaHash(template),
            javaHash(tileSize),
            javaHash(minZoom),
            javaHash(maxZoom),
            javaHash(attribution),
            javaHash(scheme.rawValue)
        ]
        return listHashCode(hashCodes)
    case let .tileJson(url):
        return listHashCode([javaHash("tileJson"), javaHash(url)])
    case let .arcGisService(serviceUrl):
        return listHashCode([javaHash("arcGisService"), javaHash(serviceUrl)])
    }
}

private func javaHash(_ value: Int?) -> Int {
    guard let value else { return 0 }
    return Int(Int32(truncatingIfNeeded: value))
}

private func listHashCode(_ values: [Int]) -> Int {
    var result: Int32 = 0
    for value in values {
        result = result &* 31 &+ Int32(truncatingIfNeeded: value)
    }
    return Int(result)
}
