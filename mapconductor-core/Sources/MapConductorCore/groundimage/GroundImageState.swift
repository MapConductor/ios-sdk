import Combine
import UIKit

public struct GroundImageFingerPrint: Equatable, Hashable {
    public let id: Int
    public let bounds: Int
    public let image: Int
    public let opacity: Int
    public let tileSize: Int
    public let extra: Int
}

public struct GroundImageEvent {
    public let state: GroundImageState
    public let clicked: GeoPointProtocol?

    public init(state: GroundImageState, clicked: GeoPointProtocol?) {
        self.state = state
        self.clicked = clicked
    }
}

public typealias OnGroundImageEventHandler = (GroundImageEvent) -> Void

public final class GroundImageState: ObservableObject, Identifiable, Equatable, Hashable {
    public let id: String

    @Published public var bounds: GeoRectBounds
    @Published public var image: UIImage
    @Published public var opacity: Double
    @Published public var tileSize: Int
    @Published public var extra: Any?
    @Published public var onClick: OnGroundImageEventHandler?

    public init(
        bounds: GeoRectBounds,
        image: UIImage,
        opacity: Double = 1.0,
        tileSize: Int = 512,
        id: String? = nil,
        extra: Any? = nil,
        onClick: OnGroundImageEventHandler? = nil
    ) {
        let resolvedId = id ?? GroundImageState.makeGroundImageId(
            bounds: bounds,
            image: image,
            opacity: opacity,
            tileSize: tileSize,
            extra: extra
        )
        self.id = resolvedId
        self.bounds = bounds
        self.image = image
        self.opacity = opacity
        self.tileSize = tileSize
        self.extra = extra
        self.onClick = onClick
    }

    public func copy(
        bounds: GeoRectBounds? = nil,
        image: UIImage? = nil,
        opacity: Double? = nil,
        tileSize: Int? = nil,
        id: String? = nil,
        extra: Any? = nil,
        onClick: OnGroundImageEventHandler? = nil
    ) -> GroundImageState {
        GroundImageState(
            bounds: bounds ?? self.bounds,
            image: image ?? self.image,
            opacity: opacity ?? self.opacity,
            tileSize: tileSize ?? self.tileSize,
            id: id ?? self.id,
            extra: extra ?? self.extra,
            onClick: onClick ?? self.onClick
        )
    }

    public func fingerPrint() -> GroundImageFingerPrint {
        GroundImageFingerPrint(
            id: javaHash(id),
            bounds: javaHash(bounds),
            image: javaHash(image),
            opacity: javaHash(opacity),
            tileSize: javaHash(tileSize),
            extra: javaHash(extra)
        )
    }

    public func asFlow() -> AnyPublisher<GroundImageFingerPrint, Never> {
        Publishers.CombineLatest4($bounds, $image, $opacity, $tileSize)
            .map { [id] bounds, image, opacity, tileSize in
                GroundImageFingerPrint(
                    id: javaHash(id),
                    bounds: javaHash(bounds),
                    image: javaHash(image),
                    opacity: javaHash(opacity),
                    tileSize: javaHash(tileSize),
                    extra: 0
                )
            }
            .combineLatest($extra)
            .map { finger, extra in
                GroundImageFingerPrint(
                    id: finger.id,
                    bounds: finger.bounds,
                    image: finger.image,
                    opacity: finger.opacity,
                    tileSize: finger.tileSize,
                    extra: javaHash(extra)
                )
            }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    public static func == (lhs: GroundImageState, rhs: GroundImageState) -> Bool {
        lhs.hashCode() == rhs.hashCode()
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(hashCode())
    }

    public func hashCode() -> Int {
        let finger = fingerPrint()
        var result: Int32 = Int32(truncatingIfNeeded: finger.bounds)
        result = result &* 31 &+ Int32(truncatingIfNeeded: finger.image)
        result = result &* 31 &+ Int32(truncatingIfNeeded: finger.opacity)
        result = result &* 31 &+ Int32(truncatingIfNeeded: finger.tileSize)
        result = result &* 31 &+ Int32(truncatingIfNeeded: finger.extra)
        return Int(result)
    }

    private static func makeGroundImageId(
        bounds: GeoRectBounds,
        image: UIImage,
        opacity: Double,
        tileSize: Int,
        extra: Any?
    ) -> String {
        let hashCodes = [
            javaHash(bounds),
            javaHash(image),
            javaHash(opacity),
            javaHash(tileSize),
            javaHash(extra)
        ]
        return groundImageId(hashCodes: hashCodes)
    }
}

private func groundImageId(hashCodes: [Int]) -> String {
    var result: Int32 = 0
    for hash in hashCodes {
        result = result &* 31 &+ Int32(truncatingIfNeeded: hash)
    }
    return String(result)
}

private func javaHash(_ value: Double) -> Int {
    let bits = value.bitPattern
    let combined = bits ^ (bits >> 32)
    return Int(Int32(truncatingIfNeeded: combined))
}

private func javaHash(_ value: Int) -> Int {
    Int(Int32(truncatingIfNeeded: value))
}

private func javaHash(_ value: Int64) -> Int {
    let combined = value ^ (value >> 32)
    return Int(Int32(truncatingIfNeeded: combined))
}

private func javaHash(_ value: String) -> Int {
    var result: Int32 = 0
    for u in value.unicodeScalars {
        result = result &* 31 &+ Int32(u.value)
    }
    return Int(result)
}

private func javaHash(_ value: Any?) -> Int {
    if value == nil { return 0 }

    if let value = value as? String {
        return javaHash(value)
    }

    if let value = value as? Bool {
        return value ? 1231 : 1237
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

    if let value = value as? NSObject {
        return value.hash
    }

    return 0
}

private func javaHash(_ bounds: GeoRectBounds) -> Int {
    var result: Int32 = 0
    if let sw = bounds.southWest {
        result = result &* 31 &+ Int32(truncatingIfNeeded: javaHash(sw))
    }
    if let ne = bounds.northEast {
        result = result &* 31 &+ Int32(truncatingIfNeeded: javaHash(ne))
    }
    return Int(result)
}

private func javaHash(_ point: GeoPointProtocol) -> Int {
    let latHash = Int64(point.latitude * 1e7)
    let lngHash = Int64(point.longitude * 1e7)
    let altHash = Int64((point.altitude ?? 0.0) * 1e7)

    var result: Int32 = Int32(truncatingIfNeeded: javaHash(latHash))
    result = result &* 31 &+ Int32(truncatingIfNeeded: javaHash(lngHash))
    result = result &* 31 &+ Int32(truncatingIfNeeded: javaHash(altHash))
    return Int(result)
}
