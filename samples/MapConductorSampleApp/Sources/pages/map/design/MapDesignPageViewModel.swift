import Foundation
import MapConductorCore
import MapConductorForGoogleMaps
import MapConductorForMapLibre
import MapConductorForMapKit
import MapConductorForMapbox
import MapConductorForArcGIS
import MapConductorForHERE

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
        case .mapKit:
            mapDesignOptions = mapKitDesigns
        case .mapbox:
            mapDesignOptions = mapboxDesigns
        case .arcGIS:
            mapDesignOptions = arcGISDesigns
        case .here:
            mapDesignOptions = hereDesign
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

    private let mapKitDesigns = [
        MapDesignOption(label: "Standard", design: MapKitMapDesign.Standard),
        MapDesignOption(label: "Satellite", design: MapKitMapDesign.Satellite),
        MapDesignOption(label: "Hybrid", design: MapKitMapDesign.Hybrid),
        MapDesignOption(label: "Satellite Flyover", design: MapKitMapDesign.SatelliteFlyover),
        MapDesignOption(label: "Hybrid Flyover", design: MapKitMapDesign.HybridFlyover),
        MapDesignOption(label: "Muted Standard", design: MapKitMapDesign.MutedStandard),
    ]

    private let mapboxDesigns = [
        MapDesignOption(label: "Standard", design: MapboxMapDesign.Standard),
        MapDesignOption(label: "Standard Satellite", design: MapboxMapDesign.StandardSatellite),
        MapDesignOption(label: "Streets", design: MapboxMapDesign.Streets),
        MapDesignOption(label: "Outdoors", design: MapboxMapDesign.Outdoors),
        MapDesignOption(label: "Light", design: MapboxMapDesign.Light),
        MapDesignOption(label: "Dark", design: MapboxMapDesign.Dark),
        MapDesignOption(label: "Satellite", design: MapboxMapDesign.Satellite),
        MapDesignOption(label: "Satellite Streets", design: MapboxMapDesign.SatelliteStreets),
        MapDesignOption(label: "Navigation Day", design: MapboxMapDesign.NavigationDay),
        MapDesignOption(label: "Navigation Night", design: MapboxMapDesign.NavigationNight),
    ]
    
    private let arcGISDesigns = [
        MapDesignOption(label: "Streets", design: ArcGISDesign.Streets),
        MapDesignOption(label: "Imagery", design: ArcGISDesign.Imagery),
        MapDesignOption(label: "Topographic", design: ArcGISDesign.Topographic),
        MapDesignOption(label: "OpenStreetMap Standard", design: ArcGISDesign.OsmStandard),
    ]
    
    private let hereDesign = [
        MapDesignOption(label: "NormalDay", design: HereMapDesign.NormalDay),
        MapDesignOption(label: "NormalNight", design: HereMapDesign.NormalNight),
        MapDesignOption(label: "Satellite", design: HereMapDesign.Satellite),
        MapDesignOption(label: "HybridDay", design: HereMapDesign.HybridDay),
        MapDesignOption(label: "HybridNight", design: HereMapDesign.HybridNight),
        MapDesignOption(label: "LiteDay", design: HereMapDesign.LiteDay),
        MapDesignOption(label: "LiteHybridDay", design: HereMapDesign.LiteHybridDay),
        MapDesignOption(label: "LiteHybridNight", design: HereMapDesign.LiteHybridNight),
        MapDesignOption(label: "LogisticsDay", design: HereMapDesign.LogisticsDay),
        MapDesignOption(label: "LogisticsNight", design: HereMapDesign.LogisticsNight),
        MapDesignOption(label: "LogisticsHybridDay", design: HereMapDesign.LogisticsHybridDay),
        MapDesignOption(label: "LogisticsHybridNight", design: HereMapDesign.LogisticsHybridNight),
        MapDesignOption(label: "RoadNetworkDay", design: HereMapDesign.RoadNetworkDay),
        MapDesignOption(label: "RoadNetworkNight", design: HereMapDesign.RoadNetworkNight),
    ]
}
