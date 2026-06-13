import Foundation

enum SampleConfig {
    static var googleMapsApiKey: String? {
        let key = "GOOGLE_MAPS_API_KEY"
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty else {
            return nil
        }
        return value
    }

    static var mapboxAccessToken: String? {
        let key = "MAPBOX_ACCESS_TOKEN"
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty else {
            return nil
        }
        return value
    }

    static var arcGISApiKey: String? {
        let key = "ARCGIS_API_KEY"
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty,
              !value.contains("$(") else {
            return nil
        }
        return value
    }
    static var hereAccessKeyId: String? {
        let key = "HERE_ACCESS_KEY_ID"
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty,
              !value.contains("$(") else {
            return nil
        }
        return value
    }
    static var hereAccessKeySecret: String? {
        let key = "HERE_ACCESS_KEY_SECRET"
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty,
              !value.contains("$(") else {
            return nil
        }
        return value
    }
}
