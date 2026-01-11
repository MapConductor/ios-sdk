import CoreGraphics
import Foundation

public struct HexCoord: Sendable, Hashable, CustomStringConvertible {
    public let q: Int
    public let r: Int
    public let depth: Int

    public init(q: Int, r: Int, depth: Int = 0) {
        self.q = q
        self.r = r
        self.depth = depth
    }

    public var description: String { "H\(q)_\(r)_\(depth)" }

    public var s: Int { -q - r }

    public func neighbors() -> [HexCoord] {
        Direction6.allCases.map { HexCoord(q: q + $0.deltaQ, r: r + $0.deltaR, depth: depth) }
    }
}

public enum Direction6: CaseIterable, Sendable {
    case right
    case rightUp
    case leftUp
    case left
    case leftDown
    case rightDown

    fileprivate var deltaQ: Int {
        switch self {
        case .right: 1
        case .rightUp: 1
        case .leftUp: 0
        case .left: -1
        case .leftDown: -1
        case .rightDown: 0
        }
    }

    fileprivate var deltaR: Int {
        switch self {
        case .right: 0
        case .rightUp: -1
        case .leftUp: -1
        case .left: 0
        case .leftDown: 1
        case .rightDown: 1
        }
    }
}

public struct HexCell: Sendable, Hashable {
    public let coord: HexCoord
    public let centerLatLng: GeoPoint
    public let centerXY: CGPoint
    public let id: String

    public init(coord: HexCoord, centerLatLng: GeoPoint, centerXY: CGPoint, id: String) {
        self.coord = coord
        self.centerLatLng = centerLatLng
        self.centerXY = centerXY
        self.id = id
    }

    public func idPrefix(levels: Int) -> String {
        id.split(separator: "_").prefix(levels + 1).joined(separator: "_")
    }

    public static func == (lhs: HexCell, rhs: HexCell) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

public struct HexCellWithDistance: Sendable, Hashable {
    public let cell: HexCell
    public let distanceMeters: Double
}

public struct IdentifiedHexCell: Sendable, Hashable {
    public let id: String
    public let cell: HexCell
}

public protocol HexGeocellProtocol: Sendable {
    var projection: ProjectionProtocol { get }
    var baseHexSideLength: Int { get }

    func latLngToHexCoord(position: GeoPointProtocol, zoom: Double) -> HexCoord
    func latLngToHexCell(position: GeoPointProtocol, zoom: Double) -> HexCell
    func hexToLatLngCenter(coord: HexCoord, latHint: Double, zoom: Double) -> GeoPoint
    func hexToCellId(coord: HexCoord, zoom: Double) -> String
    func hexToPolygonLatLng(coord: HexCoord, latHint: Double, zoom: Double) -> [GeoPoint]
    func enclosingCell(of points: [MarkerState], zoom: Double) -> HexCell
    func hexCellsForPointsWithId(points: [MarkerState], zoom: Double) -> Set<IdentifiedHexCell>
    func hexDistance(a: HexCoord, b: HexCoord) -> Int
    func hexRange(center: HexCoord, radius: Int) -> [HexCoord]
}

/// Hexagonal geocell system for spatial indexing.
///
/// - Important: `baseHexSideLength` is the *edge length* in meters at zoom level 0.
public struct HexGeocell: HexGeocellProtocol {
    public let projection: ProjectionProtocol
    public let baseHexSideLength: Int

    public init(
        projection: ProjectionProtocol,
        baseHexSideLength: Int = 1_000
    ) {
        self.projection = projection
        self.baseHexSideLength = baseHexSideLength
    }

    public func latLngToHexCoord(position: GeoPointProtocol, zoom: Double) -> HexCoord {
        let hexSideLength = adjustedHexSideLength(lat: position.latitude, zoom: zoom)
        let offset = projection.project(position)
        return pixelToHex(offset: offset, hexSideLength: hexSideLength)
    }

    public func latLngToHexCell(position: GeoPointProtocol, zoom: Double) -> HexCell {
        let coord = latLngToHexCoord(position: position, zoom: zoom)
        let id = hexToCellId(coord: coord, zoom: zoom)
        let centerLatLng = hexToLatLngCenter(coord: coord, latHint: position.latitude, zoom: zoom)
        let centerXY = projection.project(centerLatLng)
        return HexCell(coord: coord, centerLatLng: centerLatLng, centerXY: centerXY, id: id)
    }

    public func hexToLatLngCenter(coord: HexCoord, latHint: Double, zoom: Double) -> GeoPoint {
        let hexSideLength = adjustedHexSideLength(lat: latHint, zoom: zoom)
        let center = hexCenterXY(coord: coord, hexSideLength: hexSideLength)
        return projection.unproject(center)
    }

    public func hexToCellId(coord: HexCoord, zoom: Double) -> String {
        "H\(coord.q)_\(coord.r)_Z\(Int(zoom))"
    }

