import SwiftUI
import MapConductorCore
import MapConductorForMapKit

struct ContentView2: View {
    @StateObject private var mapState = MapKitViewState(
        cameraPosition: MapCameraPosition(
            position: GeoPoint(latitude: 0.014, longitude: 0.008),
            zoom: 15.0
        )
    )

    var body: some View {
        MapKitMapView(state: mapState, content : {
            Marker(state: MarkerState(
                position: GeoPoint(latitude: 0.018, longitude: 0.004),
                id: "dm_07",
                icon: DefaultMarkerIcon(scale: 0.7, label: "scale=0.7"),
            ))
            Marker(state: MarkerState(
                position: GeoPoint(latitude: 0.018, longitude: 0.008),
                id: "dm_10",
                icon: DefaultMarkerIcon(
                    fillColor: UIColor.green,
                    scale: 1.0,
                    label: "scale=1.0",
                )
            ))
            Marker(state: MarkerState(
                position: GeoPoint(latitude: 0.018, longitude: 0.012),
                id: "dm_14",
                icon: DefaultMarkerIcon(
                    fillColor: UIColor.white,
                    strokeColor: UIColor.black,
                    scale: 1.4, label: "scale=1.4")
            ))
            if let image = ContentView2.loadPngImage(named: "coffee_extra") {
                Marker(state: MarkerState(
                    position: GeoPoint(latitude: 0.018, longitude: 0.016),
                    id: "imd_wmo",
                    icon: ImageDefaultIcon(backgroundImage: image)
                ))
            }
        })
    }
    private static func makeStoreIcon(named name: String) -> ImageDefaultIcon? {
        guard let image = loadPngImage(named: name) else { return nil }
        return ImageDefaultIcon(
            backgroundImage: image,
            strokeColor: .white,
            strokeWidth: DefaultMarkerIcon.defaultStrokeWidth,
            scale: 1.0,
            infoAnchor: DefaultMarkerIcon.defaultInfoAnchor,
            iconSize: DefaultMarkerIcon.defaultIconSize,
            debug: false
        )
    }
    private static func loadPngImage(named name: String) -> UIImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
              let data = try? Data(contentsOf: url),
              let image = UIImage(data: data) else {
            return nil
        }
        return image
    }
}
