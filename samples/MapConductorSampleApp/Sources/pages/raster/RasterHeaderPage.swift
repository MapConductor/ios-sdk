import MapConductorCore
import MapConductorForArcGIS
import MapConductorForGoogleMaps
import MapConductorForHERE
import MapConductorForLongdo
import MapConductorForMapKit
import MapConductorForMapLibre
import MapConductorForMapTiler
import MapConductorForMapbox
import MapConductorForTomTom
import SwiftUI

/// `RasterHeaderUITests` が使う計測ページ。
///
/// `RasterLayerState` の `userAgent` / `extraHeaders` が**実際にタイル要求に載るか**を
/// プロバイダごとに確かめる。タイルの取得はプロバイダのネイティブ SDK が握っているので、
/// 送り出す側のコードを読んでも「載っているか」は分からない。受け取る側をアプリ内に立てて
/// 届いたヘッダをそのまま読む（``HeaderRecordingTileServer``）。
///
/// プロバイダは `MAPCONDUCTOR_SAMPLE_PROVIDER` で選ぶ。
///
/// アクセシビリティ経由で次を公開する:
///
/// - `rasterHeaderCount`   受け取ったタイル要求の数。0 ならそもそも取りに来ていない
/// - `rasterHeaderUA`      観測した User-Agent（未観測は `-`）
/// - `rasterHeaderCustom`  観測した `X-MapConductor-Test`（未観測は `-`）
///
/// `rasterHeaderCount` を分けているのは、失敗したときに**取りに来ていない**のか
/// **来たがヘッダが無い**のかを区別するため。前者はページの不備、後者が本題。
struct RasterHeaderPage: View {
    /// 送信を期待する値。UI テスト側と一致させること。
    static let expectedUserAgent = "MapConductorRasterHeaderProbe/1.0"
    static let expectedHeaderName = "X-MapConductor-Test"
    static let expectedHeaderValue = "mapconductor-probe"

    private static let center = GeoPoint(latitude: 35.681236, longitude: 139.767125)
    private static let camera = MapCameraPosition(position: RasterHeaderPage.center, zoom: 8.0)

    let onToggleSidebar: () -> Void

    @StateObject private var probe = RasterHeaderProbe()
    @State private var provider: MapProvider = MapProvider.initial(fallback: .mapLibre)

    @StateObject private var googleState = GoogleMapViewState(cameraPosition: RasterHeaderPage.camera)
    @StateObject private var mapLibreState = MapLibreViewState(
        mapDesignType: MapLibreDesign.DemoTiles, cameraPosition: RasterHeaderPage.camera)
    @StateObject private var mapKitState = MapKitViewState(
        mapDesignType: MapKitMapDesign.Standard, cameraPosition: RasterHeaderPage.camera)
    @StateObject private var mapboxState = MapboxViewState(cameraPosition: RasterHeaderPage.camera)
    @StateObject private var arcGISState = ArcGISMapViewState(
        mapDesignType: ArcGISDesign.OsmStandard, cameraPosition: RasterHeaderPage.camera)
    @StateObject private var hereState = HereMapViewState(
        mapDesignType: HereMapDesign.NormalDay, cameraPosition: RasterHeaderPage.camera)
    @StateObject private var tomTomState = TomTomMapViewState(
        mapDesignType: TomTomMapDesign.Standard, cameraPosition: RasterHeaderPage.camera)
    @StateObject private var mapTilerState = MapTilerViewState(
        mapDesignType: MapTilerDesign.Streets, cameraPosition: RasterHeaderPage.camera)
    @StateObject private var longdoState = LongdoViewState(
        mapDesignType: LongdoDesign.Normal, cameraPosition: RasterHeaderPage.camera)

    private let refresh = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack(alignment: .top) {
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
                sdkInitialize: SampleMapView.initializeAllSDKs
            ) {
                var content = MapViewContent()
                content.rasterLayers = [RasterLayer(state: probe.rasterLayerState)]
                return content
            }

            VStack(spacing: 0) {
                Text(probe.observedCount).accessibilityIdentifier("rasterHeaderCount")
                Text(probe.observedUserAgent).accessibilityIdentifier("rasterHeaderUA")
                Text(probe.observedCustomHeader).accessibilityIdentifier("rasterHeaderCustom")
            }
            .font(.caption2)
            .opacity(0.85)
        }
        .onReceive(refresh) { _ in probe.refresh() }
    }
}

/// 計測サーバとラスタレイヤの寿命を握る。
///
/// `View` の struct に持たせると再構築のたびにサーバが立ち上がるので、
/// `@StateObject` にして 1 回だけ作る。
@MainActor
final class RasterHeaderProbe: ObservableObject {
    @Published var observedCount: String = "0"
    @Published var observedUserAgent: String = "-"
    @Published var observedCustomHeader: String = "-"

    private let server = HeaderRecordingTileServer.start()
    let rasterLayerState: RasterLayerState

    init() {
        rasterLayerState = RasterLayerState(
            source: .urlTemplate(template: server.urlTemplate(), tileSize: 256),
            opacity: 1.0,
            visible: true,
            zIndex: 0,
            userAgent: RasterHeaderPage.expectedUserAgent,
            extraHeaders: [RasterHeaderPage.expectedHeaderName: RasterHeaderPage.expectedHeaderValue],
            id: "raster_header_probe"
        )
    }

    func refresh() {
        observedCount = String(server.requestCount)
        observedUserAgent = server.anyHeader("User-Agent") ?? "-"
        observedCustomHeader = server.anyHeader(RasterHeaderPage.expectedHeaderName) ?? "-"
    }

    deinit {
        server.stop()
    }
}
