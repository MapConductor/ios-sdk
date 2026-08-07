import MapConductorCore
import MapConductorForMapLibre
import MapConductorForMapTiler
import MapConductorForMapbox
import SwiftUI

/// `StyleReloadUITests` が実機で使う計測ページ。
///
/// Mapbox / MapLibre / MapTiler は地図デザインを変えると新しいスタイルを読み込み、
/// ランタイムに足したソース・レイヤ・画像がすべて捨てられる。オーバーレイがその後
/// ちゃんと作り直されるかを確かめる。プロバイダは
/// `MAPCONDUCTOR_SAMPLE_PROVIDER`（mapbox / maplibre / maptiler）で選ぶ。
///
/// アクセシビリティ経由で次を公開する:
///
/// - `styleReloadAnchor`  マーカーのアンカー（ウィンドウ座標・pt）
/// - `styleReloadResult`  `"<seq>:HIT"` / `"<seq>:MISS"`。タップごとに seq が増える
/// - `styleReloadDesign`  現在の地図デザイン id
/// - `styleReloadToggle`  デザインを切り替えるボタン
///
/// 判定にタップを使うのは、当たり判定が**実際に描かれているもの**を見るため。
/// マネージャが状態を持っているだけでは HIT にならない。
/// `HereHitTestPage` と同じ計測ページの作りに合わせてある。
struct StyleReloadPage: View {
    static let center = GeoPoint(latitude: 35.681236, longitude: 139.767125)

    /// 中央のマーカーから離した位置に他のオーバーレイを置く（当たり判定が被らないように）。
    private static let ring: [GeoPoint] = [
        GeoPoint(latitude: 35.6870, longitude: 139.7620),
        GeoPoint(latitude: 35.6870, longitude: 139.7720),
        GeoPoint(latitude: 35.6790, longitude: 139.7720),
        GeoPoint(latitude: 35.6790, longitude: 139.7620),
    ]

    private static var selectedProvider: String {
        ProcessInfo.processInfo.environment["MAPCONDUCTOR_SAMPLE_PROVIDER"]?.lowercased() ?? "mapbox"
    }

    let onToggleSidebar: () -> Void

    @StateObject private var mapboxState = MapboxViewState(
        mapDesignType: MapboxMapDesign.Streets,
        cameraPosition: MapCameraPosition(position: StyleReloadPage.center, zoom: 14.0)
    )
    @StateObject private var mapLibreState = MapLibreViewState(
        mapDesignType: MapLibreDesign.OsmBright,
        cameraPosition: MapCameraPosition(position: StyleReloadPage.center, zoom: 14.0)
    )
    @StateObject private var mapTilerState = MapTilerViewState(
        mapDesignType: MapTilerDesign.Streets,
        cameraPosition: MapCameraPosition(position: StyleReloadPage.center, zoom: 14.0)
    )

    /// ラスタレイヤの配信元。判定は画面の色で行うので、ここは**タイルを配るだけ**。
    ///
    /// 受け取った数を画面に出してはいけない。数は増え続けるので表示が止まらず、
    /// UI が静止しないまま `XCUIElement.tap()` が撃たれてボタンを外す
    /// （実機で「トグルを押したのに地図がクリックされた」形で踏んだ）。
    @StateObject private var rasterProbe = StyleReloadRasterProbe()

    @State private var seq: Int = 0
    @State private var result: String = "NONE"
    @State private var anchor: String = "?"
    @State private var mapFrame: CGRect = .zero

