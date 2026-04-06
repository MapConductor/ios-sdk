import GoogleMaps
import MapConductorCore
import MapConductorForGoogleMaps
import MapConductorForMapLibre
import MapConductorForMapKit
import MapConductorForMapbox
import SwiftUI
import UIKit

struct VisibleRegionMapComponent: View {
    @Binding var provider: MapProvider
    @ObservedObject var googleState: GoogleMapViewState
    @ObservedObject var mapLibreState: MapLibreViewState
    @ObservedObject var mapKitState: MapKitViewState
    @ObservedObject var mapboxState: MapboxViewState

    let onCameraChanged: ((MapCameraPosition) -> Void)?

    @State private var cameraPosition: MapCameraPosition?
    @State private var visibleRegionInfo: VisibleRegionInfo?
    @State private var isExpanded = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            SampleMapView(
                provider: $provider,
                googleState: googleState,
                mapLibreState: mapLibreState,
                mapKitState: mapKitState,
                mapboxState: mapboxState,
                onCameraMoveEnd: { pos in
                    cameraPosition = pos
                    onCameraChanged?(pos)
                    if let vr = pos.visibleRegion {
                        visibleRegionInfo = makeInfo(vr)
                    }
                },
                sdkInitialize: {
                    GMSServices.provideAPIKey(SampleConfig.googleMapsApiKey)
                initializeMapbox(accessToken: SampleConfig.mapboxAccessToken)
                }
            ) {
                { () -> MapViewContent in
                    var content = MapViewContent()
                    if let pos = cameraPosition, let vr = pos.visibleRegion {
                        let bounds = vr.bounds
                        if !bounds.isEmpty, let sw = bounds.southWest, let ne = bounds.northEast {
                            let centerLat = (sw.latitude + ne.latitude) / 2
                            let centerLng = (sw.longitude + ne.longitude) / 2
                            content.markers = [
                                Marker(state: MarkerState(
                                    position: GeoPoint(latitude: centerLat, longitude: centerLng),
                                    id: "vr_center",
                                    icon: DefaultMarkerIcon(fillColor: .red, label: "C")
                                )),
                                Marker(state: MarkerState(
                                    position: sw,
                                    id: "vr_sw",
                                    icon: DefaultMarkerIcon(fillColor: .black, label: "SW")
                                )),
                                Marker(state: MarkerState(
                                    position: ne,
                                    id: "vr_ne",
                                    icon: DefaultMarkerIcon(fillColor: .black, label: "NE")
                                ))
                            ]
                            if let p = vr.nearLeft {
                                content.markers.append(Marker(state: MarkerState(
                                    position: p, id: "vr_nl",
                                    icon: DefaultMarkerIcon(fillColor: .blue, label: "NL")
                                )))
                            }
                            if let p = vr.nearRight {
                                content.markers.append(Marker(state: MarkerState(
                                    position: p, id: "vr_nr",
                                    icon: DefaultMarkerIcon(fillColor: .green, label: "NR")
                                )))
                            }
                            if let p = vr.farLeft {
                                content.markers.append(Marker(state: MarkerState(
                                    position: p, id: "vr_fl",
                                    icon: DefaultMarkerIcon(fillColor: .systemYellow, label: "FL")
                                )))
                            }
                            if let p = vr.farRight {
                                content.markers.append(Marker(state: MarkerState(
                                    position: p, id: "vr_fr",
                                    icon: DefaultMarkerIcon(fillColor: .magenta, label: "FR")
                                )))
                            }
                        }
                    }
                    return content
                }()
            }

