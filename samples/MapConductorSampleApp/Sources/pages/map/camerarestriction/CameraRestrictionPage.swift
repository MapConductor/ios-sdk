import GoogleMaps
import MapConductorCore
import MapConductorForArcGIS
import MapConductorForGoogleMaps
import MapConductorForHERE
import MapConductorForLongdo
import MapConductorForMapKit
import MapConductorForMapLibre
import MapConductorForMapTiler
import MapConductorForMapbox
import MapConductorForTomTom
import SwiftUI

/// Exercises `CameraRestriction` against a live map — the iOS counterpart of the
/// example-app's camera-restriction page.
///
/// The allowed rectangle is drawn as a polygon so the limit is visible, and the
/// buttons ask the camera to go somewhere it is not allowed:
///
/// - **Move outside** : pans far north-east of the rectangle.
/// - **Zoom over max** / **Zoom under min** : asks for a zoom outside the range.
///
/// Providers with a native restriction API (Google, Mapbox) refuse the move
/// outright; the clamp-based ones (HERE, ArcGIS, TomTom, MapKit, Longdo, and the
/// pan axis of MapLibre/MapTiler) let it happen and pull the camera back when the
/// gesture settles. Either way the readout must end up inside the limits.
///
/// The camera is published through the `cameraReadout` accessibility identifier so
/// a device run can assert the clamp actually happened.
struct CameraRestrictionPage: View {
    let onToggleSidebar: () -> Void

    init(onToggleSidebar: @escaping () -> Void = {}) {
        self.onToggleSidebar = onToggleSidebar
    }

    // MARK: - Limits

    /// 許可する矩形（東京駅周辺）。
    private static let south = 35.63
    private static let west = 139.70
    private static let north = 35.75
    private static let east = 139.85

    private static let minZoom = 12.0
    private static let maxZoom = 16.0

    private static let allowedBounds = GeoRectBounds(
        southWest: GeoPoint(latitude: south, longitude: west),
        northEast: GeoPoint(latitude: north, longitude: east)
    )

    static let restriction = CameraRestriction(
        bounds: allowedBounds,
        minZoom: minZoom,
        maxZoom: maxZoom
    )

    private static let startPosition = GeoPoint(latitude: 35.681236, longitude: 139.767125)
    private static let start = MapCameraPosition(position: startPosition, zoom: 14)

    /// 制限矩形を可視化するポリゴン。
    private static let boundsPolygon = PolygonState(
        points: [
            GeoPoint(latitude: south, longitude: west),
            GeoPoint(latitude: south, longitude: east),
            GeoPoint(latitude: north, longitude: east),
            GeoPoint(latitude: north, longitude: west),
        ],
        id: "camera-restriction-bounds",
        strokeColor: .systemRed,
        strokeWidth: 3.0,
        fillColor: UIColor.systemRed.withAlphaComponent(0.10),
        geodesic: false
    )

    // MARK: - State

    /// UI テストが起動時に制限 ON で開始できるようにする（トグルを座標タップするより確実）。
    private static func initialEnabled() -> Bool {
        ProcessInfo.processInfo.environment["MAPCONDUCTOR_SAMPLE_CAMERA_RESTRICTION"] != "off"
    }

    @State private var provider: MapProvider = MapProvider.initial()
    @State private var enabled = CameraRestrictionPage.initialEnabled()
    @State private var cameraText = "?"

    @StateObject private var googleState = GoogleMapViewState(cameraPosition: start)
    @StateObject private var mapLibreState = MapLibreViewState(
        mapDesignType: MapLibreDesign.DemoTiles, cameraPosition: start)
    @StateObject private var mapKitState = MapKitViewState(
        mapDesignType: MapKitMapDesign.Standard, cameraPosition: start)
    @StateObject private var mapboxState = MapboxViewState(cameraPosition: start)
    @StateObject private var arcGISState = ArcGISMapViewState(
        mapDesignType: ArcGISDesign.OsmStandard, cameraPosition: start)
    @StateObject private var hereState = HereMapViewState(
        mapDesignType: HereMapDesign.NormalDay, cameraPosition: start)
    @StateObject private var tomTomState = TomTomMapViewState(
        mapDesignType: TomTomMapDesign.Standard, cameraPosition: start)
    @StateObject private var mapTilerState = MapTilerViewState(
        mapDesignType: MapTilerDesign.Streets, cameraPosition: start)
    @StateObject private var longdoState = LongdoViewState(
        mapDesignType: LongdoDesign.Normal, cameraPosition: start)

