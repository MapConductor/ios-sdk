import GoogleMaps
import MapConductorCore
import MapConductorForGoogleMaps
import MapConductorForMapLibre
import MapConductorForMapKit
import MapConductorForMapbox
import SwiftUI
import UIKit

struct MarkerBasicMapComponent: View {
    @Binding var provider: MapProvider
    @ObservedObject var googleState: GoogleMapViewState
    @ObservedObject var mapLibreState: MapLibreViewState
    @ObservedObject var mapKitState: MapKitViewState
    @ObservedObject var mapboxState: MapboxViewState

    @State private var selectedSnippet: String?

    var body: some View {
        ZStack {
            SampleMapView(
                provider: $provider,
                googleState: googleState,
                mapLibreState: mapLibreState,
                mapKitState: mapKitState,
                mapboxState: mapboxState,
                onMapClick: { _ in selectedSnippet = nil },
                sdkInitialize: {
                    GMSServices.provideAPIKey(SampleConfig.googleMapsApiKey)
                initializeMapbox(accessToken: SampleConfig.mapboxAccessToken)
                }
            ) {
                { () -> MapViewContent in
                    var content = MapViewContent()
                    content.markers = buildMarkers()
                    return content
                }()
            }

            if let snippet = selectedSnippet {
                VStack {
                    Spacer()
                    Text(snippet)
                        .font(.system(size: 12, design: .monospaced))
                        .padding(12)
                        .background(Color(UIColor.systemBackground).opacity(0.95))
                        .cornerRadius(8)
                        .shadow(color: Color.black.opacity(0.2), radius: 6, x: 0, y: 3)
                        .padding(16)
                }
            }
        }
    }

    private func buildMarkers() -> [Marker] {
        var markers: [Marker] = []

        // Row 1: DefaultMarkerIcon scale variants
        markers.append(Marker(state: MarkerState(
            position: GeoPoint(latitude: 0.018, longitude: 0.004),
            id: "dm_07",
            extra: "DefaultMarkerIcon(scale: 0.7, label: \"0.7\", debug: true)",
            icon: DefaultMarkerIcon(scale: 0.7, label: "0.7", debug: true),
            onClick: onMarkerClick
        )))
        markers.append(Marker(state: MarkerState(
            position: GeoPoint(latitude: 0.018, longitude: 0.008),
            id: "dm_10",
            extra: "DefaultMarkerIcon(scale: 1.0, label: \"1.0\", debug: true)",
            icon: DefaultMarkerIcon(scale: 1.0, label: "1.0", debug: true),
            onClick: onMarkerClick
        )))
        markers.append(Marker(state: MarkerState(
            position: GeoPoint(latitude: 0.018, longitude: 0.012),
            id: "dm_14",
            extra: "DefaultMarkerIcon(scale: 1.4, label: \"1.4\", debug: true)",
            icon: DefaultMarkerIcon(scale: 1.4, label: "1.4", debug: true),
            onClick: onMarkerClick
        )))
        markers.append(Marker(state: MarkerState(
            position: GeoPoint(latitude: 0.018, longitude: 0.018),
            id: "dm_21",
            extra: "DefaultMarkerIcon(scale: 2.1, label: \"2.1\", debug: true)",
            icon: DefaultMarkerIcon(scale: 2.1, label: "2.1", debug: true),
            onClick: onMarkerClick
        )))

        // Row 2: DefaultMarkerIcon color variants
        markers.append(Marker(state: MarkerState(
            position: GeoPoint(latitude: 0.014, longitude: 0.004),
            id: "dm_default",
            extra: "DefaultMarkerIcon()",
            onClick: onMarkerClick
        )))
        markers.append(Marker(state: MarkerState(
            position: GeoPoint(latitude: 0.014, longitude: 0.008),
            id: "dm_yellow",
            extra: "DefaultMarkerIcon(\n  fillColor: .yellow,\n  strokeColor: .black,\n  strokeWidth: 2.0\n)",
            icon: DefaultMarkerIcon(fillColor: .systemYellow, strokeColor: .black, strokeWidth: 2.0),
            onClick: onMarkerClick
        )))
        markers.append(Marker(state: MarkerState(
            position: GeoPoint(latitude: 0.014, longitude: 0.012),
            id: "dm_green",
            extra: "DefaultMarkerIcon(\n  fillColor: #2EF527,\n  strokeColor: #FC225C,\n  label: \"AB\"\n)",
            icon: DefaultMarkerIcon(
                fillColor: UIColor(red: 0x2E/255, green: 0xF5/255, blue: 0x27/255, alpha: 1),
                strokeColor: UIColor(red: 0xFC/255, green: 0x22/255, blue: 0x5C/255, alpha: 1),
                label: "AB",
                labelTextColor: .white,
                labelStrokeColor: .black
            ),
            onClick: onMarkerClick
        )))

        // Row 3: ImageDefaultIcon (pin shape with image fill)
        if let image = loadPngImage(named: "wmo_00_clear") {
            markers.append(Marker(state: MarkerState(
                position: GeoPoint(latitude: 0.010, longitude: 0.004),
                id: "imd_wmo",
                extra: "ImageDefaultIcon(backgroundImage: wmo_00_clear)",
                icon: ImageDefaultIcon(backgroundImage: image),
                onClick: onMarkerClick
            )))
            markers.append(Marker(state: MarkerState(
                position: GeoPoint(latitude: 0.010, longitude: 0.008),
                id: "imd_wmo_stroke",
                extra: "ImageDefaultIcon(\n  backgroundImage: wmo_00_clear,\n  strokeColor: .black,\n  scale: 1.5\n)",
                icon: ImageDefaultIcon(backgroundImage: image, strokeColor: .black, scale: 1.5),
                onClick: onMarkerClick
            )))

            // Row 4: ImageIcon (raw image with custom anchor)
            markers.append(Marker(state: MarkerState(
                position: GeoPoint(latitude: 0.006, longitude: 0.004),
                id: "ii_anchor",
                extra: "ImageIcon(\n  image: wmo_00_clear,\n  anchor: CGPoint(x:0.5, y:1.0),\n  debug: true\n)",
                icon: ImageIcon(image: image, anchor: CGPoint(x: 0.5, y: 1.0), debug: true),
                onClick: onMarkerClick
            )))
            markers.append(Marker(state: MarkerState(
                position: GeoPoint(latitude: 0.006, longitude: 0.008),
                id: "ii_scale",
                extra: "ImageIcon(\n  image: wmo_00_clear,\n  scale: 0.5,\n  anchor: CGPoint(x:0.0, y:0.0)\n)",
                icon: ImageIcon(image: image, scale: 0.5, anchor: CGPoint(x: 0.0, y: 0.0), debug: true),
                onClick: onMarkerClick
            )))
        }

        return markers
    }

    private var onMarkerClick: OnMarkerEventHandler {
        { [self] state in
            selectedSnippet = state.extra as? String
        }
    }

    private func loadPngImage(named name: String) -> UIImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
              let data = try? Data(contentsOf: url),
              let image = UIImage(data: data) else {
            return nil
        }
        return image
    }
}
