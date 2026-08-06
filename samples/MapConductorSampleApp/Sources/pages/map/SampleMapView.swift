import Foundation
import GoogleMaps
import MapConductorCore
import MapConductorForGoogleMaps
import MapConductorForMapLibre
import MapConductorForMapKit
import MapConductorForMapbox
import MapConductorForArcGIS
import MapConductorForHERE
import MapConductorForTomTom
import MapConductorForMapTiler
import MapConductorForLongdo
import LongdoMapFramework
import SwiftUI

enum MapProvider: String, CaseIterable, Identifiable {
    case googleMaps = "Google Map"
    case mapLibre = "MapLibre"
    case mapKit = "MapKit"
    case mapbox = "Mapbox"
    case arcGIS = "ArcGIS"
    case arcGIS2D = "ArcGIS 2D"
    case here = "Here"
    case tomTom = "TomTom"
    case mapTiler = "MapTiler"
    case longdo = "Longdo"

    var id: String { rawValue }

    static let allCases: [MapProvider] = [
        .googleMaps, .mapLibre, .mapKit, .mapbox, .arcGIS, .arcGIS2D, .here, .tomTom, .mapTiler, .longdo,
    ]
}

extension MapProvider {
    /// 名前文字列からプロバイダを解決する。`nil` は該当なし。
    static func parse(_ raw: String) -> MapProvider? {
        switch raw.lowercased() {
        case "maplibre", "map_libre": return .mapLibre
        case "googlemaps", "google_maps", "google": return .googleMaps
        case "mapkit", "map_kit": return .mapKit
        case "mapbox": return .mapbox
        case "arcgis2d", "arcgis_2d", "arcgis-2d": return .arcGIS2D
        case "arcgis", "arc_gis": return .arcGIS
        case "here": return .here
        case "tomtom", "tom_tom": return .tomTom
        case "maptiler", "map_tiler": return .mapTiler
        case "longdo": return .longdo
        default: return nil
        }
    }

    /// 起動時に選択しておくプロバイダ。UI テストが環境変数／起動引数で指定する。
    ///
    /// - Parameters:
    ///   - environmentKey: 参照する環境変数名。ペインが 2 つあるページ（Camera Sync Test）は
    ///     右ペイン用に別のキーを渡す。
    ///   - argumentName: 参照する起動引数名。
    ///   - fallback: どちらも指定されていないときの既定値。
    static func initial(
        environmentKey: String = "MAPCONDUCTOR_SAMPLE_PROVIDER",
        argumentName: String = "--provider",
        fallback: MapProvider = .googleMaps
    ) -> MapProvider {
        let env = ProcessInfo.processInfo.environment
        if let value = env[environmentKey], let provider = parse(value) {
            return provider
        }

        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: argumentName),
           index + 1 < args.count,
           let provider = parse(args[index + 1]) {
            return provider
        }

        return fallback
    }
}

struct SampleMapView: View {
    @Binding var provider: MapProvider
    @ObservedObject var googleState: GoogleMapViewState
    @ObservedObject var mapLibreState: MapLibreViewState
    @ObservedObject var mapKitState: MapKitViewState
    @ObservedObject var mapboxState: MapboxViewState
    @ObservedObject var arcGISState: ArcGISMapViewState
    @ObservedObject var hereState: HereMapViewState
    @ObservedObject var tomTomState: TomTomMapViewState
    @ObservedObject var mapTilerState: MapTilerViewState
    @ObservedObject var longdoState: LongdoViewState
    /// カメラの可動範囲制限。`nil` で無制限。選択中のプロバイダの MapView へそのまま渡す。
    var cameraRestriction: CameraRestriction? = nil
    var onMapClick: ((GeoPoint) -> Void)? = nil
    var onMapLongClick: ((GeoPoint) -> Void)? = nil
    var onCameraMoveStart: ((MapCameraPosition) -> Void)? = nil
    var onCameraMove: ((MapCameraPosition) -> Void)? = nil
    var onCameraMoveEnd: ((MapCameraPosition) -> Void)? = nil
    var sdkInitialize: (() -> Void)?
    let content: () -> MapViewContent

