import MapConductorCore
import MapConductorForArcGIS
import SwiftUI

private let initCameraPosition = MapCameraPosition(
    position: GeoPoint(latitude: 35.68162987878426, longitude: 139.76703394012318),
    zoom: 14.0
)

struct ArcGISMapView2DPage: View {
    let onToggleSidebar: () -> Void

    init(onToggleSidebar: @escaping () -> Void = {}) {
        self.onToggleSidebar = onToggleSidebar
    }

    @StateObject private var state = ArcGISMapViewState(
        mapDesignType: ArcGISDesign.Streets,
        cameraPosition: initCameraPosition
    )

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ArcGISMapView2D(
                state: state,
                sdkInitialize: SampleMapView.initializeAllSDKs
            )
            .ignoresSafeArea()

            HStack(spacing: 12) {
                Button(action: onToggleSidebar) {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)

                Text("ArcGIS 2D")
                    .font(.headline)
            }
            .padding(12)
            .background(Color(UIColor.systemBackground).opacity(0.95))
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
            .padding(.top, 12)
            .padding(.trailing, 12)
        }
        .overlay(alignment: .bottomLeading) {
            Text("Flat 2D map — no tilt or elevation")
                .font(.caption)
                .padding(8)
                .background(Color(UIColor.systemBackground).opacity(0.85))
                .cornerRadius(8)
                .padding([.bottom, .leading], 16)
        }
    }
}