    public func hexToPolygonLatLng(coord: HexCoord, latHint: Double, zoom: Double) -> [GeoPoint] {
        let hexSideLength = adjustedHexSideLength(lat: latHint, zoom: zoom)
        let center = hexCenterXY(coord: coord, hexSideLength: hexSideLength)

        let circumRadius = hexSideLength * 2.0 / sqrt(3.0)

        return (0..<6).map { i in
            let angle = (60.0 * Double(i) - 30.0) * .pi / 180.0
            let x = center.x + circumRadius * cos(angle)
            let y = center.y + circumRadius * sin(angle)
            return projection.unproject(CGPoint(x: x, y: y))
        }
    }

    public func enclosingCell(of points: [MarkerState], zoom: Double) -> HexCell {
        precondition(!points.isEmpty, "Points list cannot be empty")
        let center = computeGeographicCentroid(points.map { $0.position })
        let coord = latLngToHexCoord(position: center, zoom: zoom)
        let centerLatLng = hexToLatLngCenter(coord: coord, latHint: center.latitude, zoom: zoom)
        let centerXY = projection.project(centerLatLng)
        let id = hexToCellId(coord: coord, zoom: zoom)
        return HexCell(coord: coord, centerLatLng: centerLatLng, centerXY: centerXY, id: id)
    }

    public func hexCellsForPointsWithId(points: [MarkerState], zoom: Double) -> Set<IdentifiedHexCell> {
        Set(
            points.map { point in
                let coord = latLngToHexCoord(position: point.position, zoom: zoom)
                let centerLatLng = hexToLatLngCenter(coord: coord, latHint: point.position.latitude, zoom: zoom)
                let centerXY = projection.project(centerLatLng)
                let cellId = hexToCellId(coord: coord, zoom: zoom)
                let cell = HexCell(coord: coord, centerLatLng: centerLatLng, centerXY: centerXY, id: cellId)
                return IdentifiedHexCell(id: point.id, cell: cell)
            }
        )
    }

    public func hexDistance(a: HexCoord, b: HexCoord) -> Int {
        (abs(a.q - b.q) + abs(a.q + a.r - b.q - b.r) + abs(a.r - b.r)) / 2
    }

    public func hexRange(center: HexCoord, radius: Int) -> [HexCoord] {
        var results: [HexCoord] = []
        results.reserveCapacity((radius * 2 + 1) * (radius * 2 + 1))

        for dq in (-radius)...radius {
            let minR = max(-radius, -dq - radius)
            let maxR = min(radius, -dq + radius)
            for dr in minR...maxR {
                results.append(HexCoord(q: center.q + dq, r: center.r + dr, depth: center.depth))
            }
        }
        return results
    }

    private func computeGeographicCentroid(_ points: [GeoPointProtocol]) -> GeoPoint {
        if points.count == 1 { return GeoPoint.from(position: points[0]) }

        var x = 0.0
        var y = 0.0
        var z = 0.0

        for point in points {
            let latRad = point.latitude * .pi / 180.0
            let lngRad = point.longitude * .pi / 180.0
            x += cos(latRad) * cos(lngRad)
            y += cos(latRad) * sin(lngRad)
            z += sin(latRad)
        }

        let count = Double(points.count)
        x /= count
        y /= count
        z /= count

        let centralLng = atan2(y, x) * 180.0 / .pi
        let centralSquareRoot = sqrt(x * x + y * y)
        let centralLat = atan2(z, centralSquareRoot) * 180.0 / .pi

        return GeoPoint(latitude: centralLat, longitude: centralLng)
    }

    private func adjustedHexSideLength(lat: Double, zoom: Double) -> Double {
        let scale = 1.0 / pow(2.0, zoom)
        let latScale = max(cos(lat * .pi / 180.0), 0.01)
        return Double(baseHexSideLength) * scale / latScale
    }

    private func hexCenterXY(coord: HexCoord, hexSideLength: Double) -> CGPoint {
        let x = hexSideLength * (3.0 / 2.0 * Double(coord.q))
        let y = hexSideLength * (sqrt(3.0) * (Double(coord.r) + Double(coord.q) / 2.0))
        return CGPoint(x: x, y: y)
    }

    private func pixelToHex(offset: CGPoint, hexSideLength: Double) -> HexCoord {
        let q = (2.0 / 3.0 * offset.x / hexSideLength)
        let r = (-1.0 / 3.0 * offset.x + sqrt(3.0) / 3.0 * offset.y) / hexSideLength
        return cubeRound(q: q, r: r)
    }

    private func cubeRound(q: Double, r: Double) -> HexCoord {
        let s = -q - r

        var rq = Int(q.rounded())
        var rr = Int(r.rounded())
        var rs = Int(s.rounded())

        let qDiff = abs(Double(rq) - q)
        let rDiff = abs(Double(rr) - r)
        let sDiff = abs(Double(rs) - s)

        if qDiff > rDiff, qDiff > sDiff {
            rq = -rr - rs
        } else if rDiff > sDiff {
            rr = -rq - rs
        } else {
            rs = -rq - rr
        }

        return HexCoord(q: rq, r: rr)
    }

    public static func defaultGeocell() -> HexGeocellProtocol {
        HexGeocell(
            projection: WebMercatorProjection(),
            baseHexSideLength: 100_000
        )
    }
}

