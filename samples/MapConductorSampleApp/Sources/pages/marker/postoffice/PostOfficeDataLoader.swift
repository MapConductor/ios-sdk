import Foundation
import MapConductorCore
import ZIPFoundation

/// Loads post office data from P30-13_*.zip files bundled in the app.
/// Each zip contains a GeoJSON file with post office features.
struct PostOfficeDataLoader {

    func loadAllPostOffices() async -> [PostOffice] {
        await Task.detached(priority: .userInitiated) {
            let start = Date()
            var postOffices: [PostOffice] = []

            let zipUrls = Bundle.main.urls(forResourcesWithExtension: "zip", subdirectory: nil)?
                .filter { $0.lastPathComponent.hasPrefix("P30-13_") }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
                ?? []

            for url in zipUrls {
                do {
                    let loaded = try loadFromZip(url: url)
                    postOffices.append(contentsOf: loaded)
                } catch {
                    print("[PostOfficeDataLoader] Error loading \(url.lastPathComponent): \(error)")
                }
            }

            let elapsed = Date().timeIntervalSince(start)
            print("[PostOfficeDataLoader] Loaded \(postOffices.count) offices from \(zipUrls.count) zips in \(String(format: "%.2f", elapsed))s")
            return postOffices
        }.value
    }

    private func loadFromZip(url: URL) throws -> [PostOffice] {
        var postOffices: [PostOffice] = []
        guard let archive = Archive(url: url, accessMode: .read) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        for entry in archive where !entry.path.hasPrefix("__MACOSX") && entry.path.hasSuffix(".geojson") {
            var data = Data()
            _ = try archive.extract(entry) { chunk in data.append(chunk) }
            let parsed = parseGeoJSON(data: data)
            postOffices.append(contentsOf: parsed)
        }
        return postOffices
    }

    private func parseGeoJSON(data: Data) -> [PostOffice] {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let features = json["features"] as? [[String: Any]]
        else { return [] }

        var result: [PostOffice] = []
        for feature in features {
            guard
                let geometry = feature["geometry"] as? [String: Any],
                let coordinates = geometry["coordinates"] as? [Double],
                coordinates.count >= 2
            else { continue }

            let longitude = coordinates[0]
            let latitude = coordinates[1]
            let properties = feature["properties"] as? [String: Any]
            let name = properties?["name"] as? String ?? ""
            let address = properties?["address"] as? String ?? ""

            result.append(PostOffice(
                position: GeoPoint(latitude: latitude, longitude: longitude),
                name: name,
                address: address
            ))
        }
        return result
    }
}