    static func initializeAllSDKs() {
        if let apiKey = SampleConfig.googleMapsApiKey {
            GMSServices.provideAPIKey(apiKey)
        }
        if let accessToken = SampleConfig.mapboxAccessToken {
            initializeMapbox(accessToken: accessToken)
        }
        if let apiKey = SampleConfig.arcGISApiKey {
            _ = arcGISApiKeyInitialize(apiKey: apiKey)
        }
        if let accessKey = SampleConfig.hereAccessKeyId,
           let accessSecret = SampleConfig.hereAccessKeySecret {
            do {
                try hereKeyInitialize(accessKeyId: accessKey, accessKeySecret: accessSecret)
            } catch {
                NSLog("[MapConductor] HERE authentication failed: %@", String(describing: error))
            }
        }
    }

    init(
        provider: Binding<MapProvider>,
        googleState: GoogleMapViewState,
        mapLibreState: MapLibreViewState,
        mapKitState: MapKitViewState,
        mapboxState: MapboxViewState,
        arcGISState: ArcGISMapViewState,
        hereState: HereMapViewState,
        tomTomState: TomTomMapViewState,
        mapTilerState: MapTilerViewState,
        longdoState: LongdoViewState,
        cameraRestriction: CameraRestriction? = nil,
        onMapClick: ((GeoPoint) -> Void)? = nil,
        onMapLongClick: ((GeoPoint) -> Void)? = nil,
        onCameraMoveStart: ((MapCameraPosition) -> Void)? = nil,
        onCameraMove: ((MapCameraPosition) -> Void)? = nil,
        onCameraMoveEnd: ((MapCameraPosition) -> Void)? = nil,
        sdkInitialize: (() -> Void)? = SampleMapView.initializeAllSDKs,
        @MapViewContentBuilder content: @escaping () -> MapViewContent
    ) {
        self._provider = provider
        self.googleState = googleState
        self.mapLibreState = mapLibreState
        self.mapKitState = mapKitState
        self.mapboxState = mapboxState
        self.arcGISState = arcGISState
        self.hereState = hereState
        self.tomTomState = tomTomState
        self.mapTilerState = mapTilerState
        self.longdoState = longdoState
        self.cameraRestriction = cameraRestriction
        self.onMapClick = onMapClick
        self.onMapLongClick = onMapLongClick
        self.onCameraMoveStart = onCameraMoveStart
        self.onCameraMove = onCameraMove
        self.onCameraMoveEnd = onCameraMoveEnd
        self.sdkInitialize = sdkInitialize
        self.content = content
    }

