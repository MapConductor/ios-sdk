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
import SwiftUI

struct StyledInfoBubblePage: View {
    let onToggleSidebar: () -> Void

    init(onToggleSidebar: @escaping () -> Void = {}) {
        self.onToggleSidebar = onToggleSidebar
    }

    @State private var provider: MapProvider = MapProvider.initial()

    @StateObject private var googleState = GoogleMapViewState(
        cameraPosition: MapCameraPosition(
            position: GeoPoint(latitude: 35.6812, longitude: 139.7671),
            zoom: 12
        )
    )

    @StateObject private var mapLibreState = MapLibreViewState(
        mapDesignType: MapLibreDesign.DemoTiles,
        cameraPosition: MapCameraPosition(
            position: GeoPoint(latitude: 35.6812, longitude: 139.7671),
            zoom: 12
        )
    )

    @StateObject private var mapKitState = MapKitViewState(
        mapDesignType: MapKitMapDesign.Standard,
        cameraPosition: MapCameraPosition(
            position: GeoPoint(latitude: 35.6812, longitude: 139.7671),
            zoom: 12
        )
    )

    @StateObject private var mapboxState = MapboxViewState(
        cameraPosition: MapCameraPosition(
            position: GeoPoint(latitude: 35.6812, longitude: 139.7671),
            zoom: 12
        )
    )
    
    @StateObject private var arcGISState = ArcGISMapViewState(
        mapDesignType: ArcGISDesign.OsmStandard,
        cameraPosition: MapCameraPosition(
            position: GeoPoint(latitude: 35.6812, longitude: 139.7671),
            zoom: 12
        )
    )
    
    @StateObject private var hereState = HereMapViewState(
        mapDesignType: HereMapDesign.NormalDay,
        cameraPosition: MapCameraPosition(
            position: GeoPoint(latitude: 35.6812, longitude: 139.7671),
            zoom: 12
        )
    )
    @StateObject private var tomTomState = TomTomMapViewState(
        mapDesignType: TomTomMapDesign.Standard,
        cameraPosition: MapCameraPosition(
            position: GeoPoint(latitude: 35.6812, longitude: 139.7671),
            zoom: 12
        )
    )
    @StateObject private var mapTilerState = MapTilerViewState(
        mapDesignType: MapTilerDesign.Streets,
        cameraPosition: MapCameraPosition(
            position: GeoPoint(latitude: 35.6812, longitude: 139.7671),
            zoom: 12
        )
    )
    
    @StateObject private var longdoState = LongdoViewState(
        mapDesignType: LongdoDesign.Normal,
        cameraPosition: MapCameraPosition(
            position: GeoPoint(latitude: 35.6812, longitude: 139.7671),
            zoom: 12
        )
    )

    @StateObject private var markerState = MarkerState(
        position: GeoPoint(latitude: 35.6812, longitude: 139.7671)
    )

    /// Second marker, used to demo `InfoBubbleCustom` — content drawn entirely by us,
    /// tail included. Mirrors the Android example's `InfoBubbleCustom` section.
    @StateObject private var customMarkerState = MarkerState(
        position: GeoPoint(latitude: 35.6812, longitude: 139.7971)
    )


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
                onMapClick: { point in markerState.position = point }
            ) {
                Marker(state: markerState)
                InfoBubble(
                    marker: markerState,
                    bubbleColor: Color.black.opacity(0.85),
                    borderColor: Color.white,
                    contentPadding: 10,
                    cornerRadius: 10,
                    tailSize: 10
                ) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Night Mode")
                            .font(.headline)
                            .foregroundColor(.white)
                        Text("Custom style bubble")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.8))
                    }
                }

                Marker(state: customMarkerState)
                // The tail is part of our own drawing, so tell the overlay engine that
                // the connection point sits at the content box's center-left.
                InfoBubbleCustom(
                    marker: customMarkerState,
                    tailOffset: CGPoint(x: 0, y: 0.5)
                ) {
                    RightTailInfoBubble(bubbleColor: .white, borderColor: .black) {
                        Text("Fully custom bubble")
                            .font(.subheadline)
                            .foregroundColor(.accentColor)
                    }
                }
            }
        }
    }
}

/// A bubble that sits to the right of its marker, with the tail on its own left edge.
/// Ported from the Android example's `RightTailInfoBubble` composable.
private struct RightTailInfoBubble<Content: View>: View {
    var bubbleColor: Color = .white
    var borderColor: Color = .black
    var contentPadding: CGFloat = 8
    var cornerRadius: CGFloat = 4
    var tailSize: CGFloat = 8
    @ViewBuilder var content: Content

    private var shape: RightTailBubbleShape {
        RightTailBubbleShape(tail: tailSize, corner: cornerRadius)
    }

    var body: some View {
        content
            .padding(contentPadding)
            .padding(.leading, tailSize)
            .background(shape.fill(bubbleColor))
            .overlay(shape.stroke(borderColor, lineWidth: 1))
    }
}

/// Rounded rect occupying `x ∈ [tail, width]`, plus a triangular tail pointing left
/// from the vertical center — so the tail tip lands at the box's `(0, 0.5)`.
private struct RightTailBubbleShape: Shape {
    let tail: CGFloat
    let corner: CGFloat

    func path(in rect: CGRect) -> Path {
        let left = rect.minX + tail
        let right = rect.maxX
        let top = rect.minY
        let bottom = rect.maxY
        let midY = rect.midY

        var path = Path()
        path.move(to: CGPoint(x: left + corner, y: top))
        path.addArc(
            tangent1End: CGPoint(x: right, y: top),
            tangent2End: CGPoint(x: right, y: bottom),
            radius: corner
        )
        path.addArc(
            tangent1End: CGPoint(x: right, y: bottom),
            tangent2End: CGPoint(x: left, y: bottom),
            radius: corner
        )
        path.addArc(
            tangent1End: CGPoint(x: left, y: bottom),
            tangent2End: CGPoint(x: left, y: top),
            radius: corner
        )
        path.addLine(to: CGPoint(x: left, y: midY + tail / 2))
        path.addLine(to: CGPoint(x: rect.minX, y: midY))
        path.addLine(to: CGPoint(x: left, y: midY - tail / 2))
        path.addArc(
            tangent1End: CGPoint(x: left, y: top),
            tangent2End: CGPoint(x: right, y: top),
            radius: corner
        )
        path.closeSubpath()
        return path
    }
}