    var body: some View {
        DemoMapPageScaffold(provider: $provider, onToggleSidebar: onToggleSidebar) {
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
                cameraRestriction: enabled ? CameraRestrictionPage.restriction : nil,
                onCameraMove: { camera in updateReadout(camera) },
                onCameraMoveEnd: { camera in updateReadout(camera) }
            ) {
                Polygon(state: CameraRestrictionPage.boundsPolygon)
            }

            // 右上のプロバイダピッカーと重ならないよう下端に寄せる。
            VStack {
                Spacer()
                controlPanel
            }
        }
    }

    private var controlPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
                Toggle("restriction", isOn: $enabled)
                    .accessibilityIdentifier("restrictionToggle")
                    .font(.caption)
                    .frame(maxWidth: 260)

                HStack(spacing: 8) {
                    button("Move outside", "moveOutside") {
                        // 矩形の北東よりさらに外側へ。
                        moveCamera(
                            to: GeoPoint(latitude: 36.20, longitude: 140.40),
                            zoom: currentZoomOrDefault()
                        )
                    }
                    button("Zoom > max", "zoomOverMax") {
                        moveCamera(to: CameraRestrictionPage.startPosition, zoom: 20)
                    }
                    button("Zoom < min", "zoomUnderMin") {
                        moveCamera(to: CameraRestrictionPage.startPosition, zoom: 8)
                    }
                    button("Reset", "resetCamera") {
                        moveCamera(
                            to: CameraRestrictionPage.startPosition,
                            zoom: CameraRestrictionPage.start.zoom
                        )
                    }
                }

                Text(cameraText)
                    .font(.caption2)
                    .accessibilityIdentifier("cameraReadout")

                Text(limitsText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .background(.thinMaterial)
            .cornerRadius(12)
            .padding(10)
    }

    private var limitsText: String {
        String(
            format: "limits lat %.2f..%.2f lng %.2f..%.2f zoom %.0f..%.0f",
            CameraRestrictionPage.south,
            CameraRestrictionPage.north,
            CameraRestrictionPage.west,
            CameraRestrictionPage.east,
            CameraRestrictionPage.minZoom,
            CameraRestrictionPage.maxZoom
        )
    }

    private func button(
        _ title: String,
        _ identifier: String,
        _ action: @escaping () -> Void
    ) -> some View {
        Button(title, action: action)
            .accessibilityIdentifier(identifier)
            .font(.caption)
            .buttonStyle(.bordered)
    }

    private func updateReadout(_ camera: MapCameraPosition) {
        cameraText = String(
            format: "%.5f,%.5f,%.2f",
            camera.position.latitude,
            camera.position.longitude,
            camera.zoom
        )
    }

    private func currentZoomOrDefault() -> Double {
        currentCamera()?.zoom ?? CameraRestrictionPage.start.zoom
    }

    private func currentCamera() -> MapCameraPosition? {
        switch provider {
        case .googleMaps: return googleState.cameraPosition
        case .mapLibre: return mapLibreState.cameraPosition
        case .mapKit: return mapKitState.cameraPosition
        case .mapbox: return mapboxState.cameraPosition
        case .arcGIS, .arcGIS2D: return arcGISState.cameraPosition
        case .here: return hereState.cameraPosition
        case .tomTom: return tomTomState.cameraPosition
        case .mapTiler: return mapTilerState.cameraPosition
        case .longdo: return longdoState.cameraPosition
        }
    }

    /// 選択中のプロバイダのカメラを動かす。制限が効いていれば、ここで外へ出そうとしても
    /// ネイティブ API に拒否されるか、停止時にクランプで引き戻される。
    private func moveCamera(to position: GeoPoint, zoom: Double) {
        let target = MapCameraPosition(position: position, zoom: zoom)
        switch provider {
        case .googleMaps: googleState.moveCameraTo(cameraPosition: target)
        case .mapLibre: mapLibreState.moveCameraTo(cameraPosition: target)
        case .mapKit: mapKitState.moveCameraTo(cameraPosition: target)
        case .mapbox: mapboxState.moveCameraTo(cameraPosition: target)
        case .arcGIS, .arcGIS2D: arcGISState.moveCameraTo(cameraPosition: target)
        case .here: hereState.moveCameraTo(cameraPosition: target)
        case .tomTom: tomTomState.moveCameraTo(cameraPosition: target)
        case .mapTiler: mapTilerState.moveCameraTo(cameraPosition: target)
        case .longdo: longdoState.moveCameraTo(cameraPosition: target)
        }
    }
}
