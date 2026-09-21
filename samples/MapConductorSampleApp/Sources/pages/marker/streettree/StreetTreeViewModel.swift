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
        // `MAPCONDUCTOR_SAMPLE_TILE_DEBUG=1` でタイルの格子と番号を焼き込む。
        // 継ぎ目の不具合は「どの 2 枚の間か」が分からないと追えない。
        // 一度環境変数で指定されたら UserDefaults に覚え、**手動起動でも維持**する
        // （devicectl から環境変数付きで起動し直さなくても格子が残る）。
        // 消すときは =0 で起動する。
        debugTileOverlay: StreetTreeViewModel.tileDebugEnabled(),
        // Trees are planted a few metres apart along a road, so below street
        // level most of them sit on top of one another. Thinning them to one
        // per icon width halves the tile bytes and shows the same map.
        iconScaleCallback: { _, zoom in StreetTreeViewModel.iconScale(zoom: zoom) },
        declutterPx: 14
    )

    static func tileDebugEnabled() -> Bool {
        let key = "mc.sample.tileDebug"
        if let raw = ProcessInfo.processInfo.environment["MAPCONDUCTOR_SAMPLE_TILE_DEBUG"] {
            let on = raw == "1"
            UserDefaults.standard.set(on, forKey: key)
            return on
        }
        return UserDefaults.standard.bool(forKey: key)
    }

    /// Matches android-sdk's StreetTreeViewModel and the web sample, so the
    /// three show the same density at the same zoom.
    static func iconScale(zoom: Int) -> Double {
        if zoom > 15 { return 1.4 }
        if zoom > 13 { return 1.0 }
        if zoom > 11 { return 0.7 }
        return 0.5
    }

    init() {
        // 再現用の入口。`MAPCONDUCTOR_SAMPLE_INIT_CAMERA="35.698,139.766,17.5"` の
        // ように渡すと、その場・そのズームで開く。継ぎ目の不具合は特定のタイル
        // 境界でしか出ないので、口頭の「このあたり」を座標に固定できないと
        // 再現も検証もできない。
        let env = ProcessInfo.processInfo.environment["MAPCONDUCTOR_SAMPLE_INIT_CAMERA"]
        let parts = env?.split(separator: ",").compactMap { Double($0) } ?? []
        let (lat, lon, zoom) = parts.count == 3
            ? (parts[0], parts[1], parts[2])
            : (35.6812, 139.7671, 11.0)
        self.initCameraPosition = MapCameraPosition(
            position: GeoPoint.fromLatLong(latitude: lat, longitude: lon),
            zoom: zoom,
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
