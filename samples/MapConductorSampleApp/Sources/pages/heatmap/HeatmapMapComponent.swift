import GoogleMaps
import MapConductorCore
import MapConductorForGoogleMaps
import MapConductorForMapLibre
import MapConductorForMapKit
import MapConductorHeatmap
import SwiftUI
import UIKit

struct HeatmapMapComponent: View {
    @Binding var provider: MapProvider
    @ObservedObject var googleState: GoogleMapViewState
    @ObservedObject var mapLibreState: MapLibreViewState
    @ObservedObject var mapKitState: MapKitViewState

    let heatmap: HeatmapOverlayState
    let points: [HeatmapPointState]
    let onCameraMove: (MapProvider, MapCameraPosition) -> Void

    var body: some View {
        SampleMapView(
            provider: $provider,
            googleState: googleState,
            mapLibreState: mapLibreState,
            mapKitState: mapKitState,
            onCameraMove: nil,
            onCameraMoveEnd: { camera in
                onCameraMove(provider, camera)
            },
            sdkInitialize: {
                GMSServices.provideAPIKey(SampleConfig.googleMapsApiKey)
            }
        ) {
            HeatmapOverlay(state: heatmap) {
                ForEach(points, id: \.id) { pointState in
                    HeatmapPointView(state: pointState)
                }
            }
        }
    }
}
