import Combine
import UIKit

public struct CircleFingerPrint: Equatable, Hashable {
    public let id: Int
    public let center: Int
    public let radiusMeters: Int
    public let clickable: Int
    public let geodesic: Int
    public let strokeColor: Int
    public let strokeWidth: Int
    public let fillColor: Int
    public let zIndex: Int
    public let extra: Int
}

public struct CircleEvent {
    public let state: CircleState
    public let clicked: GeoPointProtocol

    public init(state: CircleState, clicked: GeoPointProtocol) {
        self.state = state
        self.clicked = clicked
    }
}

public typealias OnCircleEventHandler = (CircleEvent) -> Void

public final class CircleState: ObservableObject, Identifiable, Equatable, Hashable {
    public let id: String

    @Published public var center: GeoPointProtocol
    @Published public var radiusMeters: Double
    @Published public var geodesic: Bool
    @Published public var clickable: Bool
    @Published public var strokeColor: UIColor
    @Published public var strokeWidth: Double
    @Published public var fillColor: UIColor
    @Published public var extra: Any?
    @Published public var zIndex: Int?
    @Published public var onClick: OnCircleEventHandler?

    public init(
        center: GeoPointProtocol,
        radiusMeters: Double,
        geodesic: Bool = true,
        clickable: Bool = true,
        strokeColor: UIColor = .red,
        strokeWidth: Double = 1.0,
        fillColor: UIColor = UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.5),
        id: String? = nil,
        zIndex: Int? = nil,
        extra: Any? = nil,
        onClick: OnCircleEventHandler? = nil
    ) {
        let resolvedId = id ?? CircleState.makeCircleId(
            center: center,
            radiusMeters: radiusMeters,
            clickable: clickable,
            geodesic: geodesic,
            extra: extra,
            strokeColor: strokeColor,
            strokeWidth: strokeWidth,
            fillColor: fillColor,
            zIndex: zIndex
        )
        self.id = resolvedId
        self.center = center
        self.radiusMeters = radiusMeters
        self.geodesic = geodesic
        self.clickable = clickable
        self.strokeColor = strokeColor
        self.strokeWidth = strokeWidth
        self.fillColor = fillColor
        self.zIndex = zIndex
        self.extra = extra
        self.onClick = onClick
    }

    public func copy(
        center: GeoPointProtocol? = nil,
        radiusMeters: Double? = nil,
        geodesic: Bool? = nil,
        clickable: Bool? = nil,
        strokeColor: UIColor? = nil,
        strokeWidth: Double? = nil,
        fillColor: UIColor? = nil,
        id: String? = nil,
        zIndex: Int? = nil,
        extra: Any? = nil,
        onClick: OnCircleEventHandler? = nil
    ) -> CircleState {
        CircleState(
            center: center ?? self.center,
            radiusMeters: radiusMeters ?? self.radiusMeters,
            geodesic: geodesic ?? self.geodesic,
            clickable: clickable ?? self.clickable,
            strokeColor: strokeColor ?? self.strokeColor,
            strokeWidth: strokeWidth ?? self.strokeWidth,
            fillColor: fillColor ?? self.fillColor,
            id: id ?? self.id,
            zIndex: zIndex ?? self.zIndex,
            extra: extra ?? self.extra,
            onClick: onClick ?? self.onClick
        )
    }

    public func fingerPrint() -> CircleFingerPrint {
        CircleFingerPrint(
            id: javaHash(id),
            center: javaHash(center),
            radiusMeters: javaHash(radiusMeters),
            clickable: javaHash(clickable),
            geodesic: javaHash(geodesic),
            strokeColor: javaHash(strokeColor),
            strokeWidth: javaHash(strokeWidth),
            fillColor: javaHash(fillColor),
            zIndex: javaHash(zIndex),
            extra: javaHash(extra)
        )
    }

    public func asFlow() -> AnyPublisher<CircleFingerPrint, Never> {
        let combined = Publishers.CombineLatest4($center, $radiusMeters, $clickable, $geodesic)
        let combined2 = Publishers.CombineLatest4($strokeColor, $strokeWidth, $fillColor, $zIndex)
        return combined
            .combineLatest(combined2)
            .map { [id] left, right in
                CircleFingerPrint(
                    id: javaHash(id),
                    center: javaHash(left.0),
                    radiusMeters: javaHash(left.1),
                    clickable: javaHash(left.2),
                    geodesic: javaHash(left.3),
                    strokeColor: javaHash(right.0),
                    strokeWidth: javaHash(right.1),
                    fillColor: javaHash(right.2),
                    zIndex: javaHash(right.3),
                    extra: 0
                )
            }
            .combineLatest($extra)
            .map { finger, extra in
                CircleFingerPrint(
                    id: finger.id,
                    center: finger.center,
                    radiusMeters: finger.radiusMeters,
                    clickable: finger.clickable,
                    geodesic: finger.geodesic,
                    strokeColor: finger.strokeColor,
                    strokeWidth: finger.strokeWidth,
                    fillColor: finger.fillColor,
                    zIndex: finger.zIndex,
                    extra: javaHash(extra)
                )
            }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    public static func == (lhs: CircleState, rhs: CircleState) -> Bool {
        lhs.hashCode() == rhs.hashCode()
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(hashCode())
    }

    public func hashCode() -> Int {
        var result: Int32 = Int32(truncatingIfNeeded: javaHash(extra))
        result = result &* 31 &+ Int32(truncatingIfNeeded: javaHash(center))
        result = result &* 31 &+ Int32(truncatingIfNeeded: javaHash(clickable))
        result = result &* 31 &+ Int32(truncatingIfNeeded: javaHash(geodesic))
        result = result &* 31 &+ Int32(truncatingIfNeeded: javaHash(radiusMeters))
        result = result &* 31 &+ Int32(truncatingIfNeeded: javaHash(strokeColor))
        result = result &* 31 &+ Int32(truncatingIfNeeded: javaHash(strokeWidth))
        result = result &* 31 &+ Int32(truncatingIfNeeded: javaHash(fillColor))
        result = result &* 31 &+ Int32(truncatingIfNeeded: javaHash(zIndex))
        return Int(result)
    }

    private static func makeCircleId(
        center: GeoPointProtocol,
        radiusMeters: Double,
        clickable: Bool,
        geodesic: Bool,
        extra: Any?,
        strokeColor: UIColor,
        strokeWidth: Double,
        fillColor: UIColor,
        zIndex: Int?
    ) -> String {
        let hashCodes = [
            javaHash(center),
            javaHash(radiusMeters),
            javaHash(clickable),
            javaHash(geodesic),
            javaHash(extra),
            javaHash(strokeColor),
            javaHash(strokeWidth),
            javaHash(fillColor),
            javaHash(zIndex)
        ]
        return circleId(hashCodes: hashCodes)
    }
}

private func circleId(hashCodes: [Int]) -> String {
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

private func javaHash(_ value: Int?) -> Int {
    guard let value else { return 0 }
    return Int(Int32(truncatingIfNeeded: value))
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

    if let value = value as? NSObject {
        return value.hash
    }

    return 0
}

private func javaHash(_ color: UIColor) -> Int {
    var r: CGFloat = 0
    var g: CGFloat = 0
    var b: CGFloat = 0
    var a: CGFloat = 0
    if color.getRed(&r, green: &g, blue: &b, alpha: &a) {
        let ri = Int(r * 255.0)
        let gi = Int(g * 255.0)
        let bi = Int(b * 255.0)
        let ai = Int(a * 255.0)
        let argb = (ai << 24) | (ri << 16) | (gi << 8) | bi
        return Int(Int32(bitPattern: UInt32(argb)))
    }
    return color.hashValue
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
