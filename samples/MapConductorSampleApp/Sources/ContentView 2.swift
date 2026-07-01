import SwiftUI
import MapConductorForMapLibre
import MapConductorCore
import MapConductorForMapKit
import MapConductorForMapbox

struct ContentView2: View {
    private var mapViewState: MapboxViewState
    
    private let center = GeoPoint(
        latitude: 43.09473984251199,
        longitude: 141.51752370787707
    )
    
    init() {
        
        let camera = MapCameraPosition(
            position: center,
            zoom: 13
        )
        mapViewState = MapboxViewState(
            cameraPosition: camera,
        )
    }
    
    var body: some View {
        MapboxMapView(
            state: mapViewState,
            content: {
                
                Marker(
                    position: center,
                    icon: DefaultMarkerIcon(
                        label: "Japan",
                    )
                )
                
            }
        )
    }
}
