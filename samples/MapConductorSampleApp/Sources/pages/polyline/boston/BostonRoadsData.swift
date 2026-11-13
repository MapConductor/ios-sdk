import Foundation
import MapConductorCore
import UIKit

/// The roads the Boston roads page draws. Same data and file format as the React
/// sample (`examples/basic/src/pages/polyline/boston/`) and the Android one.
///
/// `boston-city-roads.bin` (bundled, Resources): Overture Maps `transportation/segment`
/// (release 2026-10-21.0), road subtype only, cut at the City of Boston boundary
/// (Analyze Boston): 54,645 polylines, 234,765 vertices. Built by the React sample's
/// `examples/basic/tools/boston/pack.py roads` (see its README).
///
/// MCPG v2 (see BostonData.swift) with fields = name (8) | road class (16) | lines (32),
/// coordinates at 1e-5 degree, vertices almost on a straight line (0.5 m) left out,
/// both ends kept. One record is one polyline; there are no ids: a road's id on the
/// map is its index in the file.
enum RoadClass: Int, CaseIterable, Identifiable {
    case highway, primary, secondary, tertiary, local, service, path

    var id: Int { rawValue }

    /// The same colours, widths and zIndex as the React and Android samples:
    /// the bigger the road, the wider, the warmer and the higher.
    var color: UIColor {
        switch self {
        case .highway: return UIColor(red: 0xE8 / 255, green: 0x59 / 255, blue: 0x0C / 255, alpha: 1)
        case .primary: return UIColor(red: 0xF0 / 255, green: 0x8C / 255, blue: 0x00 / 255, alpha: 1)
        case .secondary: return UIColor(red: 0xFA / 255, green: 0xB0 / 255, blue: 0x05 / 255, alpha: 1)
        case .tertiary: return UIColor(red: 0xFF / 255, green: 0xD4 / 255, blue: 0x3B / 255, alpha: 1)
        case .local: return UIColor(red: 0x86 / 255, green: 0x8E / 255, blue: 0x96 / 255, alpha: 1)
        case .service: return UIColor(red: 0xAD / 255, green: 0xB5 / 255, blue: 0xBD / 255, alpha: 1)
        case .path: return UIColor(red: 0x74 / 255, green: 0xB8 / 255, blue: 0x16 / 255, alpha: 1)
        }
    }

    /// On screen, in points.
    var width: Double {
        switch self {
        case .highway: return 5
        case .primary: return 4
        case .secondary: return 3.5
        case .tertiary: return 3
        case .local: return 2
        case .service: return 1.5
        case .path: return 1
        }
    }

    var zIndex: Int { 6 - rawValue }

    var label: String {
        switch self {
        case .highway: return "Highway"
        case .primary: return "Primary"
        case .secondary: return "Secondary"
        case .tertiary: return "Tertiary"
        case .local: return "Local"
        case .service: return "Service"
        case .path: return "Path"
        }
    }
}

struct BostonRoad {
    let id: String
    let road: RoadClass
    let name: String?
    /// The open polyline as flat [lng, lat, lng, lat, ...].
    let points: [Double]

    var vertexCount: Int { points.count / 2 }

    /// The length in metres: the geodesic distances between its points, summed.
    var lengthMetres: Double {
        var total = 0.0
        var i = 2
        while i < points.count {
            total += Spherical.computeDistanceBetween(
                from: GeoPoint(latitude: points[i - 1], longitude: points[i - 2]),
                to: GeoPoint(latitude: points[i + 1], longitude: points[i])
            )
            i += 2
        }
        return total
    }
}

enum BostonRoadsLoader {
    static let attribution = "© OpenStreetMap contributors, TomTom — via Overture Maps Foundation (ODbL 1.0); boundary: City of Boston (Analyze Boston)"

    /// Reads and decodes the bundled roads off the main thread, reporting progress there.
    static func load(onProgress: @escaping @MainActor (BostonLoadPhase) -> Void) async throws -> [BostonRoad] {
        try await Task.detached(priority: .userInitiated) {
            guard let url = Bundle.main.url(forResource: "boston-city-roads", withExtension: "bin") else {
                throw BostonDataLoader.Missing(path: "boston-city-roads.bin")
            }
            let bytes = try BostonDataLoader.readWithProgress(url, onProgress: onProgress)
            await onProgress(.decode)
            return try decode(bytes)
        }.value
    }

    /// Decodes an MCPG v2 file of polylines; road `i` gets the id "roads-<i>".
    static func decode(_ bytes: Data) throws -> [BostonRoad] {
        guard bytes.count >= 14, bytes[bytes.startIndex + 12] & 32 != 0 else { throw CocoaError(.fileReadCorruptFile) }
        return try BostonDataLoader.decode(bytes, idPrefix: "roads").map { record in
            guard record.rings.count == 1, record.rings[0].count >= 4 else { throw CocoaError(.fileReadCorruptFile) }
            return BostonRoad(id: record.id, road: record.road ?? .local, name: record.name, points: record.rings[0])
        }
    }
}
