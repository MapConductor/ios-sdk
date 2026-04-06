import Foundation
import MapConductorCore

struct VisibleRegionInfo {
    let boundsString: String
    let corners: [String]
    let centerPoint: String
    let widthKm: Double
    let heightKm: Double
}

@MainActor
final class VisibleRegionViewModel: ObservableObject {
    @Published var cameraPosition: MapCameraPosition?
    @Published var visibleRegionInfo: VisibleRegionInfo?

    func onCameraChanged(_ camera: MapCameraPosition) {
        cameraPosition = camera
        if let vr = camera.visibleRegion {
            visibleRegionInfo = createVisibleRegionInfo(vr)
        }
    }

    private func createVisibleRegionInfo(_ visibleRegion: VisibleRegion) -> VisibleRegionInfo {
        let bounds = visibleRegion.bounds

        guard !bounds.isEmpty, let sw = bounds.southWest, let ne = bounds.northEast else {
            return VisibleRegionInfo(
                boundsString: "Empty bounds",
                corners: [],
                centerPoint: "N/A",
                widthKm: 0.0,
                heightKm: 0.0
            )
        }

        let boundsString = String(
            format: "SW: (%.6f, %.6f) NE: (%.6f, %.6f)",
            sw.latitude, sw.longitude, ne.latitude, ne.longitude
        )

        var corners: [String] = []
        if let p = visibleRegion.nearLeft  { corners.append(String(format: "NearLeft: (%.6f, %.6f)", p.latitude, p.longitude)) }
        if let p = visibleRegion.nearRight { corners.append(String(format: "NearRight: (%.6f, %.6f)", p.latitude, p.longitude)) }
        if let p = visibleRegion.farLeft   { corners.append(String(format: "FarLeft: (%.6f, %.6f)", p.latitude, p.longitude)) }
        if let p = visibleRegion.farRight  { corners.append(String(format: "FarRight: (%.6f, %.6f)", p.latitude, p.longitude)) }

        let centerLat = (ne.latitude + sw.latitude) / 2
        let centerLng = (ne.longitude + sw.longitude) / 2
        let centerPoint = String(format: "Center: (%.6f, %.6f)", centerLat, centerLng)

        let widthM = Spherical.computeDistanceBetween(
            from: sw,
            to: GeoPoint(latitude: sw.latitude, longitude: ne.longitude)
        )
        let heightM = Spherical.computeDistanceBetween(
            from: sw,
            to: GeoPoint(latitude: ne.latitude, longitude: sw.longitude)
        )

        return VisibleRegionInfo(
            boundsString: boundsString,
            corners: corners,
            centerPoint: centerPoint,
            widthKm: widthM / 1000.0,
            heightKm: heightM / 1000.0
        )
    }
}
