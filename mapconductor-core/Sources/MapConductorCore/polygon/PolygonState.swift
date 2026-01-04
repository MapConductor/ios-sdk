import Combine
import UIKit

public struct PolygonFingerPrint: Equatable, Hashable {
    public let id: Int
    public let strokeColor: Int
    public let strokeWidth: Int
    public let fillColor: Int
    public let geodesic: Int
    public let zIndex: Int
    public let points: Int
    public let extra: Int
}

public struct PolygonEvent {
    public let state: PolygonState
    public let clicked: GeoPointProtocol

    public init(state: PolygonState, clicked: GeoPointProtocol) {
        self.state = state
        self.clicked = clicked
    }
}

public typealias OnPolygonEventHandler = (PolygonEvent) -> Void

public final class PolygonState: ObservableObject, Identifiable, Equatable, Hashable {
    public let id: String

    @Published public var strokeColor: UIColor
    @Published public var strokeWidth: Double
    @Published public var fillColor: UIColor
    @Published public var geodesic: Bool
    @Published public var zIndex: Int
    @Published public var points: [GeoPointProtocol]
    @Published public var extra: Any?
    @Published public var onClick: OnPolygonEventHandler?

    public init(
        points: [GeoPointProtocol],
        id: String? = nil,
        strokeColor: UIColor = .black,
        strokeWidth: Double = 2.0,
        fillColor: UIColor = .clear,
        geodesic: Bool = false,
        zIndex: Int = 0,
        extra: Any? = nil,
        onClick: OnPolygonEventHandler? = nil
    ) {
        let resolvedId = id ?? PolygonState.makePolygonId(
            points: points,
            strokeColor: strokeColor,
            strokeWidth: strokeWidth,
            fillColor: fillColor,
            geodesic: geodesic,
            extra: extra
        )
        self.id = resolvedId
        self.strokeColor = strokeColor
        self.strokeWidth = strokeWidth
        self.fillColor = fillColor
        self.geodesic = geodesic
        self.zIndex = zIndex
        self.points = points
        self.extra = extra
        self.onClick = onClick
    }

    public func copy(
        points: [GeoPointProtocol]? = nil,
        id: String? = nil,
        strokeColor: UIColor? = nil,
        strokeWidth: Double? = nil,
        fillColor: UIColor? = nil,
        geodesic: Bool? = nil,
        zIndex: Int? = nil,
        extra: Any? = nil,
        onClick: OnPolygonEventHandler? = nil
    ) -> PolygonState {
        PolygonState(
            points: points ?? self.points,
            id: id ?? self.id,
            strokeColor: strokeColor ?? self.strokeColor,
            strokeWidth: strokeWidth ?? self.strokeWidth,
            fillColor: fillColor ?? self.fillColor,
            geodesic: geodesic ?? self.geodesic,
            zIndex: zIndex ?? self.zIndex,
            extra: extra ?? self.extra,
            onClick: onClick ?? self.onClick
        )
    }

    public func fingerPrint() -> PolygonFingerPrint {
        PolygonFingerPrint(
            id: javaHash(id),
            strokeColor: javaHash(strokeColor),
            strokeWidth: javaHash(strokeWidth),
            fillColor: javaHash(fillColor),
            geodesic: javaHash(geodesic),
            zIndex: zIndex,
            points: listHashCode(points),
            extra: javaHash(extra)
        )
    }

    public func asFlow() -> AnyPublisher<PolygonFingerPrint, Never> {
        let combined = Publishers.CombineLatest4($strokeColor, $strokeWidth, $fillColor, $geodesic)
        let combined2 = Publishers.CombineLatest(combined, $zIndex)
        let combined3 = Publishers.CombineLatest(combined2, $points)
        return combined3
            .map { [id] combined, points in
                let strokeColor = combined.0.0
                let strokeWidth = combined.0.1
                let fillColor = combined.0.2
                let geodesic = combined.0.3
                let zIndex = combined.1
                return PolygonFingerPrint(
                    id: javaHash(id),
                    strokeColor: javaHash(strokeColor),
                    strokeWidth: javaHash(strokeWidth),
                    fillColor: javaHash(fillColor),
                    geodesic: javaHash(geodesic),
                    zIndex: zIndex,
                    points: listHashCode(points),
                    extra: 0
                )
            }
            .combineLatest($extra)
            .map { finger, extra in
                PolygonFingerPrint(
                    id: finger.id,
                    strokeColor: finger.strokeColor,
                    strokeWidth: finger.strokeWidth,
                    fillColor: finger.fillColor,
                    geodesic: finger.geodesic,
                    zIndex: finger.zIndex,
                    points: finger.points,
                    extra: javaHash(extra)
                )
            }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    public static func == (lhs: PolygonState, rhs: PolygonState) -> Bool {
        lhs.hashCode() == rhs.hashCode()
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(hashCode())
    }

    public func hashCode() -> Int {
        var result: Int32 = Int32(truncatingIfNeeded: javaHash(extra))
        result = result &* 31 &+ Int32(truncatingIfNeeded: javaHash(strokeColor))
        result = result &* 31 &+ Int32(truncatingIfNeeded: javaHash(strokeWidth))
        result = result &* 31 &+ Int32(truncatingIfNeeded: javaHash(fillColor))
        result = result &* 31 &+ Int32(truncatingIfNeeded: javaHash(geodesic))
        result = result &* 31 &+ Int32(truncatingIfNeeded: zIndex)
        result = result &* 31 &+ Int32(truncatingIfNeeded: listHashCode(points))
        return Int(result)
    }

    private static func makePolygonId(
        points: [GeoPointProtocol],
        strokeColor: UIColor,
        strokeWidth: Double,
        fillColor: UIColor,
        geodesic: Bool,
        extra: Any?
    ) -> String {
        let hashCodes = [
            listHashCode(points),
            javaHash(strokeColor),
            javaHash(strokeWidth),
            javaHash(fillColor),
            javaHash(geodesic),
            javaHash(extra)
        ]
        return polygonId(hashCodes: hashCodes)
    }
}

private func listHashCode(_ points: [GeoPointProtocol]) -> Int {
    var result: Int32 = 0
    for point in points {
        result = result &* 31 &+ Int32(truncatingIfNeeded: javaHash(point))
    }
    return Int(result)
}

private func polygonId(hashCodes: [Int]) -> String {
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
