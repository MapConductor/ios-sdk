import Foundation
import MapConductorCore
import UIKit

/// The polygons the Boston page draws. Same data and file format as the React
/// sample (`examples/basic/src/pages/polygon/boston/bostonData.ts`) and the
/// Android one (`BostonData.kt`).
///
/// - ``BostonDataset/downtown``: Overture building footprints of downtown in three
///   nested areas (`boston-downtown.bin`).
/// - ``BostonDataset/buildings`` / ``BostonDataset/parcels``: the whole city, about
///   100,000 polygons each (`boston-city-buildings.bin`, `boston-city-parcels.bin`):
///   Overture buildings, and Analyze Boston Parcels 2025 joined with the FY2026
///   Property Assessment land use.
///
/// All three are bundled (Resources). The React sample's `examples/basic/tools/boston/`
/// builds them from the official sources (see its README).
///
/// The files carry no ids: this is a polygon demo, and a polygon's id on the map
/// is its index in the file.
///
/// Binary layout, MCPG v2:
///   'MCPG' u32 version=2 u32 count u8 fields u8 digits   (little-endian)
///     fields: 1 = height, 2 = land use, 4 = area, 8 = name (what the file carries)
///     digits: coordinates are integers of 10^-digits degree (buildings 6, parcels 5)
///   per polygon, only the fields present, in this order:
///     height    varint, 0 = unknown, else the height in 0.1 m plus 1
///     land use  u8, the index in ``LandUse`` (family … unknown)
///     area      u8, the smallest downtown area (0, 1 or 2) the building fits in
///     name      varint byte length (0 = none), UTF-8
///     varint ringCount, per ring: varint n, n x (svarint dLat, svarint dLng)
///   varint is LEB128 (7 bits at a time, low first); svarint is a zigzag varint.
///   Coordinates are integers of 10^-digits degree, each the difference from the
///   previous vertex across the whole file. A ring's closing vertex (the same as its first)
///   is not stored: n counts the others, and the reader closes the ring again.
enum BostonDataset: String, CaseIterable, Identifiable {
    case downtown
    case buildings
    case parcels

    var id: String { rawValue }

    var label: String {
        switch self {
        case .downtown: return "Downtown"
        case .buildings: return "City buildings"
        case .parcels: return "City parcels"
        }
    }

    /// The file's name in the app bundle, without the `.bin` extension.
    fileprivate var resource: String {
        switch self {
        case .downtown: return "boston-downtown"
        case .buildings: return "boston-city-buildings"
        case .parcels: return "boston-city-parcels"
        }
    }

    fileprivate var attribution: String {
        switch self {
        case .downtown, .buildings:
            return "© OpenStreetMap contributors, Esri Community Maps contributors, USGS, Microsoft — via Overture Maps Foundation (ODbL 1.0)"
        case .parcels:
            return "City of Boston, Parcels 2025 and FY2026 Property Assessment (Analyze Boston) (ODC PDDL)"
        }
    }
}

/// A parcel's land use, from the City of Boston's Property Assessment.
/// The order is the file's: a land use is stored as its index here.
enum LandUse: String, CaseIterable {
    case family, apartment, condo, mixed, commercial, industrial, exempt, vacant, unknown

    /// How it is drawn; the same colours as the React sample's LAND_USE_STYLES.
    var fill: UIColor {
        switch self {
        case .family: return UIColor(red: 250 / 255, green: 204 / 255, blue: 21 / 255, alpha: 0.55)
        case .apartment: return UIColor(red: 249 / 255, green: 115 / 255, blue: 22 / 255, alpha: 0.55)
        case .condo: return UIColor(red: 236 / 255, green: 72 / 255, blue: 153 / 255, alpha: 0.5)
        case .mixed: return UIColor(red: 168 / 255, green: 85 / 255, blue: 247 / 255, alpha: 0.5)
        case .commercial: return UIColor(red: 239 / 255, green: 68 / 255, blue: 68 / 255, alpha: 0.55)
        case .industrial: return UIColor(red: 100 / 255, green: 116 / 255, blue: 139 / 255, alpha: 0.6)
        case .exempt: return UIColor(red: 59 / 255, green: 130 / 255, blue: 246 / 255, alpha: 0.5)
        case .vacant: return UIColor(red: 34 / 255, green: 197 / 255, blue: 94 / 255, alpha: 0.45)
        case .unknown: return UIColor(red: 148 / 255, green: 163 / 255, blue: 184 / 255, alpha: 0.35)
        }
    }

    var label: String {
        switch self {
        case .family: return "1–3 family"
        case .apartment: return "Apartments"
        case .condo: return "Condominium"
        case .mixed: return "Residential + commercial"
        case .commercial: return "Commercial"
        case .industrial: return "Industrial"
        case .exempt: return "Exempt (public, institutions)"
        case .vacant: return "Vacant land"
        case .unknown: return "No assessment (roads, islands)"
        }
    }
}

