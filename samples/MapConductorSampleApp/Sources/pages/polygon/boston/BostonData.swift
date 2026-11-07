import Foundation
import UIKit

/// The polygons the Boston page draws. Same data and file format as the React
/// sample (`examples/basic/src/pages/polygon/boston/bostonData.ts`) and the
/// Android one (`BostonData.kt`).
///
/// - ``BostonDataset/downtown``: the bundled Overture extract (JSON), three nested areas.
/// - ``BostonDataset/buildings`` / ``BostonDataset/parcels``: the whole city, about
///   100,000 polygons each. Those files are too large for the app bundle; copy them
///   into the app's Documents folder on the device:
///
///       xcrun devicectl device copy to --device <udid> \
///         --domain-type appDataContainer --domain-identifier com.mapconductor.sample \
///         --source boston-parcels.bin --destination Documents/boston/boston-parcels.bin
///
///   A parcel's label is "<GIS_ID>|<land use>".
///
/// Binary layout (little-endian):
///   'MCPG' u32 version=1 u32 count
///   per polygon: u8 labelLen, label (UTF-8), u16 height (0.1 m, 0xFFFF unknown),
///                u16 ringCount, per ring: u32 n, n x (i32 dLat, i32 dLng)
///   Coordinates are 1e-6 degree integers, each the difference from the
///   previous vertex across the whole file.
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

    fileprivate var file: String? {
        switch self {
        case .downtown: return nil
        case .buildings: return "boston/boston-buildings-city.bin"
        case .parcels: return "boston/boston-parcels.bin"
        }
    }

    fileprivate var attribution: String {
        switch self {
        case .downtown: return ""
        case .buildings:
            return "© OpenStreetMap contributors, Esri Community Maps contributors, USGS, Microsoft — via Overture Maps Foundation (ODbL 1.0)"
        case .parcels:
            return "City of Boston, Parcels 2025 and FY2026 Property Assessment (Analyze Boston) (ODC PDDL)"
        }
    }
}

/// A parcel's land use, from the City of Boston's Property Assessment.
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
        var errorDescription: String? {
            "Missing \(path). Copy it to the app's Documents folder with devicectl (see BostonData.swift)."
        }
    }

    /// Reads and decodes `dataset` off the main thread, reporting progress there.
    static func load(
        _ dataset: BostonDataset,
        onProgress: @escaping @MainActor (BostonLoadPhase) -> Void
    ) async throws -> BostonDoc {
        try await Task.detached(priority: .userInitiated) {
            let bytes: Data
            let url: URL
            if let file = dataset.file {
                let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                url = documents.appendingPathComponent(file)
                guard FileManager.default.fileExists(atPath: url.path) else { throw Missing(path: "Documents/\(file)") }
            } else {
                guard let bundled = Bundle.main.url(forResource: "boston-buildings", withExtension: "json") else {
                    throw Missing(path: "boston-buildings.json (app bundle)")
                }
                url = bundled
            }
            bytes = try readWithProgress(url, onProgress: onProgress)
            await onProgress(.decode)
            if dataset == .downtown { return try decodeDowntown(bytes) }
            return BostonDoc(attribution: dataset.attribution, buildings: try decode(bytes, dataset: dataset))
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

    private static func decodeDowntown(_ bytes: Data) throws -> BostonDoc {
        struct Doc: Decodable {
            struct Item: Decodable {
                let id: String
                let l: Int
                let h: Double?
                let n: String?
                let rings: [[Double]]
            }
            let attribution: String
            let license: String
            let buildings: [Item]
        }
        let doc = try JSONDecoder().decode(Doc.self, from: bytes)
        return BostonDoc(
            attribution: "\(doc.attribution) (\(doc.license))",
            buildings: doc.buildings.map {
                BostonBuilding(id: $0.id, level: $0.l, height: $0.h, name: $0.n, use: nil, rings: $0.rings)
            }
        )
    }

    private static func decode(_ bytes: Data, dataset: BostonDataset) throws -> [BostonBuilding] {
        try bytes.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> [BostonBuilding] in
            func u8(_ at: Int) -> Int { Int(raw[at]) }
            func u16(_ at: Int) -> Int { Int(raw.loadUnaligned(fromByteOffset: at, as: UInt16.self).littleEndian) }
            func u32(_ at: Int) -> Int { Int(raw.loadUnaligned(fromByteOffset: at, as: UInt32.self).littleEndian) }
            func i32(_ at: Int) -> Int { Int(Int32(littleEndian: raw.loadUnaligned(fromByteOffset: at, as: Int32.self))) }
            guard raw.count >= 12, String(decoding: raw[0..<4], as: UTF8.self) == "MCPG", u32(4) == 1 else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let count = u32(8)
            var buildings: [BostonBuilding] = []
            buildings.reserveCapacity(count)
            var seen = Set<String>()
            seen.reserveCapacity(count)
            var offset = 12
            var lat = 0, lng = 0
            for i in 0..<count {
                let labelLength = u8(offset)
                let label = String(decoding: raw[(offset + 1)..<(offset + 1 + labelLength)], as: UTF8.self)
                offset += 1 + labelLength
                let height = u16(offset)
                let ringCount = u16(offset + 2)
                offset += 4
                var rings: [[Double]] = []
                rings.reserveCapacity(ringCount)
                for _ in 0..<ringCount {
                    let n = u32(offset)
                    offset += 4
                    var ring = [Double](repeating: 0, count: n * 2)
                    for v in 0..<n {
                        lat += i32(offset)
                        lng += i32(offset + 4)
                        offset += 8
                        ring[v * 2] = Double(lng) / 1e6
                        ring[v * 2 + 1] = Double(lat) / 1e6
                    }
                    rings.append(ring)
                }
                // A building's label is its Overture id; a parcel's is "<parcel id>|<land use>".
                // Parts of a multipolygon share the label, so a repeat gets the index appended.
                var key = label
                var use: LandUse?
                if dataset == .parcels {
                    let parts = label.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
                    key = parts.first.map(String.init) ?? ""
                    use = parts.count > 1 ? (LandUse(rawValue: String(parts[1])) ?? .unknown) : .unknown
                }
                var id = key.isEmpty ? "\(dataset.rawValue)-\(i)" : key
                if seen.contains(id) { id = "\(id)#\(i)" }
                seen.insert(id)
                buildings.append(BostonBuilding(
                    id: id,
                    level: 0,
                    height: height == 0xFFFF ? nil : Double(height) / 10,
                    name: dataset == .parcels && !key.isEmpty ? "Parcel \(key)" : nil,
                    use: use,
                    rings: rings
                ))
            }
            return buildings
        }
    }
}
