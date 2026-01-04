import Combine
import CoreLocation
import UIKit

public struct PolylineFingerPrint: Equatable, Hashable {
    public let id: Int
    public let strokeColor: Int
    public let strokeWidth: Int
    public let geodesic: Int
    public let points: Int
    public let extra: Int
}

public struct PolylineEvent {
    public let state: PolylineState
    public let clicked: GeoPointProtocol

    public init(state: PolylineState, clicked: GeoPointProtocol) {
        self.state = state
        self.clicked = clicked
    }
}

public typealias OnPolylineEventHandler = (PolylineEvent) -> Void

public final class PolylineState: ObservableObject, Identifiable, Equatable, Hashable {
    public let id: String

    @Published public var strokeColor: UIColor
    @Published public var strokeWidth: Double
    @Published public var geodesic: Bool
    @Published public var points: [GeoPointProtocol]
    @Published public var extra: Any?
    @Published public var onClick: OnPolylineEventHandler?

    public init(
        points: [GeoPointProtocol],
        id: String? = nil,
        strokeColor: UIColor = .black,
        strokeWidth: Double = 1.0,
        geodesic: Bool = false,
        extra: Any? = nil,
        onClick: OnPolylineEventHandler? = nil
    ) {
        let resolvedId = id ?? PolylineState.makePolylineId(
            points: points,
            strokeColor: strokeColor,
            strokeWidth: strokeWidth,
            geodesic: geodesic,
            extra: extra
        )
        self.id = resolvedId
        self.strokeColor = strokeColor
        self.strokeWidth = strokeWidth
        self.geodesic = geodesic
        self.points = points
        self.extra = extra
        self.onClick = onClick
    }

    public func copy(
        points: [GeoPointProtocol]? = nil,
        id: String? = nil,
        strokeColor: UIColor? = nil,
        strokeWidth: Double? = nil,
        geodesic: Bool? = nil,
        extra: Any? = nil,
        onClick: OnPolylineEventHandler? = nil
    ) -> PolylineState {
        PolylineState(
            points: points ?? self.points,
            id: id ?? self.id,
            strokeColor: strokeColor ?? self.strokeColor,
            strokeWidth: strokeWidth ?? self.strokeWidth,
            geodesic: geodesic ?? self.geodesic,
            extra: extra ?? self.extra,
            onClick: onClick ?? self.onClick
        )
    }

    public func fingerPrint() -> PolylineFingerPrint {
        PolylineFingerPrint(
            id: javaHash(id),
            strokeColor: javaHash(strokeColor),
            strokeWidth: javaHash(strokeWidth),
            geodesic: javaHash(geodesic),
            points: listHashCode(points),
            extra: javaHash(extra)
        )
    }

    public func asFlow() -> AnyPublisher<PolylineFingerPrint, Never> {
        let combined = Publishers.CombineLatest4($strokeColor, $strokeWidth, $geodesic, $points)
        return combined
            .map { [id] strokeColor, strokeWidth, geodesic, points in
                PolylineFingerPrint(
                    id: javaHash(id),
                    strokeColor: javaHash(strokeColor),
                    strokeWidth: javaHash(strokeWidth),
                    geodesic: javaHash(geodesic),
                    points: listHashCode(points),
                    extra: 0
                )
            }
            .combineLatest($extra)
            .map { finger, extra in
                PolylineFingerPrint(
                    id: finger.id,
                    strokeColor: finger.strokeColor,
                    strokeWidth: finger.strokeWidth,
                    geodesic: finger.geodesic,
                    points: finger.points,
                    extra: javaHash(extra)
                )
            }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    public static func == (lhs: PolylineState, rhs: PolylineState) -> Bool {
        lhs.hashCode() == rhs.hashCode()
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(hashCode())
    }

    public func hashCode() -> Int {
        var result: Int32 = Int32(truncatingIfNeeded: javaHash(extra))
        result = result &* 31 &+ Int32(truncatingIfNeeded: javaHash(strokeColor))
        result = result &* 31 &+ Int32(truncatingIfNeeded: javaHash(strokeWidth))
        result = result &* 31 &+ Int32(truncatingIfNeeded: javaHash(geodesic))
        result = result &* 31 &+ Int32(truncatingIfNeeded: listHashCode(points))
        return Int(result)
    }

    private static func makePolylineId(
        points: [GeoPointProtocol],
        strokeColor: UIColor,
        strokeWidth: Double,
        geodesic: Bool,
        extra: Any?
    ) -> String {
        let hashCodes = [
            listHashCode(points),
            javaHash(strokeColor),
            javaHash(strokeWidth),
            javaHash(geodesic),
            javaHash(extra)
        ]
        return markerId(hashCodes: hashCodes)
    }
}

private func listHashCode(_ points: [GeoPointProtocol]) -> Int {
    var result: Int32 = 0
    for point in points {
        result = result &* 31 &+ Int32(truncatingIfNeeded: javaHash(point))
    }
    return Int(result)
}

private func markerId(hashCodes: [Int]) -> String {
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