    private let refresh = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack(alignment: .top) {
            GeometryReader { geo in
                mapView
                    .onAppear { mapFrame = geo.frame(in: .global) }
                    .onChange(of: geo.frame(in: .global)) { _, newFrame in mapFrame = newFrame }
            }

            // 読み出し用。テストは中央付近しかタップしないので上端に寄せておく。
            VStack(spacing: 0) {
                Text(anchor).accessibilityIdentifier("styleReloadAnchor")
                Text(result).accessibilityIdentifier("styleReloadResult")
                Text(currentDesignId).accessibilityIdentifier("styleReloadDesign")
                Button("Toggle design") { toggleDesign() }
                    .accessibilityIdentifier("styleReloadToggle")
            }
            .font(.caption2)
            .opacity(0.85)
        }
        .onReceive(refresh) { _ in updateAnchor() }
    }

    @ViewBuilder
    private var mapView: some View {
        switch Self.selectedProvider {
        case "maplibre":
            MapLibreMapView(
                state: mapLibreState,
                onMapClick: { _ in record("MISS") },
                sdkInitialize: SampleMapView.initializeAllSDKs
            ) { overlays }
        case "maptiler":
            MapTilerMapView(
                state: mapTilerState,
                onMapClick: { _ in record("MISS") },
                sdkInitialize: SampleMapView.initializeAllSDKs
            ) { overlays }
        default:
            MapboxMapView(
                state: mapboxState,
                onMapClick: { _ in record("MISS") },
                sdkInitialize: SampleMapView.initializeAllSDKs
            ) { overlays }
        }
    }

    @MapViewContentBuilder
    private var overlays: MapViewContent {
        Marker(state: MarkerState(
            position: StyleReloadPage.center,
            id: "stylereload_target",
            icon: DefaultMarkerIcon(),
            onClick: { _ in record("HIT") }
        ))
        Circle(
            center: GeoPoint(latitude: 35.6840, longitude: 139.7600),
            radiusMeters: 200,
            strokeColor: .blue,
            fillColor: UIColor.blue.withAlphaComponent(0.3)
        )
        Polyline(
            points: StyleReloadPage.ring,
            strokeColor: .red,
            strokeWidth: 4
        )
        Polygon(
            points: [
                GeoPoint(latitude: 35.6760, longitude: 139.7640),
                GeoPoint(latitude: 35.6760, longitude: 139.7700),
                GeoPoint(latitude: 35.6730, longitude: 139.7670),
            ],
            strokeColor: .green,
            fillColor: UIColor.green.withAlphaComponent(0.4)
        )
        RasterLayer(state: rasterProbe.rasterLayerState)
    }

    private var currentDesignId: String {
        switch Self.selectedProvider {
        case "maplibre": return mapLibreState.mapDesignType.id
        case "maptiler": return mapTilerState.mapDesignType.id
        default: return mapboxState.mapDesignType.id
        }
    }

    /// スタイル再読込を起こす。切り替え先はベクタタイルの別スタイルにしておく
    /// （衛星画像だとマーカーが見えていても目視確認しづらいため）。
    private func toggleDesign() {
        switch Self.selectedProvider {
        case "maplibre":
            mapLibreState.mapDesignType =
                mapLibreState.mapDesignType.id == MapLibreDesign.OsmBright.id
                    ? MapLibreDesign.DemoTiles
                    : MapLibreDesign.OsmBright
        case "maptiler":
            mapTilerState.mapDesignType =
                mapTilerState.mapDesignType.id == MapTilerDesign.Streets.id
                    ? MapTilerDesign.Bright
                    : MapTilerDesign.Streets
        default:
            mapboxState.mapDesignType =
                mapboxState.mapDesignType.id == MapboxMapDesign.Streets.id
                    ? MapboxMapDesign.Outdoors
                    : MapboxMapDesign.Streets
        }
    }

    private func updateAnchor() {
        let holder: AnyMapViewHolder?
        switch Self.selectedProvider {
        case "maplibre": holder = mapLibreState.getMapViewHolder()
        case "maptiler": holder = mapTilerState.getMapViewHolder()
        default: holder = mapboxState.getMapViewHolder()
        }
        guard let holder, let local = holder.toScreenOffset(position: StyleReloadPage.center) else {
            anchor = "?"
            return
        }
        anchor = String(
            format: "%.2f,%.2f",
            mapFrame.origin.x + local.x,
            mapFrame.origin.y + local.y
        )
    }

    private func record(_ outcome: String) {
        seq += 1
        result = "\(seq):\(outcome)"
    }
}

/// ラスタレイヤ用の計測サーバとレイヤの寿命を握る。
///
/// `View` の struct に持たせると再構築のたびにサーバが立ち上がるので、
/// `@StateObject` にして 1 回だけ作る。
@MainActor
final class StyleReloadRasterProbe: ObservableObject {
    private let server = HeaderRecordingTileServer.start()
    let rasterLayerState: RasterLayerState

    init() {
        rasterLayerState = RasterLayerState(
            source: .urlTemplate(template: server.urlTemplate(), tileSize: 256),
            // タイル画像自体が α 0.35 のマゼンタなので、レイヤ側は下げない。
            // 薄くすると画面平均の色の偏りが小さくなり、判定の余裕が無くなる。
            opacity: 1.0,
            id: "stylereload_raster"
        )
    }

    deinit {
        server.stop()
    }
}
