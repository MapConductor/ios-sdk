import MapConductorCore
import MapConductorForLongdo
import MapConductorForArcGIS
import MapConductorForGoogleMaps
import MapConductorForHERE
import MapConductorForTomTom
import MapConductorForMapTiler
import MapConductorForMapKit
import MapConductorForMapLibre
import MapConductorForMapbox
import MapConductorGeoJSON
import SwiftUI
import UIKit

struct BasicGeoJSONMapPage: View {
    let onToggleSidebar: () -> Void

    @State private var provider: MapProvider
    @StateObject private var layerState: GeoJSONLayerState

    @StateObject private var googleState: GoogleMapViewState
    @StateObject private var mapLibreState: MapLibreViewState
    @StateObject private var mapKitState: MapKitViewState
    @StateObject private var mapboxState: MapboxViewState
    @StateObject private var arcGISState: ArcGISMapViewState
    @StateObject private var hereState: HereMapViewState
    @StateObject private var tomTomState: TomTomMapViewState
    @StateObject private var mapTilerState: MapTilerViewState
    @StateObject private var longdoState: LongdoViewState

    init(onToggleSidebar: @escaping () -> Void = {}) {
        self.onToggleSidebar = onToggleSidebar
        let cameraPosition = MapCameraPosition(
            position: GeoPoint.fromLongLat(longitude: 55.3089185, latitude: 25.255377),
            zoom: 13.0
        )
        let style = GeoJSONTileRenderer.LayerStyle(
            strokeColor: UIColor(red: 0x1d / 255.0, green: 0x70 / 255.0, blue: 0x82 / 255.0, alpha: 1.0),
            fillColor: UIColor(red: 0x3b / 255.0, green: 0xb2 / 255.0, blue: 0xd0 / 255.0, alpha: 1.0),
            strokeWidth: 2,
            pointRadius: 8
        )

        _provider = State(initialValue: .mapLibre)
        _layerState = StateObject(wrappedValue: GeoJSONLayerState(layerStyle: style))
        _googleState = StateObject(wrappedValue: GoogleMapViewState(cameraPosition: cameraPosition))
        _mapLibreState = StateObject(
            wrappedValue: MapLibreViewState(
                mapDesignType: MapLibreDesign.DemoTiles,
                cameraPosition: cameraPosition
            )
        )
        _mapKitState = StateObject(
            wrappedValue: MapKitViewState(
                mapDesignType: MapKitMapDesign.Standard,
                cameraPosition: cameraPosition
            )
        )
        _mapboxState = StateObject(wrappedValue: MapboxViewState(cameraPosition: cameraPosition))
        _arcGISState = StateObject(
            wrappedValue: ArcGISMapViewState(
                mapDesignType: ArcGISDesign.OsmStandard,
                cameraPosition: cameraPosition
            )
        )
        _hereState = StateObject(
            wrappedValue: HereMapViewState(
                mapDesignType: HereMapDesign.NormalDay,
                cameraPosition: cameraPosition
            )
        )
        _tomTomState = StateObject(
            wrappedValue: TomTomMapViewState(
                mapDesignType: TomTomMapDesign.Standard,
                cameraPosition: cameraPosition
            )
        )
        _mapTilerState = StateObject(
            wrappedValue: MapTilerViewState(
                mapDesignType: MapTilerDesign.Streets,
                cameraPosition: cameraPosition
            )
        )
        _longdoState = StateObject(
            wrappedValue: LongdoViewState(
                mapDesignType: LongdoDesign.Normal,
                cameraPosition: cameraPosition
            )
        )
    }

    var body: some View {
        DemoMapPageScaffold(provider: $provider, onToggleSidebar: onToggleSidebar) {
            ZStack(alignment: .bottomLeading) {
                SampleMapView(
                    provider: $provider,
                    googleState: googleState,
                    mapLibreState: mapLibreState,
                    mapKitState: mapKitState,
                    mapboxState: mapboxState,
                    arcGISState: arcGISState,
                    hereState: hereState,
                    tomTomState: tomTomState,
                    mapTilerState: mapTilerState,
                    longdoState: longdoState,
                ) {
                    GeoJSONLayer(state: layerState, features: basicGeoJSONFeatures)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("GeoJSON")
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text("Tile-rendered GeoJSON polygon layer.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(16)
                .background(Color(UIColor.systemBackground).opacity(0.95))
                .cornerRadius(12)
                .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
                .padding(.leading, 16)
                .padding(.bottom, 16)
            }
        }
    }
}

private let basicGeoJSONFeatures: [GeoJSONFeature] = {
    guard let data = basicGeoJSONString.data(using: .utf8) else { return [] }
    return GeoJSONParser.parse(data: data)
}()

private let basicGeoJSONString = """
{
  "type": "FeatureCollection",
  "features": [
    {
      "type": "Feature",
      "geometry": {
        "type": "Polygon",
        "coordinates": [
          [
            [55.30122473231012, 25.26476622289597],
            [55.29743486255916, 25.25827212207261],
            [55.28978863411328, 25.251356725509737],
            [55.300027931336984, 25.246425506635504],
            [55.307474692951274, 25.244200378933655],
            [55.31212891895635, 25.256408010450187],
            [55.30774064871093, 25.26266169122738],
            [55.301357710197806, 25.264946609615492],
            [55.30122473231012, 25.26476622289597]
          ],
          [
            [55.30084858315658, 25.256531695820797],
            [55.298280197635705, 25.252243254705405],
            [55.30163885563897, 25.250501032248863],
            [55.304059065092645, 25.254700192612702],
            [55.30084858315658, 25.256531695820797]
          ],
          [
            [55.30173763969924, 25.262517391695198],
            [55.301095543307355, 25.26122200491396],
            [55.30396028103232, 25.259479911263526],
            [55.30489872958182, 25.261132667394975],
            [55.30173763969924, 25.262517391695198]
          ]
        ]
      },
      "properties": {}
    }
  ]
}
"""
