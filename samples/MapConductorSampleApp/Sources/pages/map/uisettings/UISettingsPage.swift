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

/// Exercises `MapUISettings` against a live map — the iOS counterpart of the
/// example-app's "UI Settings" page.
///
/// Four toggles flip the gesture flags. The camera is published as an
/// accessibility label so a device run can tell whether a swipe actually moved the
/// map, which is the only way to check providers whose gesture state cannot be
/// read back (Longdo, MapTiler).
struct UISettingsPage: View {
    let onToggleSidebar: () -> Void

    init(onToggleSidebar: @escaping () -> Void = {}) {
        self.onToggleSidebar = onToggleSidebar
    }

    @State private var provider: MapProvider = MapProvider.initial()
    @State private var settings = UISettingsPage.initialSettings()

    /// Lets a UI test preset the flags instead of driving the toggles, which is
    /// far more reliable than tapping a SwiftUI Toggle by coordinate.
    private static func initialSettings() -> MapUISettings {
        ProcessInfo.processInfo.environment["MAPCONDUCTOR_SAMPLE_UI_GESTURES"] == "none"
            ? .None
            : .Default
    }
    @State private var cameraText = "?"

    private static let start = MapCameraPosition(
        position: GeoPoint(latitude: 35.681236, longitude: 139.767125),
        zoom: 14,
        bearing: 20,
        tilt: 30
    )

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
                onCameraMove: { camera in
                    cameraText = String(
                        format: "%.5f,%.5f,%.2f,%.1f,%.1f",
                        camera.position.latitude,
                        camera.position.longitude,
                        camera.zoom,
                        camera.bearing,
                        camera.tilt
                    )
                }
            ) {}

            VStack(alignment: .leading, spacing: 2) {
                toggle("scrollGesture", \.scrollGesture)
                toggle("zoomGesture", \.zoomGesture)
                toggle("rotateGesture", \.rotateGesture)
                toggle("tiltGesture", \.tiltGesture)
                Text(cameraText)
                    .font(.caption2)
                    .accessibilityIdentifier("cameraReadout")
            }
            .padding(10)
            .background(.thinMaterial)
            .padding(10)
        }
        .onChange(of: settings) { _, new in apply(new) }
        .onAppear { apply(settings) }
    }

    private func toggle(
        _ label: String,
        _ key: WritableKeyPath<MapUISettings, Bool>
    ) -> some View {
        Toggle(label, isOn: Binding(
            get: { settings[keyPath: key] },
            set: { settings[keyPath: key] = $0 }
        ))
        .accessibilityIdentifier(label)
        .font(.caption)
        .frame(maxWidth: 260)
    }

    /// Every provider state carries its own `uiSettings`, so push to all of them —
    /// switching provider then keeps the current flags.
    private func apply(_ new: MapUISettings) {
        googleState.uiSettings = new
        mapLibreState.uiSettings = new
        mapKitState.uiSettings = new
        mapboxState.uiSettings = new
        arcGISState.uiSettings = new
        hereState.uiSettings = new
        tomTomState.uiSettings = new
        mapTilerState.uiSettings = new
        longdoState.uiSettings = new
    }
}
