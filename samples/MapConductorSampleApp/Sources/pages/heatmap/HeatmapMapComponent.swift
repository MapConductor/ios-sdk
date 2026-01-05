import GoogleMaps
import MapConductorCore
import MapConductorForGoogleMaps
import MapConductorForMapLibre
import MapConductorHeatmap
import SwiftUI
import UIKit

struct HeatmapMapComponent: View {
    @Binding var provider: MapProvider
    @ObservedObject var googleState: GoogleMapViewState
    @ObservedObject var mapLibreState: MapLibreViewState

    let heatmap: HeatmapOverlay
    let points: [HeatmapPoint]
    let onCameraMove: (MapCameraPosition) -> Void

    var body: some View {
        SampleMapView(
            provider: $provider,
            googleState: googleState,
            mapLibreState: mapLibreState,
            onCameraMove: nil,
            onCameraMoveEnd: onCameraMove,
            sdkInitialize: {
                GMSServices.provideAPIKey(SampleConfig.googleMapsApiKey)
            }
        ) {
            HeatmapLayer(overlay: heatmap, points: points)
        }
    }
}