    var body: some View {
        switch provider {
        case .googleMaps:
            if let _ = SampleConfig.googleMapsApiKey {
                GoogleMapView(
                    state: googleState,
                    cameraRestriction: cameraRestriction,
                    onMapClick: onMapClick,
                    onMapLongClick: onMapLongClick,
                    onCameraMoveStart: onCameraMoveStart,
                    onCameraMove: onCameraMove,
                    onCameraMoveEnd: onCameraMoveEnd,
                    sdkInitialize: sdkInitialize,
                    content: content
                )
            } else {
                Text("Google Map is not available due to no API key")
            }
        case .mapLibre:
            MapLibreMapView(
                state: mapLibreState,
                cameraRestriction: cameraRestriction,
                onMapClick: onMapClick,
                onMapLongClick: onMapLongClick,
                onCameraMoveStart: onCameraMoveStart,
                onCameraMove: onCameraMove,
                onCameraMoveEnd: onCameraMoveEnd,
                sdkInitialize: sdkInitialize,
                content: content
            )

        case .mapKit:
            MapKitMapView(
                state: mapKitState,
                cameraRestriction: cameraRestriction,
                onMapClick: onMapClick,
                onMapLongClick: onMapLongClick,
                onCameraMoveStart: onCameraMoveStart,
                onCameraMove: onCameraMove,
                onCameraMoveEnd: onCameraMoveEnd,
                sdkInitialize: sdkInitialize,
                content: content
            )

        case .mapbox:
            if let _ = SampleConfig.mapboxAccessToken {
                MapboxMapView(
                    state: mapboxState,
                    cameraRestriction: cameraRestriction,
                    onMapClick: onMapClick,
                    onMapLongClick: onMapLongClick,
                    onCameraMoveStart: onCameraMoveStart,
                    onCameraMove: onCameraMove,
                    onCameraMoveEnd: onCameraMoveEnd,
                    sdkInitialize: sdkInitialize,
                    content: content
                )
            } else {
                Text("MapBox is not available due to no access token")
            }


        case .arcGIS:
            if let _ = SampleConfig.arcGISApiKey {
                ArcGISMapView(
                    state: arcGISState,
                    cameraRestriction: cameraRestriction,
                    onMapClick: onMapClick,
                    onMapLongClick: onMapLongClick,
                    onCameraMoveStart: onCameraMoveStart,
                    onCameraMove: onCameraMove,
                    onCameraMoveEnd: onCameraMoveEnd,
                    sdkInitialize: sdkInitialize,
                    content: content
                )
            } else {
                Text("ArcGIS is not available due to no api key")
            }
        
        
        case .arcGIS2D:
            if let _ = SampleConfig.arcGISApiKey {
                // 2D (MapView) と 3D (SceneView) は同じ ArcGISMapViewState を共有する。
                // プロバイダ切り替えでは同時に描画されないため、状態を分ける必要はない。
                ArcGISMapView2D(
                    state: arcGISState,
                    cameraRestriction: cameraRestriction,
                    onMapClick: onMapClick,
                    onMapLongClick: onMapLongClick,
                    onCameraMoveStart: onCameraMoveStart,
                    onCameraMove: onCameraMove,
                    onCameraMoveEnd: onCameraMoveEnd,
                    sdkInitialize: sdkInitialize,
                    content: content
                )
            } else {
                Text("ArcGIS is not available due to no api key")
            }

        case .here:
            if let _ = SampleConfig.hereAccessKeyId,
               let _ = SampleConfig.hereAccessKeySecret  {
                HereMapView(
                    state: hereState,
                    cameraRestriction: cameraRestriction,
                    onMapClick: onMapClick,
                    onMapLongClick: onMapLongClick,
                    onCameraMoveStart: onCameraMoveStart,
                    onCameraMove: onCameraMove,
                    onCameraMoveEnd: onCameraMoveEnd,
                    sdkInitialize: sdkInitialize,
                    content: content
                )
            } else {
                Text("Here is not available due to no api key")
            }

        case .tomTom:
            if let _ = SampleConfig.tomTomApiKey {
                TomTomMapView(
                    state: tomTomState,
                    apiKey: SampleConfig.tomTomApiKey,
                    cameraRestriction: cameraRestriction,
                    onMapClick: onMapClick,
                    onMapLongClick: onMapLongClick,
                    onCameraMoveStart: onCameraMoveStart,
                    onCameraMove: onCameraMove,
                    onCameraMoveEnd: onCameraMoveEnd,
                    sdkInitialize: sdkInitialize,
                    content: content
                )
            } else {
                Text("TomTom is not available due to no api key")
            }

        case .mapTiler:
            if let _ = SampleConfig.mapTilerApiKey {
                MapTilerMapView(
                    state: mapTilerState,
                    apiKey: SampleConfig.mapTilerApiKey,
                    cameraRestriction: cameraRestriction,
                    onMapClick: onMapClick,
                    onMapLongClick: onMapLongClick,
                    onCameraMoveStart: onCameraMoveStart,
                    onCameraMove: onCameraMove,
                    onCameraMoveEnd: onCameraMoveEnd,
                    sdkInitialize: sdkInitialize,
                    content: content
                )
            } else {
                Text("MapTiler is not available due to no api key")
            }

        case .longdo:
            if let _ = SampleConfig.longdoApiKey {
                LongdoMapView(
                    state: longdoState,
                    apiKey: SampleConfig.longdoApiKey,
                    cameraRestriction: cameraRestriction,
                    onMapClick: onMapClick,
                    onMapLongClick: onMapLongClick,
                    onCameraMoveStart: onCameraMoveStart,
                    onCameraMove: onCameraMove,
                    onCameraMoveEnd: onCameraMoveEnd,
                    sdkInitialize: {
                        if let map = longdoState.mapViewHolder?.map {
                            // 右上のレイヤー切り替えドロップダウンはサンプルアプリの
                            // provider メニューと重なるため非表示にする
                            _ = map.call(method: "Ui.LayerSelector.visible", args: [false])
                        }

                        sdkInitialize?()
                    },
                    content: content
                )
            } else {
                Text("Longdo is not available due to no api key")
            }

        }
    }
}
