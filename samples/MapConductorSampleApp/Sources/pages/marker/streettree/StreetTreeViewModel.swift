import Foundation
import MapConductorCore

@MainActor
final class StreetTreeViewModel: ObservableObject {
    let initCameraPosition: MapCameraPosition

    @Published var markers: [MarkerState] = []
    @Published var selectedMarker: MarkerState?
    @Published var isDataLoading = false
    @Published private(set) var speciesCount = 0

    let markerTiling = MarkerTilingOptions(
        // Trees are planted a few metres apart along a road, so below street
        // level most of them sit on top of one another. Thinning them to one
        // per icon width halves the tile bytes and shows the same map.
        iconScaleCallback: { _, zoom in StreetTreeViewModel.iconScale(zoom: zoom) },
        declutterPx: 14
    )

    /// Matches android-sdk's StreetTreeViewModel and the web sample, so the
    /// three show the same density at the same zoom.
    static func iconScale(zoom: Int) -> Double {
        if zoom > 15 { return 1.4 }
        if zoom > 13 { return 1.0 }
        if zoom > 11 { return 0.7 }
        return 0.5
    }

    init() {
        self.initCameraPosition = MapCameraPosition(
            position: GeoPoint.fromLatLong(latitude: 35.6812, longitude: 139.7671),
            zoom: 11.0,
            bearing: 0.0,
            tilt: 0.0,
            paddings: nil
        )
    }

    func loadTrees() {
        if !markers.isEmpty { return }
        isDataLoading = true

        Task { [weak self] in
            guard let self else { return }
            let data = await StreetTreeDataLoader().load()
            let icons = StreetTreeIcons.palette(count: data.species.count)
            self.speciesCount = data.species.count
            self.markers = data.trees.enumerated().map { index, tree in
                MarkerState(
                    position: tree.position,
                    id: String(index),
                    extra: tree,
                    icon: icons[tree.speciesIndex],
                    animation: nil,
                    clickable: true,
                    draggable: false,
                    onClick: { [weak self] marker in
                        self?.selectedMarker = marker
                    }
                )
            }
            self.isDataLoading = false
        }
    }

    func clearSelection() {
        selectedMarker = nil
    }
}
