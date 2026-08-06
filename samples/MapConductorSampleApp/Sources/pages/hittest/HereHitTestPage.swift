import MapConductorCore
import MapConductorForHERE
import SwiftUI
import heresdk

/// Instrumentation page used by `HereHitTestUITests` to measure the HERE marker
/// hit-test box on a real device.
///
/// A single default-icon marker sits at a fixed position with a fixed camera. The
/// page publishes, via accessibility labels:
///
/// - `hitTestAnchor`   the marker's anchor point in **window** coordinates (points)
/// - `hitTestResult`   `"<seq>:HIT"` / `"<seq>:MISS"`, bumped once per tap
/// - `hitTestScale`    the map view's `pixelScale`
///
/// A tap that lands inside the hit box reaches the marker's `onClick`; anything else
/// falls through to `onMapClick`. The sequence number lets the test wait for the
/// result of a specific tap rather than racing the previous one.
struct HereHitTestPage: View {
    static let markerPosition = GeoPoint(latitude: 35.681236, longitude: 139.767125)

    let onToggleSidebar: () -> Void

    @StateObject private var state = HereMapViewState(
        cameraPosition: MapCameraPosition(position: HereHitTestPage.markerPosition, zoom: 15.0)
    )

    @State private var seq: Int = 0
    @State private var result: String = "NONE"
    @State private var anchor: String = "?"
    @State private var scale: String = "?"
    @State private var mapFrame: CGRect = .zero

    private let refresh = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack(alignment: .top) {
            GeometryReader { geo in
                if SampleConfig.hereAccessKeyId != nil {
                    HereMapView(
                        state: state,
                        onMapClick: { _ in record("MISS") },
                        sdkInitialize: SampleMapView.initializeAllSDKs
                    ) {
                        Marker(state: MarkerState(
                            position: HereHitTestPage.markerPosition,
                            id: "hittest_target",
                            icon: DefaultMarkerIcon(),
                            onClick: { _ in record("HIT") }
                        ))
                    }
                    .onAppear { mapFrame = geo.frame(in: .global) }
                    .onChange(of: geo.frame(in: .global)) { _, newFrame in mapFrame = newFrame }
                } else {
                    Text("Here is not available due to no api key")
                }
            }

            // Keep the readouts out of the probe area; the test only taps near center.
            VStack(spacing: 0) {
                Text(anchor).accessibilityIdentifier("hitTestAnchor")
                Text(result).accessibilityIdentifier("hitTestResult")
                Text(scale).accessibilityIdentifier("hitTestScale")
            }
            .font(.caption2)
            .opacity(0.6)
        }
        .onReceive(refresh) { _ in updateAnchor() }
    }

    private func record(_ outcome: String) {
        seq += 1
        result = "\(seq):\(outcome)"
    }

    /// Projects the marker to the map view's local space and lifts it into window
    /// coordinates, which is the space `XCUICoordinate` taps are expressed in.
    private func updateAnchor() {
        guard let holder = state.getMapViewHolder(),
              let local = holder.toScreenOffset(position: HereHitTestPage.markerPosition)
        else {
            anchor = "?"
            return
        }
        anchor = String(
            format: "%.2f,%.2f",
            mapFrame.origin.x + local.x,
            mapFrame.origin.y + local.y
        )
        if let native = holder.mapView as? MapView {
            scale = String(format: "%.2f", native.pixelScale)
        }
    }
}
