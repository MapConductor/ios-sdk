import MapConductorCore
import MapConductorForMapLibre
import MapConductorForMapTiler
import MapConductorForMapbox
import MapConductorForMappls
import SwiftUI

/// `StyleReloadUITests` が実機で使う計測ページ。
///
/// Mapbox / MapLibre / MapTiler は地図デザインを変えると新しいスタイルを読み込み、
/// ランタイムに足したソース・レイヤ・画像がすべて捨てられる。オーバーレイがその後
/// ちゃんと作り直されるかを確かめる。プロバイダは
/// `MAPCONDUCTOR_SAMPLE_PROVIDER`（mapbox / maplibre / maptiler / mappls）で選ぶ。
///
/// アクセシビリティ経由で次を公開する:
///
/// - `styleReloadAnchor`  マーカーのアンカー（ウィンドウ座標・pt）
/// - `styleReloadResult`  `"<seq>:HIT"` / `"<seq>:MISS"`。タップごとに seq が増える
/// - `styleReloadDesign`  現在の地図デザイン id
/// - `styleReloadToggle`  デザインを切り替えるボタン
/// - `styleReloadChurn`   デザインを切り替え、読み込み中にラスタを出し入れするボタン
/// - `styleReloadChurnDone` 出し入れを終えた回数
///
/// 判定にタップを使うのは、当たり判定が**実際に描かれているもの**を見るため。
/// マネージャが状態を持っているだけでは HIT にならない。
/// `HereHitTestPage` と同じ計測ページの作りに合わせてある。
struct StyleReloadPage: View {
    static let center = GeoPoint(latitude: 35.681236, longitude: 139.767125)
    static let mapplsCenter = GeoPoint(latitude: 28.613939, longitude: 77.209021)

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
    /// Mappls はインド国外のタイルを配らないので、デリーを映す。
    @StateObject private var mapplsState = MapplsViewState(
        mapDesignType: MapplsDesign.Default,
        cameraPosition: MapCameraPosition(position: StyleReloadPage.mapplsCenter, zoom: 14.0)
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
    @State private var rasterShown = true
    /// 出し入れ中だけ進む。ラスタ以外のオーバーレイもこれで揺らす（0 のときは元の配置）。
    @State private var churnTick = 0
    @State private var churnDone = 0

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
                Button("Churn") { churn() }
                    .accessibilityIdentifier("styleReloadChurn")
                Text("\(churnDone)").accessibilityIdentifier("styleReloadChurnDone")
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
        case "mappls":
            MapplsMapView(
                state: mapplsState,
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

    /// 出し入れ中に交互に 0 / 0.001° ずらす量。
    private var wiggle: Double { Double(churnTick % 2) * 0.001 }

    @MapViewContentBuilder
    private var overlays: MapViewContent {
        Marker(state: MarkerState(
            position: GeoPoint(
                latitude: StyleReloadPage.center.latitude + wiggle,
                longitude: StyleReloadPage.center.longitude
            ),
            id: "stylereload_target",
            icon: DefaultMarkerIcon(),
            onClick: { _ in record("HIT") }
        ))
        Circle(
            center: GeoPoint(latitude: 35.6840, longitude: 139.7600),
            radiusMeters: 200 + wiggle * 50_000,
            strokeColor: .blue,
            fillColor: UIColor.blue.withAlphaComponent(0.3)
        )
        Polyline(
            points: StyleReloadPage.ring.map {
                GeoPoint(latitude: $0.latitude + wiggle, longitude: $0.longitude)
            },
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
        if rasterShown {
            RasterLayer(state: rasterProbe.rasterLayerState)
        }
        if churnTick % 3 != 1 {
            GroundImage(state: rasterProbe.groundImageState)
        }
    }

    private var currentDesignId: String {
        switch Self.selectedProvider {
        case "maplibre": return mapLibreState.mapDesignType.id
        case "maptiler": return mapTilerState.mapDesignType.id
        case "mappls": return mapplsState.mapDesignType.id
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
        case "mappls":
            // 契約外のスタイルは弾かれるので、使えるのは既定と standard_day だけ。
            // 既定へ戻すときは setMapplsMapStyle が呼ばれず、スタイルは差し替わらない。
            mapplsState.mapDesignType =
                mapplsState.mapDesignType.id == MapplsDesign.Default.id
                    ? MapplsDesign.StandardDay
                    : MapplsDesign.Default
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
        case "mappls": holder = mapplsState.getMapViewHolder()
        default: holder = mapboxState.getMapViewHolder()
        }
        let target = Self.selectedProvider == "mappls" ? StyleReloadPage.mapplsCenter : StyleReloadPage.center
        guard let holder, let local = holder.toScreenOffset(position: target) else {
            anchor = "?"
            return
        }
        anchor = String(
            format: "%.2f,%.2f",
            mapFrame.origin.x + local.x,
            mapFrame.origin.y + local.y
        )
    }

    /// スタイルの差し替えと、その読み込み中のラスタ操作を重ねる。
    ///
    /// デザインを切り替えた直後から 3 秒間、20ms ごとにラスタと地上画像を出し入れし、
    /// ラスタのソースも差し替える。マーカー・円・線もずらし続ける。新しいスタイルが載るまでの間に追加・削除・ソース差し替えが
    /// 走るので、描画側が手放された古いスタイルを触っていれば、ここで落ちる。
    private func churn() {
        // 対照実験用: デザインを変えずに出し入れだけする。
        if ProcessInfo.processInfo.environment["MAPCONDUCTOR_STYLERELOAD_KEEP_DESIGN"] != "1" {
            toggleDesign()
        }
        Task { @MainActor in
            let end = Date().addingTimeInterval(3)
            while Date() < end {
                churnTick += 1
                rasterShown.toggle()
                rasterProbe.flipSource()
                rasterProbe.groundImageState.opacity = churnTick % 2 == 0 ? 0.5 : 0.8
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
            rasterShown = true
            churnTick = 0
            churnDone += 1
        }
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
    /// 出し入れ用の地上画像。ラスタと同じくスタイルへソースとレイヤを足す経路を通す。
    let groundImageState = GroundImageState(
        bounds: GeoRectBounds(
            southWest: GeoPoint(latitude: 35.6700, longitude: 139.7500),
            northEast: GeoPoint(latitude: 35.6900, longitude: 139.7800)
        ),
        image: UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
            UIColor.orange.withAlphaComponent(0.4).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        },
        opacity: 0.8,
        id: "stylereload_groundimage"
    )

    init() {
        rasterLayerState = RasterLayerState(
            source: .urlTemplate(template: server.urlTemplate(), tileSize: 256),
            // タイル画像自体が α 0.35 のマゼンタなので、レイヤ側は下げない。
            // 薄くすると画面平均の色の偏りが小さくなり、判定の余裕が無くなる。
            opacity: 1.0,
            id: "stylereload_raster"
        )
    }

    /// タイルサイズを 256 / 512 で行き来させる。ソースの指紋が変わるので、
    /// 描画側はソースとレイヤを作り直す（URL は同じなのでサーバはそのまま）。
    func flipSource() {
        tileSize = tileSize == 256 ? 512 : 256
        rasterLayerState.source = .urlTemplate(template: server.urlTemplate(), tileSize: tileSize)
    }
    private var tileSize = 256

    deinit {
        server.stop()
    }
}
