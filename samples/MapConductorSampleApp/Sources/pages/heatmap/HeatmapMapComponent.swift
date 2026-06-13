import GoogleMaps
import MapConductorCore
import MapConductorForGoogleMaps
import MapConductorForMapLibre
import MapConductorForMapKit
import MapConductorForMapbox
import MapConductorForArcGIS
import MapConductorForHERE
import MapConductorHeatmap
import SwiftUI
import UIKit

struct HeatmapMapComponent: View {
    @Binding var provider: MapProvider
    @ObservedObject var googleState: GoogleMapViewState
    @ObservedObject var mapLibreState: MapLibreViewState
    @ObservedObject var mapKitState: MapKitViewState
    @ObservedObject var mapboxState: MapboxViewState
    @ObservedObject var arcGISState: ArcGISMapViewState
    @ObservedObject var hereState: HereMapViewState

    let heatmap: HeatmapOverlayState
    let points: [HeatmapPointState]
    let onCameraMove: (MapProvider, MapCameraPosition) -> Void

    var body: some View {
        SampleMapView(
            provider: $provider,
            googleState: googleState,
            mapLibreState: mapLibreState,
            mapKitState: mapKitState,
            mapboxState: mapboxState,
            arcGISState: arcGISState,
            hereState: hereState,
            onCameraMove: nil,
            onCameraMoveEnd: { camera in
                onCameraMove(provider, camera)
            }
        ) {
            HeatmapOverlay(state: heatmap) {
                HeatmapPoints(points)
            }
        }
    }
}
