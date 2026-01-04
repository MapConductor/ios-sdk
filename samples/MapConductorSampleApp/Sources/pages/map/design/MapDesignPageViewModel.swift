import Foundation
import MapConductorCore
import MapConductorForGoogleMaps
import MapConductorForMapLibre

struct MapDesignOption {
    let label: String
    let design: Any // Can be GoogleMapDesignType or MapLibreDesign
}

final class MapDesignPageViewModel: ObservableObject {
    let initCameraPosition: MapCameraPosition

    @Published var mapDesignOptions: [MapDesignOption] = []

    init() {
        self.initCameraPosition = MapCameraPosition(
            position: GeoPoint.fromLatLong(
                latitude: 21.382314,
                longitude: -157.933097
            ),
            zoom: 12.0,
            bearing: 0.0,
            tilt: 0.0,
            paddings: nil
        )
    }

    func onMapViewChanged(provider: MapProvider) {
        switch provider {
        case .googleMaps:
            mapDesignOptions = googleMapDesigns
        case .mapLibre:
            mapDesignOptions = mapLibreDesigns
        }
    }

    private let googleMapDesigns = [
        MapDesignOption(label: "Normal", design: GoogleMapDesign.Normal),
        MapDesignOption(label: "Satellite", design: GoogleMapDesign.Satellite),
        MapDesignOption(label: "Hybrid", design: GoogleMapDesign.Hybrid),
        MapDesignOption(label: "Terrain", design: GoogleMapDesign.Terrain),
        MapDesignOption(label: "None", design: GoogleMapDesign.None),
    ]

    private let mapLibreDesigns = [
        MapDesignOption(label: "DemoTiles", design: MapLibreDesign.DemoTiles),
        MapDesignOption(label: "MapTilerBasicEn", design: MapLibreDesign.MapTilerBasicEn),
        MapDesignOption(label: "MapTilerBasicJa", design: MapLibreDesign.MapTilerBasicJa),
        MapDesignOption(label: "MapTilerTonerEn", design: MapLibreDesign.MapTilerTonerEn),
        MapDesignOption(label: "MapTilerTonerJa", design: MapLibreDesign.MapTilerTonerJa),
        MapDesignOption(label: "OsmBright", design: MapLibreDesign.OsmBright),
        MapDesignOption(label: "OsmBrightEn", design: MapLibreDesign.OsmBrightEn),
        MapDesignOption(label: "OsmBrightJa", design: MapLibreDesign.OsmBrightJa),
        MapDesignOption(label: "OpenMapTiles", design: MapLibreDesign.OpenMapTiles),
    ]
}
