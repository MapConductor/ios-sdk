import GoogleMaps
import MapConductorForHERE
import MapConductorForTomTom
import MapConductorForMapTiler
import MapConductorCore
import MapConductorForGoogleMaps
import MapConductorForMapLibre
import MapConductorForMapKit
import MapConductorForMapbox
import MapConductorForArcGIS
import MapConductorForLongdo
import MapConductorForOpenMobileMaps
import MapConductorForMappls
import SwiftUI
import UIKit

// 信州大学（松本キャンパス）周辺に 3 × 3 で並べ、それぞれ違う labelPosition を付ける。
// react-sdk の marker-label-position、android-sdk の MarkerLabelPositionPage と同じ配置。
private let labelPositionCenter = GeoPoint(latitude: 36.2526, longitude: 137.9828)

struct MarkerLabelPositionPage: View {
    let onToggleSidebar: () -> Void

    init(onToggleSidebar: @escaping () -> Void = {}) {
        self.onToggleSidebar = onToggleSidebar
    }

    @State private var provider: MapProvider = MapProvider.initial()
    @State private var selectedId: String?

    @StateObject private var googleState = GoogleMapViewState(
        cameraPosition: MapCameraPosition(
            position: labelPositionCenter,
            zoom: 14
        )
    )

    @StateObject private var mapLibreState = MapLibreViewState(
        mapDesignType: MapLibreDesign.DemoTiles,
        cameraPosition: MapCameraPosition(
            position: labelPositionCenter,
            zoom: 14
        )
    )

    @StateObject private var mapKitState = MapKitViewState(
        mapDesignType: MapKitMapDesign.Standard,
        cameraPosition: MapCameraPosition(
            position: labelPositionCenter,
            zoom: 14
        )
    )

    @StateObject private var mapboxState = MapboxViewState(
        cameraPosition: MapCameraPosition(
            position: labelPositionCenter,
            zoom: 14
        )
    )

    @StateObject private var arcGISState = ArcGISMapViewState(
        mapDesignType: ArcGISDesign.OsmStandard,
        cameraPosition: MapCameraPosition(
            position: labelPositionCenter,
            zoom: 14
        )
    )
    
    @StateObject private var hereState = HereMapViewState(
        mapDesignType: HereMapDesign.NormalDay,
        cameraPosition: MapCameraPosition(
            position: labelPositionCenter,
            zoom: 14
        )
    )
    @StateObject private var tomTomState = TomTomMapViewState(
        mapDesignType: TomTomMapDesign.Standard,
        cameraPosition: MapCameraPosition(
            position: labelPositionCenter,
            zoom: 14
        )
    )
    @StateObject private var mapTilerState = MapTilerViewState(
        mapDesignType: MapTilerDesign.Streets,
        cameraPosition: MapCameraPosition(
            position: labelPositionCenter,
            zoom: 14
        )
    )
    @StateObject private var longdoState = LongdoViewState(
        mapDesignType: LongdoDesign.Normal,
        cameraPosition: MapCameraPosition(
            position: labelPositionCenter,
            zoom: 14
        )
    )
    @StateObject private var openMobileMapsState = OpenMobileMapsViewState(
        mapDesignType: OpenMobileMapsDesign.openStreetMap,
        cameraPosition: MapCameraPosition(
            position: labelPositionCenter,
            zoom: 14
        )
    )
    @StateObject private var mapplsState = MapplsViewState(
        mapDesignType: MapplsDesign.Default,
        cameraPosition: MapCameraPosition(
            position: labelPositionCenter,
            zoom: 14
        )
    )
    
    private let markerStates: [MarkerState] = {
        let positions = [
            ["left top", "center top", "right top"],
            ["left center", "center center", "right center"],
            ["left bottom", "center bottom", "right bottom"],
        ]
        return positions.enumerated().flatMap { rowIndex, row in
            row.enumerated().map { columnIndex, labelPosition in
                MarkerState(
                    position: GeoPoint(
                        latitude: labelPositionCenter.latitude + Double(1 - rowIndex) * 0.004,
                        longitude: labelPositionCenter.longitude + Double(columnIndex - 1) * 0.007
                    ),
                    id: labelPosition,
                    extra: labelPosition,
                    icon: DefaultMarkerIcon(
                        label: labelPosition == "center center" ? "信" : "信州大学",
                        labelPosition: labelPosition,
                        debug: true
                    )
                )
            }
        }
    }()

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
                openMobileMapsState: openMobileMapsState,
                mapplsState: mapplsState,
                onMapClick: { _ in
                    selectedId = nil
                }
            ) {
                for markerState in markerStates {
                    Marker(state: markerState)
                    if selectedId == markerState.id {
                        InfoBubble(marker: markerState) {
                            Text("labelPosition: \"\(markerState.extra as? String ?? "")\"")
                                .font(.system(.body, design: .monospaced))
                        }
                    }
                }
            }
        }
        .onAppear {
            markerStates.forEach { marker in
                marker.onClick = { clicked in
                    selectedId = clicked.id
                }
            }
        }
    }
}
