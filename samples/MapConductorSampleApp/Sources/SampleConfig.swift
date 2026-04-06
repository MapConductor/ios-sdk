import Foundation

enum SampleConfig {
    static var googleMapsApiKey: String {
        let key = "GOOGLE_MAPS_API_KEY"
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty else {
            fatalError("Missing \(key). Set it in Config/Secrets.xcconfig.")
        }
        return value
    }

    static var mapboxAccessToken: String {
        let key = "MAPBOX_ACCESS_TOKEN"
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty else {
            fatalError("Missing \(key). Set it in Config/Secrets.xcconfig.")
        }
        return value
    }
}