            VisibleRegionInfoPanel(
                cameraPosition: cameraPosition,
                visibleRegionInfo: visibleRegionInfo,
                isExpanded: $isExpanded
            )
            .padding(16)
            .frame(maxWidth: 350, alignment: .leading)
        }
    }

    private func makeInfo(_ vr: VisibleRegion) -> VisibleRegionInfo {
        let bounds = vr.bounds
        guard !bounds.isEmpty, let sw = bounds.southWest, let ne = bounds.northEast else {
            return VisibleRegionInfo(boundsString: "Empty", corners: [], centerPoint: "N/A", widthKm: 0, heightKm: 0)
        }
        let boundsString = String(format: "SW:(%.6f,%.6f) NE:(%.6f,%.6f)", sw.latitude, sw.longitude, ne.latitude, ne.longitude)
        var corners: [String] = []
        if let p = vr.nearLeft  { corners.append(String(format: "NL:(%.6f,%.6f)", p.latitude, p.longitude)) }
        if let p = vr.nearRight { corners.append(String(format: "NR:(%.6f,%.6f)", p.latitude, p.longitude)) }
        if let p = vr.farLeft   { corners.append(String(format: "FL:(%.6f,%.6f)", p.latitude, p.longitude)) }
        if let p = vr.farRight  { corners.append(String(format: "FR:(%.6f,%.6f)", p.latitude, p.longitude)) }
        let centerLat = (sw.latitude + ne.latitude) / 2
        let centerLng = (sw.longitude + ne.longitude) / 2
        let centerPoint = String(format: "Center:(%.6f,%.6f)", centerLat, centerLng)
        let widthM = Spherical.computeDistanceBetween(from: sw, to: GeoPoint(latitude: sw.latitude, longitude: ne.longitude))
        let heightM = Spherical.computeDistanceBetween(from: sw, to: GeoPoint(latitude: ne.latitude, longitude: sw.longitude))
        return VisibleRegionInfo(boundsString: boundsString, corners: corners, centerPoint: centerPoint, widthKm: widthM / 1000, heightKm: heightM / 1000)
    }
}

private struct VisibleRegionInfoPanel: View {
    let cameraPosition: MapCameraPosition?
    let visibleRegionInfo: VisibleRegionInfo?
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Visible Region")
                    .font(.headline)
                Spacer()
                Button(action: { withAnimation { isExpanded.toggle() } }) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                        .foregroundColor(.primary)
                }
                if let camera = cameraPosition, let info = visibleRegionInfo {
                    ShareLink(
                        item: buildCopyText(camera: camera, info: info),
                        label: { Image(systemName: "square.and.arrow.up").foregroundColor(.primary) }
                    )
                }
            }
            .padding(12)

            if isExpanded {
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        if let camera = cameraPosition {
                            InfoRow(label: "Zoom", value: String(format: "%.2f", camera.zoom))
                            InfoRow(label: "Bearing", value: String(format: "%.2f°", camera.bearing))
                            InfoRow(label: "Tilt", value: String(format: "%.2f°", camera.tilt))
                            InfoRow(label: "Position", value: String(format: "%.6f, %.6f", camera.position.latitude, camera.position.longitude))
                        }
                        if let info = visibleRegionInfo {
                            Divider().padding(.vertical, 4)
                            Text("Bounds & Size").font(.subheadline).fontWeight(.medium)
                            InfoRow(label: "Size", value: String(format: "%.2f x %.2f km", info.widthKm, info.heightKm))
                            ForEach(info.corners, id: \.self) { corner in
                                Text(corner).font(.system(size: 11, design: .monospaced))
                            }
                            InfoRow(label: "Center", value: info.centerPoint)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }
                .frame(maxHeight: 280)
            }
        }
        .background(Color(UIColor.systemBackground).opacity(0.95))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
    }

    private func buildCopyText(camera: MapCameraPosition, info: VisibleRegionInfo) -> String {
        var lines = ["=== Visible Region Info ==="]
        lines.append(String(format: "Zoom: %.2f", camera.zoom))
        lines.append(String(format: "Bearing: %.2f°", camera.bearing))
        lines.append(String(format: "Tilt: %.2f°", camera.tilt))
        lines.append(String(format: "Position: %.6f, %.6f", camera.position.latitude, camera.position.longitude))
        lines.append(String(format: "Size: %.2f x %.2f km", info.widthKm, info.heightKm))
        lines.append(info.boundsString)
        lines.append(contentsOf: info.corners)
        return lines.joined(separator: "\n")
    }
}

private struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.primary)
                .frame(minWidth: 60, alignment: .leading)
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
