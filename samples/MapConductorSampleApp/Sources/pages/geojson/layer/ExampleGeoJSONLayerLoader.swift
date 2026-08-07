import Foundation
import MapConductorGeoJSON
import UIKit
import ZIPFoundation

struct ExampleGeoJSONLayerData {
    let features: [GeoJSONFeature]
    let styleProvider: ExampleGeoJSONStyler
}

final class ExampleGeoJSONLayerLoader {
    private let bundle: Bundle

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    func load(assetName: String) throws -> ExampleGeoJSONLayerData {
        guard let url = bundle.url(forResource: assetName, withExtension: "zip") else {
            throw LoaderError.assetNotFound("\(assetName).zip")
        }
        let archive = try Archive(url: url, accessMode: .read, pathEncoding: nil)
        var features: [GeoJSONFeature]?
        var styleData: Data?

        for entry in archive where entry.type == .file {
            switch entry.path.split(separator: "/").last?.lowercased() {
            case Self.geoJSONEntry.lowercased():
                features = GeoJSONParser.parse(data: try extract(entry, from: archive))
            case Self.styleEntry.lowercased():
                styleData = try extract(entry, from: archive)
            default:
                continue
            }
        }

        guard let features else {
            throw LoaderError.entryNotFound(Self.geoJSONEntry, assetName)
        }
        guard let styleData else {
            throw LoaderError.entryNotFound(Self.styleEntry, assetName)
        }
        return ExampleGeoJSONLayerData(
            features: features,
            styleProvider: ExampleGeoJSONStyler(routeColors: try parseRouteColors(styleData))
        )
    }

    private func extract(_ entry: Entry, from archive: Archive) throws -> Data {
        var data = Data()
        _ = try archive.extract(entry) { data.append($0) }
        return data
    }

    private func parseRouteColors(_ data: Data) throws -> [ExampleGeoJSONStyler.RouteKey: UIColor] {
        guard let companies = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw LoaderError.invalidStyleJSON
        }
        var result: [ExampleGeoJSONStyler.RouteKey: UIColor] = [:]
        for item in companies {
            guard let company = item["company"] as? [String: Any],
                  let companyName = nonEmptyString(company["name"]),
                  let lines = company["lines"] as? [[String: Any]] else {
                continue
            }
            for line in lines {
                guard let lineName = nonEmptyString(line["name"]),
                      let colorString = nonEmptyString(line["color"]),
                      let color = UIColor(androidHex: colorString) else {
                    continue
                }
                result[.init(companyName: companyName, lineName: lineName)] = color
            }
        }
        return result
    }

    private func nonEmptyString(_ value: Any?) -> String? {
        guard let value = value as? String, !value.isEmpty else { return nil }
        return value
    }

    private enum LoaderError: LocalizedError {
        case assetNotFound(String)
        case entryNotFound(String, String)
        case invalidStyleJSON

        var errorDescription: String? {
            switch self {
            case .assetNotFound(let name):
                return "\(name) was not found in the app bundle"
            case .entryNotFound(let entry, let asset):
                return "\(entry) was not found in \(asset)"
            case .invalidStyleJSON:
                return "The GeoJSON style file does not contain a JSON array"
            }
        }
    }

    private static let geoJSONEntry = "N02-22_RailroadSection.geojson"
    private static let styleEntry = "N02-22_RailroadSection.style.json"
}

private extension UIColor {
    convenience init?(androidHex value: String) {
        let hex = value.hasPrefix("#") ? String(value.dropFirst()) : value
        guard hex.count == 6 || hex.count == 8,
              let parsed = UInt64(hex, radix: 16) else {
            return nil
        }
        let alpha: UInt64 = hex.count == 8 ? (parsed >> 24) & 0xff : 0xff
        let red = (parsed >> 16) & 0xff
        let green = (parsed >> 8) & 0xff
        let blue = parsed & 0xff
        self.init(
            red: CGFloat(red) / 255,
            green: CGFloat(green) / 255,
            blue: CGFloat(blue) / 255,
            alpha: CGFloat(alpha) / 255
        )
    }
}
