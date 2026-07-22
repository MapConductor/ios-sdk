import GoogleMaps
import MapConductorCore
import MapConductorForGoogleMaps
import MapConductorForMapLibre
import MapConductorForMapKit
import MapConductorForMapbox
import MapConductorForArcGIS
import MapConductorForHERE
import MapConductorForTomTom
import SwiftUI
import UIKit

struct CircleMapComponent: View {
    @Binding var provider: MapProvider
    @ObservedObject var googleState: GoogleMapViewState
    @ObservedObject var mapLibreState: MapLibreViewState
    @ObservedObject var mapKitState: MapKitViewState
    @ObservedObject var mapboxState: MapboxViewState
    @ObservedObject var arcGISState: ArcGISMapViewState
    @ObservedObject var hereState: HereMapViewState
    @ObservedObject var tomTomState: TomTomMapViewState
    @ObservedObject var viewModel: CirclePageViewModel

    @State private var labelPosition: CGPoint?

    var body: some View {
        ZStack {
            SampleMapView(
                provider: $provider,
                googleState: googleState,
                mapLibreState: mapLibreState,
                mapKitState: mapKitState,
                mapboxState: mapboxState,
                arcGISState: arcGISState,
                hereState: hereState,
                tomTomState: tomTomState,
                onCameraMove: { _ in calculateLabelPosition() }
            ) {
                { () -> MapViewContent in
                    var content = MapViewContent()
                    content.circles = [Circle(state: viewModel.circleState)]
                    content.polylines = [
                        Polyline(state: PolylineState(
                            points: [viewModel.circleCenter, GeoPoint.from(position: viewModel.edgeMarker.position)],
                            id: "circle-radius-line",
                            strokeColor: UIColor.white,
                            strokeWidth: 3.0,
                            geodesic: false
                        ))
                    ]
                    content.markers = [
                        Marker(state: viewModel.centerMarker),
                        Marker(state: viewModel.edgeMarker)
                    ]
                    return content
                }()
            }

            if let pos = labelPosition {
                radiusLabel(text: "\(Int(viewModel.circleState.radiusMeters)) m")
                    .position(x: pos.x, y: pos.y)
            }
        }
        .onChange(of: viewModel.labelUpdateTick) { _ in
            calculateLabelPosition()
        }
    }

    private func calculateLabelPosition() {
        let midPoint = Spherical.linearInterpolate(
            from: viewModel.centerMarker.position,
            to: viewModel.edgeMarker.position,
            fraction: 0.5
        )
        labelPosition = activeHolder()?.toScreenOffset(position: midPoint)
    }

    private func activeHolder() -> AnyMapViewHolder? {
        switch provider {
        case .googleMaps: return googleState.getMapViewHolder()
        case .mapLibre: return mapLibreState.getMapViewHolder()
        case .mapKit: return mapKitState.getMapViewHolder()
        case .mapbox: return mapboxState.getMapViewHolder()
        case .arcGIS: return arcGISState.getMapViewHolder()
        case .here: return hereState.getMapViewHolder()
        case .tomTom: return tomTomState.getMapViewHolder()
        }
    }
}

private func radiusLabel(text: String) -> some View {
    ZStack {
        Text(text)
            .font(.system(size: 16, weight: .bold))
            .foregroundColor(.white)
            .shadow(color: .white, radius: 5)
        Text(text)
            .font(.system(size: 16, weight: .medium))
            .foregroundColor(.black)
    }
}
