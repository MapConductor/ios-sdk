import GoogleMaps
import MapConductorCore
import MapConductorForGoogleMaps
import MapConductorForMapLibre
import SwiftUI

struct GroundImageMapComponent: View {
    @Binding var provider: MapProvider
    @ObservedObject var googleState: GoogleMapViewState
    @ObservedObject var mapLibreState: MapLibreViewState
    @ObservedObject var viewModel: GroundImagePageViewModel

    var body: some View {
        SampleMapView(
            provider: $provider,
            googleState: googleState,
            mapLibreState: mapLibreState,
            sdkInitialize: {
                GMSServices.provideAPIKey(SampleConfig.googleMapsApiKey)
            }
        ) {
            var content = MapViewContent()
            content.markers = viewModel.markers.map { Marker(state: $0) }
            content.groundImages = [GroundImage(state: viewModel.groundImageState)]
            return content
        }
    }
}