struct BostonBuilding {
    let id: String
    /// The smallest downtown area (0, 1 or 2) the building fits in; 0 for the city-wide sets.
    let level: Int
    let height: Double?
    let name: String?
    let use: LandUse?
    /// Rings as flat [lng, lat, lng, lat, ...]; the first is the outline, the rest holes.
    let rings: [[Double]]

    var vertexCount: Int { rings.reduce(0) { $0 + $1.count / 2 } }

    /// The area in square metres: the outline less its holes.
    var areaSquareMetres: Double {
        let areas = rings.map { ring in
            Spherical.computeArea(stride(from: 0, to: ring.count, by: 2).map {
                GeoPoint(latitude: ring[$0 + 1], longitude: ring[$0]) as GeoPointProtocol
            })
        }
        return (areas.first ?? 0) - areas.dropFirst().reduce(0, +)
    }
}

struct BostonDoc {
    let attribution: String
    let buildings: [BostonBuilding]
}

/// Where loading has got to, for the overlay.
enum BostonLoadPhase: Equatable {
    case read(loaded: Int, total: Int)
    case decode
    case build
    case draw
}

enum BostonDataLoader {
    struct Missing: LocalizedError {
        let path: String
        var errorDescription: String? { "Missing \(path) in the app bundle." }
    }

    /// Reads and decodes `dataset` off the main thread, reporting progress there.
    static func load(
        _ dataset: BostonDataset,
        onProgress: @escaping @MainActor (BostonLoadPhase) -> Void
    ) async throws -> BostonDoc {
        try await Task.detached(priority: .userInitiated) {
            guard let url = Bundle.main.url(forResource: dataset.resource, withExtension: "bin") else {
                throw Missing(path: "\(dataset.resource).bin")
            }
            let bytes = try readWithProgress(url, onProgress: onProgress)
            await onProgress(.decode)
            return BostonDoc(attribution: dataset.attribution, buildings: try decode(bytes, idPrefix: dataset.rawValue))
        }.value
    }

    private static func readWithProgress(
        _ url: URL,
        onProgress: @escaping @MainActor (BostonLoadPhase) -> Void
    ) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let total = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        var data = Data()
        data.reserveCapacity(total)
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            data.append(chunk)
            let loaded = data.count
            Task { @MainActor in onProgress(.read(loaded: loaded, total: total)) }
        }
        return data
    }

    /// Decodes an MCPG v2 file (see the top of this file); polygon `i` gets the id "<idPrefix>-<i>".
    static func decode(_ bytes: Data, idPrefix: String) throws -> [BostonBuilding] {
        try bytes.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> [BostonBuilding] in
            func u32(_ at: Int) -> Int { Int(raw.loadUnaligned(fromByteOffset: at, as: UInt32.self).littleEndian) }
            guard raw.count >= 14, String(decoding: raw[0..<4], as: UTF8.self) == "MCPG", u32(4) == 2 else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let count = u32(8)
            let fields = Int(raw[12])
            let scale = pow(10, Double(raw[13]))
            var offset = 14
            func varint() throws -> Int {
                var value = 0
                var shift = 0
                while true {
                    guard offset < raw.count else { throw CocoaError(.fileReadCorruptFile) }
                    let b = Int(raw[offset])
                    offset += 1
                    value |= (b & 0x7F) << shift
                    if b < 0x80 { return value }
                    shift += 7
                }
            }
            func svarint() throws -> Int {
                let v = try varint()
                return (v >> 1) ^ -(v & 1)
            }
            var buildings: [BostonBuilding] = []
            buildings.reserveCapacity(count)
            var lat = 0, lng = 0
            for i in 0..<count {
                var height: Double?
                var use: LandUse?
                var level = 0
                var name: String?
                if fields & 1 != 0 {
                    let h = try varint()
                    height = h == 0 ? nil : Double(h - 1) / 10
                }
                if fields & 2 != 0 {
                    use = LandUse.allCases[Int(raw[offset])]
                    offset += 1
                }
                if fields & 4 != 0 {
                    level = Int(raw[offset])
                    offset += 1
                }
                if fields & 8 != 0 {
                    let length = try varint()
                    if length > 0 { name = String(decoding: raw[offset..<(offset + length)], as: UTF8.self) }
                    offset += length
                }
                let ringCount = try varint()
                var rings: [[Double]] = []
                rings.reserveCapacity(ringCount)
                for _ in 0..<ringCount {
                    let n = try varint()
                    // The closing vertex is not stored; it is the first one again.
                    var ring = [Double](repeating: 0, count: (n + 1) * 2)
                    for v in 0..<n {
                        lat += try svarint()
                        lng += try svarint()
                        ring[v * 2] = Double(lng) / scale
                        ring[v * 2 + 1] = Double(lat) / scale
                    }
                    ring[n * 2] = ring[0]
                    ring[n * 2 + 1] = ring[1]
                    rings.append(ring)
                }
                buildings.append(BostonBuilding(
                    id: "\(idPrefix)-\(i)", level: level, height: height, name: name, use: use, rings: rings
                ))
            }
            return buildings
        }
    }
}
