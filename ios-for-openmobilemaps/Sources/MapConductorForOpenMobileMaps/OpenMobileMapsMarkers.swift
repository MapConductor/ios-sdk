import CoreGraphics
import Foundation
import MapCore
import MapConductorCore
import UIKit

/*
 * マーカーのレンダラとコントローラ（実装点 D のマーカー分 + F）。
 *
 * android-for-openmobilemaps の `OpenMobileMapsMarkerOverlayRenderer` /
 * `OpenMobileMapsMarkerController` と同じ構成。SDK に固有の罠も同じで、
 * どれもこのファイルの中で完結している:
 *
 *   1. アンカーをテクスチャへ焼き込む（SDK のアンカーオフセットは地図空間で効く）
 *   2. 傾けたぶんアイコンを縦へ引き伸ばす（`rotationX` で寝かせているため）
 *   3. 引き伸ばしは**傾きが落ち着いてから**適用する（毎フレーム直すとちらつく）
 */

// ── レンダラ ──────────────────────────────────────────────────────────────

/// マーカーのレンダラ。
///
/// ## ドラッグ層を持たない
///
/// MapLibre / MapTiler は GeoJSON ソースを丸ごと差し替える方式なので、ドラッグ中の
/// マーカーを専用レイヤへ逃がさないと指の位置と食い違う。Open Mobile Maps は
/// `MCIconInfoInterface.setCoordinate` で**要素を直接動かせる**ので、その必要が無い
/// （ios-for-here と同じ立場）。コアの `update(state:)` → ``onChange(data:)`` が
/// そのままドラッグの駆動経路になる。
@MainActor
final class OpenMobileMapsMarkerOverlayRenderer: MarkerOverlayRendererProtocol {
    typealias ActualMarker = OpenMobileMapsActualMarker

    /// これ未満の引き伸ばしの差ではアイコンを作り直さない。
    private static let stretchEpsilon: Double = 0.002

    /// 傾きがこの時間止まったら引き伸ばしを適用する。スライダ操作の指の粒度より十分短く。
    private static let stretchSettleSeconds: Double = 0.12

    private let markerManager: MarkerManager<OpenMobileMapsActualMarker>
    private weak var iconLayer: MCIconLayerInterface?
    private weak var surface: OpenMobileMapsMapSurface?

    var animateStartListener: OnMarkerEventHandler?
    var animateEndListener: OnMarkerEventHandler?

    /// 画面空間のマーカーアニメーション。ネイティブのアイコンを一時的に隠せるので、
    /// 傾き・回転があっても正しい見た目になる（ios-for-here と同じ経路）。
    var animationOverlay: MarkerAnimationOverlayCoordinator?

    /// アニメーション中でネイティブを隠しているマーカー。``applyIcons()`` が除く。
    ///
    /// SDK のアイコンは不透明度を持たないので、ios-for-here のように `opacity = 0` に
    /// できない。レイヤへ流す一覧から外すことで隠す。
    private var hiddenIds: Set<String> = []

    /// アイコンごとのテクスチャ。詳しい理由は ``paddedTexture(for:)`` を参照。
    private var textureCache: [BitmapIcon: PaddedTexture] = [:]

    /// いま地図上のアイコンに掛かっている縦の引き伸ばし。詳細は ``verticalStretch()``。
    private var appliedStretch: Double = 1.0

    /// アイコン id → 引き伸ばす前の高さ（px）。
    ///
    /// **比率を掛け続けないこと。** 「今の大きさ × 変化比」で更新すると、アイコンの追加
    /// （``createIcon(id:position:icon:)`` も引き伸ばしを掛ける）と傾きの変更が混ざったときに
    /// 基準がずれ、大きさが本来の値から離れていく。アンカーは割合なので、大きさがずれると
    /// アイコンの見える位置もずれる。元の高さを覚えて**毎回「元の高さ × 引き伸ばし」**を
    /// 入れるほうが、順序に関係なく必ず正しい。
    private var baseIconHeight: [String: Double] = [:]

    /// 落ち着き待ちの引き伸ばし適用。詳細は ``onVisualTiltChanged()``。
    private var stretchUpdateTask: Task<Void, Never>?

    init(
        markerManager: MarkerManager<OpenMobileMapsActualMarker>,
        iconLayer: MCIconLayerInterface?,
        surface: OpenMobileMapsMapSurface?
    ) {
        self.markerManager = markerManager
        self.iconLayer = iconLayer
        self.surface = surface
    }

    func onAdd(data: [MarkerOverlayAddParams]) async -> [OpenMobileMapsActualMarker?] {
        data.map { createIcon(id: $0.state.id, position: $0.state.position, icon: $0.bitmapIcon) }
    }

    func onChange(data: [MarkerOverlayChangeParams<OpenMobileMapsActualMarker>]) async
        -> [OpenMobileMapsActualMarker?] {
        data.map { params in
            let state = params.current.state
            // アイコンの見た目が変わっていなければ座標だけ動かす。作り直すとテクスチャを
            // 毎回アップロードし直すことになり、ドラッグ中に目に見えて重くなる。
            if let previous = params.prev.marker,
               params.current.fingerPrint.icon == params.prev.fingerPrint.icon {
                previous.setCoordinate(state.position.ommCoord)
                return previous
            }
            return createIcon(id: state.id, position: state.position, icon: params.bitmapIcon)
        }
    }

    func onRemove(data: [MarkerEntity<OpenMobileMapsActualMarker>]) async {
        for entity in data {
            baseIconHeight.removeValue(forKey: entity.state.id)
            hiddenIds.remove(entity.state.id)
        }
        iconLayer?.removeIdentifierList(data.map(\.state.id))
    }

    func onAnimate(entity: MarkerEntity<OpenMobileMapsActualMarker>) async {
        guard let animation = entity.state.getAnimation() else { return }
        guard let overlay = animationOverlay else {
            entity.state.animate(nil)
            return
        }

        // ネイティブのアイコンは伏せておき、画面空間のオーバーレイに演じさせる。
        // 着地したところで元に戻す（ios-for-here が `opacity` でやっていることを、
        // 不透明度を持たないこの SDK では「一覧から外す」で行う）。
        hiddenIds.insert(entity.state.id)
        applyIcons()
        animateStartListener?(entity.state)

        let icon = (entity.state.icon ?? DefaultMarkerIcon()).toBitmapIcon()
        overlay.start(MarkerAnimationOverlayEntry(
            id: entity.state.id,
            state: entity.state,
            icon: icon,
            animation: animation,
            duration: animation == .Bounce ? 2.0 : 0.3,
            onFinished: { [weak self] in
                guard let self else { return }
                self.hiddenIds.remove(entity.state.id)
                self.applyIcons()
                entity.state.animate(nil)
                self.animateEndListener?(entity.state)
            }
        ))
    }

    func onPostProcess() async {
        applyIcons()
    }

    func unbind() {
        stretchUpdateTask?.cancel()
        stretchUpdateTask = nil
        animationOverlay?.unbind()
        animationOverlay = nil
        textureCache.removeAll()
        baseIconHeight.removeAll()
        hiddenIds.removeAll()
        iconLayer = nil
        surface = nil
    }

    /// マネージャの全マーカーをレイヤへ流し直す。
    ///
    /// `tiling` が立っている entity はラスタータイルとして描かれるので、ここでは除く
    /// （除かないと同じマーカーが二重に出る）。
    private func applyIcons() {
        let icons = markerManager.allEntities()
            .filter { !$0.tiling && $0.visible && !hiddenIds.contains($0.state.id) }
            .compactMap(\.marker)
        iconLayer?.setIcons(icons)
    }

    /// 傾きが変わったので、アイコンの縦の引き伸ばしを付け直す。
    ///
    /// 既にあるアイコンの大きさを比率で直すだけなので、テクスチャは作り直さない。
    func onVisualTiltChanged() {
        let stretch = verticalStretch()
        if abs(stretch - appliedStretch) < Self.stretchEpsilon { return }

        // ★ すぐには適用しない。**傾きが落ち着いてから 1 回だけ**適用する。
        //
        // 傾きスライダを動かしている間、ここは毎フレーム呼ばれる。そのたびに全アイコンの
        // 大きさを書き換えて invalidate すると、SDK はアイコンレイヤのインスタンスバッファを
        // 組み直し、**組み直しの谷間のフレームでマーカーが消えたり位置が飛んだりする**
        // （android の実機で「スライダー移動中だけマーカーがチラつき、スライダーに合わせて
        // ズレる」という形で報告された）。
        //
        // 動かしている最中は補正が半端でも目立たない（cos の差ぶんだけ僅かに潰れて
        // 見えるだけ）。止まった瞬間に正しい高さへ揃える。
        stretchUpdateTask?.cancel()
        stretchUpdateTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.stretchSettleSeconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.applyStretch()
        }
    }

    private func applyStretch() {
        let stretch = verticalStretch()
        if abs(stretch - appliedStretch) < Self.stretchEpsilon { return }
        appliedStretch = stretch
        for entity in markerManager.allEntities() {
            guard let marker = entity.marker, let base = baseIconHeight[entity.state.id] else { continue }
            marker.setIconSize(MCVec2F(x: marker.getIconSize().x, y: Float(base * stretch)))
        }
        iconLayer?.invalidate()
    }

    /// 傾けたときにアイコンを縦へ引き伸ばす量。
    ///
    /// ## なぜ要るのか
    ///
    /// tilt は内側の `MCMapView` を X 軸まわりに回して作っている。視点距離を十分大きく
    /// 取った**ほぼ正射影**なので、SDK が描いたものは一律に縦が `cos(傾き)` へ潰れる。
    /// 地面に寝ているもの（ポリゴン・ポリライン・地図タイル）はそれで正しいが、
    /// **マーカーは常に正面を向いていなければならない**ので潰れては困る。
    ///
    /// 先に `1 / cos(傾き)` だけ縦へ伸ばしておけば、潰れたあとちょうど元の高さになる。
    /// アンカーは割合なので、伸ばしても指す位置は変わらない。
    private func verticalStretch() -> Double {
        let angle = min(max(abs(surface?.visualTilt ?? 0.0), 0.0), OpenMobileMapsTiltEmulation.maxTiltDegrees)
        return 1.0 / cos(angle * .pi / 180.0)
    }

    /// アイコンを 1 つ作る。
    ///
    /// `MCIconType.INVARIANT` は「ズームでも回転でも見た目の大きさが変わらない」種別で、
    /// MapConductor のマーカーの意味論（アイコンは画面上で常に同じ大きさ）に一致する。
    /// `FIXED` にすると地図と一緒に拡大され、他プロバイダと挙動が食い違う。
    private func createIcon(
        id: String,
        position: any GeoPointProtocol,
        icon: BitmapIcon
    ) -> OpenMobileMapsActualMarker? {
        // 新しく作るアイコンも、いま掛かっている引き伸ばしに合わせる。
        let stretch = verticalStretch()
        guard let padded = paddedTexture(for: icon) else { return nil }
        baseIconHeight[id] = padded.height
        return MCIconFactory.createIcon(
            withAnchor: id,
            coordinate: position.ommCoord,
            texture: padded.texture,
            iconSize: MCVec2F(x: Float(padded.width), y: Float(padded.height * stretch)),
            scale: .INVARIANT,
            blendMode: .NORMAL,
            // ★ 常に中央。アンカーのオフセットは SDK に渡さない（下の理由を参照）。
            iconAnchor: MCVec2F(x: 0.5, y: 0.5)
        )
    }

    /// アンカーを焼き込んだテクスチャ。**必ずここを通すこと。**
    ///
    /// ## SDK のアンカーオフセットは地図空間で適用される（＝ bearing で回る）
    ///
    /// `createIconWithAnchor` のアンカーを素直に渡すと、座標からのオフセットが
    /// **画面空間ではなく地図空間**で掛かる。bearing 0 なら区別が付かないが、
    /// android では bearing 270 の Tilt ページで**全ピンがちょうど自分の高さぶん横にズレる**
    /// 形で発覚した（マーカー位置に地面固定の円を描いて確定。円は正しく、アイコンだけ
    /// ズレていた）。さらに傾き補正でアイコンの高さを変えるたびにオフセット量も変わるので、
    /// **スライダに合わせてズレが動く**ように見える。
    ///
    /// 対策: アンカー点がテクスチャの**中央**へ来るよう透明の余白を足し、SDK には常に
    /// 中央アンカー（オフセット 0）を渡す。オフセットが 0 ならどの空間で適用されようと
    /// 回転のしようがない。既定のピン（アンカー下端中央）なら高さが 2 倍のテクスチャになる。
    /// 縦の引き伸ばしも中央＝アンカー点を動かさないまま効く。
    ///
    /// できたテクスチャはアイコンごとにキャッシュする。同じアイコンのマーカーが何万個
    /// あってもテクスチャは 1 枚で済む。
    private func paddedTexture(for icon: BitmapIcon) -> PaddedTexture? {
        if let cached = textureCache[icon] { return cached }

        let source = icon.bitmap
        let anchorX = icon.anchor.x
        let anchorY = icon.anchor.y
        let sourceSize = source.size
        guard sourceSize.width > 0, sourceSize.height > 0 else { return nil }

        let paddedSize = CGSize(
            width: 2.0 * max(anchorX, 1.0 - anchorX) * sourceSize.width,
            height: 2.0 * max(anchorY, 1.0 - anchorY) * sourceSize.height
        )
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = source.scale
        format.opaque = false
        let paddedImage = UIGraphicsImageRenderer(size: paddedSize, format: format).image { _ in
            source.draw(
                at: CGPoint(
                    x: paddedSize.width / 2.0 - anchorX * sourceSize.width,
                    y: paddedSize.height / 2.0 - anchorY * sourceSize.height
                )
            )
        }
        guard let cgImage = paddedImage.cgImage, let texture = try? TextureHolder(cgImage) else { return nil }

        // 大きさは**物理ピクセル**で渡す（線幅と同じ）。`BitmapIcon.size` はポイントなので
        // 画面倍率を掛ける。掛け忘れると Retina で半分の大きさになる。
        let displayScale = Double(UIScreen.main.scale)
        let padded = PaddedTexture(
            texture: texture,
            width: Double(icon.size.width) * Double(paddedSize.width / sourceSize.width) * displayScale,
            height: Double(icon.size.height) * Double(paddedSize.height / sourceSize.height) * displayScale
        )
        textureCache[icon] = padded
        return padded
    }
}

/// ``OpenMobileMapsMarkerOverlayRenderer/paddedTexture(for:)`` の結果。大きさは表示ピクセル。
private struct PaddedTexture {
    let texture: TextureHolder
    let width: Double
    let height: Double
}

// ── コントローラ ──────────────────────────────────────────────────────────

/// マーカーのコントローラ。
///
/// 差分の計算・アニメーションの保持・ドラッグ状態はコアの ``AbstractMarkerController`` が
/// 持つ。ここに残るのは**当たり判定**（SDK のヒットテストを使わないため）と、吹き出しの
/// 追従だけ。
///
/// ## SDK のヒットテストを使わない
///
/// アイコンレイヤは `setLayerClickable(false)` にしてある（``OpenMobileMapsLayers`` を参照）。
/// SDK 側に取らせるとカスケードの順序も `clickable = false` の透過も効かなくなるため、
/// 他プロバイダと同じくコアの ``MarkerHitTest`` で判定する。
@MainActor
final class OpenMobileMapsMarkerController:
    AbstractMarkerController<OpenMobileMapsActualMarker, OpenMobileMapsMarkerOverlayRenderer> {
    private weak var holder: OpenMobileMapsMapViewHolder?
    private let defaultIcon: any MarkerIconProtocol = DefaultMarkerIcon()
    private let defaultIconForTiling: BitmapIcon = DefaultMarkerIcon().toBitmapIcon()

    /// マーカーが動いたときに吹き出しの位置も追従させる。
    var onUpdateInfoBubble: ((String) -> Void)?

    /// タイル方式の設定。ビューが `MapViewContent` から流し込む。
    var tilingOptions: MarkerTilingOptions = .Default

    /// タイル用のラスターレイヤの出し入れ。地図コントローラが繋ぐ。
    ///
    /// ここを繋がないと**タイル方式のマーカーは 1 つも表示されない**（タイルは
    /// ラスターレイヤとして地図に載るため）。
    var rasterLayerCallback: ((RasterLayerState?) -> Void)?

    private let tileServer = TileServerRegistry.get()
    private var tileRenderer: MarkerTileRenderer<OpenMobileMapsActualMarker>?
    private var tileRouteId: String?
    private var tileRasterLayerState: RasterLayerState?
    private var tiledMarkerIds: Set<String> = []
    /// タイルの張り替えごとに増やす。URL に混ぜてキャッシュを外すため。
    private var tileGeneration: Int = 0

    init(holder: OpenMobileMapsMapViewHolder, iconLayer: MCIconLayerInterface?) {
        self.holder = holder
        let markerManager = MarkerManager<OpenMobileMapsActualMarker>.defaultManager()
        super.init(
            markerManager: markerManager,
            renderer: OpenMobileMapsMarkerOverlayRenderer(
                markerManager: markerManager,
                iconLayer: iconLayer,
                surface: holder.mapView
            )
        )
    }

    // MARK: - タイル方式

    /*
     * マーカーが多いときは、ネイティブのアイコンをやめて**ラスタータイルとして焼く**。
     *
     * ```
     * ingest → tiledMarkerIds へ振り分け
     *        → MarkerTileRenderer がタイルを描く
     *        → ローカルタイルサーバに登録
     *        → RasterLayerState として rasterLayerCallback へ渡す
     *        → OpenMobileMapsRasterLayerController が地図へ載せる
     * ```
     *
     * android-for-openmobilemaps / ios-for-here と同じ構造。この SDK に固有の注意は
     * **空タイルの 404 をそのまま渡すと親タイルが透けて残る**ことで、その始末は
     * ``OpenMobileMapsTileLoader`` が受け持つ。
     */

    override func add(data: [MarkerState]) async {
        guard tilingOptions.enabled else {
            await super.add(data: data)
            removeTileOverlay()
            return
        }

        let shouldTileMarkers = data.count >= tilingOptions.minMarkerCount
        var localTiledMarkerIds = tiledMarkerIds
        let result = await MarkerIngestionEngine.ingest(
            data: data,
            markerManager: markerManager,
            renderer: renderer,
            defaultMarkerIcon: defaultIconForTiling,
            tilingEnabled: tilingOptions.enabled,
            tiledMarkerIds: &localTiledMarkerIds,
            shouldTile: { state in
                // ドラッグ中／アニメーション中のマーカーはタイルに焼けない
                // （タイルは動かせないので、指に追従しなくなる）。
                shouldTileMarkers && !state.draggable && state.getAnimation() == nil
            }
        )
        tiledMarkerIds = localTiledMarkerIds
        await restoreNativeMarkersIfNeeded(states: data)
        await renderer.onPostProcess()

        if result.tiledDataChanged {
            refreshTiles(hasTiledMarkers: result.hasTiledMarkers)
        } else if result.hasTiledMarkers {
            if tileRasterLayerState == nil { refreshTiles(hasTiledMarkers: true) }
        } else {
            removeTileOverlay()
        }
    }

    /// タイル担当から外れた entity にネイティブのアイコンを戻す。
    ///
    /// `ingest` はタイル担当を `marker == nil` で登録するので、降格したときに
    /// ここで作り直さないと**そのマーカーだけ消えたまま**になる。
    private func restoreNativeMarkersIfNeeded(states: [MarkerState]) async {
        var added: [MarkerOverlayAddParams] = []
        for state in states where !tiledMarkerIds.contains(state.id) {
            guard let entity = markerManager.getEntity(state.id), entity.marker == nil else { continue }
            added.append(MarkerOverlayAddParams(
                state: state,
                bitmapIcon: state.icon?.toBitmapIcon() ?? defaultIconForTiling
            ))
        }
        guard !added.isEmpty else { return }

        let markers = await renderer.onAdd(data: added)
        for (index, marker) in markers.enumerated() {
            guard let marker else { continue }
            markerManager.updateEntity(MarkerEntity(
                marker: marker,
                state: added[index].state,
                visible: true,
                isRendered: true
            ))
        }
    }

    override func update(state: MarkerState) async {
        guard tilingOptions.enabled else {
            await super.update(state: state)
            return
        }
        guard let prevEntity = markerManager.getEntity(state.id) else { return }
        if state.fingerPrint() == prevEntity.fingerPrint { return }

        let tilingEnabled = markerManager.allEntities().count >= tilingOptions.minMarkerCount
        let wantsTiled = tilingEnabled && !state.draggable && state.getAnimation() == nil
        let wasTiled = tiledMarkerIds.contains(state.id)

        if wantsTiled {
            if !wasTiled {
                if prevEntity.marker != nil { await renderer.onRemove(data: [prevEntity]) }
                tiledMarkerIds.insert(state.id)
            }
            markerManager.updateEntity(MarkerEntity(
                marker: nil,
                state: state,
                visible: prevEntity.visible,
                isRendered: true,
                // tiling を立てないと MarkerTileRenderer の絞り込みから漏れ、
                // タイル昇格したのにタイルへ描かれないマーカーになる。
                tiling: true
            ))
            await renderer.onPostProcess()
            refreshTiles(hasTiledMarkers: true)
            return
        }

        if wasTiled { tiledMarkerIds.remove(state.id) }
        await super.update(state: state)
        refreshTiles(hasTiledMarkers: !tiledMarkerIds.isEmpty)
    }

    override func clear() async {
        await super.clear()
        tiledMarkerIds.removeAll()
        removeTileOverlay()
    }

    /// タイルを描き直して、ラスターレイヤの URL を差し替える。
    ///
    /// 世代番号を URL に混ぜるのは、同じ URL のままだとタイルのキャッシュが効いて
    /// **マーカーを足しても絵が変わらない**ため。
    private func refreshTiles(hasTiledMarkers: Bool) {
        guard hasTiledMarkers else {
            removeTileOverlay()
            return
        }
        let tileRenderer = getOrCreateTileRenderer()
        tileRenderer.invalidate()
        guard let routeId = tileRouteId else { return }

        tileGeneration += 1
        let state = RasterLayerState(
            source: .urlTemplate(
                // URL には**焼く画素数**（3x なら 768）を、レイヤには**割り付けの単位**
                // （256）を渡す。@2x/@3x タイルの通常の約束で、ios-for-maplibre と同じ。
                // ここを両方 768 にすると 1 タイルが覆う地面が変わり、**マーカーが
                // 3 倍の大きさで並ぶ**。
                template: tileServer.urlTemplate(
                    routeId: routeId,
                    tileSize: tileRenderer.tileSize,
                    cacheKey: String(tileGeneration)
                ),
                tileSize: RasterLayerSource.defaultTileSize,
                minZoom: 0,
                maxZoom: 22,
                attributionRules: [],
                scheme: .XYZ
            ),
            opacity: 1.0,
            visible: true,
            id: "\(OpenMobileMapsMapViewController.markerTileIdPrefix)\(routeId)"
        )
        tileRasterLayerState = state
        rasterLayerCallback?(state)
    }

    private func getOrCreateTileRenderer() -> MarkerTileRenderer<OpenMobileMapsActualMarker> {
        if let tileRenderer { return tileRenderer }
        let routeId = "mapconductor-markers-\(UUID().uuidString)"
        // タイルは物理ピクセルで焼く。256 のままだと Retina でぼける。
        let contentScale = Double(UIScreen.main.scale)
        let baseCallback = tilingOptions.iconScaleCallback
        let created = MarkerTileRenderer<OpenMobileMapsActualMarker>(
            markerManager: markerManager,
            tileSize: RasterLayerSource.defaultTileSize * max(1, Int(UIScreen.main.scale)),
            cacheSizeBytes: tilingOptions.cacheSize,
            debugTileOverlay: tilingOptions.debugTileOverlay,
            // 画素数を増やしたぶんアイコンも大きく描く。そうしないと 1/3 の大きさになる。
            iconScaleCallback: { state, zoom in
                (baseCallback?(state, zoom) ?? 1.0) * contentScale
            }
        )
        tileServer.register(routeId: routeId, provider: created)
        tileRenderer = created
        tileRouteId = routeId
        return created
    }

    private func removeTileOverlay() {
        // タイルサーバはプロセス共有のシングルトン。**stop してはいけない**
        // （他の地図やオーバーレイ拡張のタイルまで止まる）。自分の経路だけ外す。
        if let tileRouteId { tileServer.unregister(routeId: tileRouteId) }
        tileRouteId = nil
        tileRenderer = nil
        guard tileRasterLayerState != nil else { return }
        tileRasterLayerState = nil
        rasterLayerCallback?(nil)
    }

    func getMarkerState(for id: String) -> MarkerState? {
        markerManager.getEntity(id)?.state
    }

    /// 画面座標にあるマーカー。重なっているときはアンカーが近いほうを選ぶ。
    ///
    /// 受け取るのは**入れ物（`OpenMobileMapsMapSurface`）の座標**。ホルダーの
    /// `toScreenOffset` も入れ物の座標へ畳んで返すので、両者は同じ系で比べられる。
    func markerId(atScreenPoint point: CGPoint, where isEligible: (MarkerState) -> Bool) -> String? {
        guard let holder else { return nil }
        var bestId: String?
        var bestDistance = CGFloat.infinity
        for entity in markerManager.allEntities() where isEligible(entity.state) {
            guard let screen = holder.toScreenOffset(position: entity.state.position) else { continue }
            guard MarkerHitTest.hitsIcon(
                touchScreen: point,
                markerScreen: screen,
                state: entity.state,
                defaultIcon: defaultIcon
            ) else { continue }
            let distance = hypot(point.x - screen.x, point.y - screen.y)
            if distance < bestDistance {
                bestDistance = distance
                bestId = entity.state.id
            }
        }
        return bestId
    }

    func unbind() {
        removeTileOverlay()
        renderer.unbind()
        holder = nil
        destroy()
    }
}

// ── F. ドラッグ ───────────────────────────────────────────────────────────

/// マーカーのタップとドラッグ。状態遷移・パン抑止・掴む前の値への復元はコアの
/// ``DefaultMarkerEventController`` が持つ。ここは UIKit のジェスチャを写すだけ。
@MainActor
final class OpenMobileMapsMarkerEventController: DefaultMarkerEventController {
    init(holder: OpenMobileMapsMapViewHolder, markerController: OpenMobileMapsMarkerController) {
        super.init(
            surface: OpenMobileMapsMarkerDragSurface(holder: holder),
            host: OpenMobileMapsMarkerEventHost(markerController: markerController)
        )
    }

    /// UIKit のジェスチャをコアの状態へ写す。
    func handleLongPress(_ recognizer: UILongPressGestureRecognizer, in view: UIView) -> Bool {
        handleLongPress(state: MarkerDragGestureState(recognizer.state), at: recognizer.location(in: view))
    }
}

/// 実装点 F。ドラッグ中だけ地図のパンを止める面。
///
/// ## この SDK には「パンだけ止める」API が無い
///
/// `MCMapCameraInterface` にあるのは `setRotationEnabled` だけで、パンやズームを個別に
/// 切ることはできない（``OpenMobileMapsCapabilities`` で `gestureScroll` を非対応と
/// 宣言してあるのはそのため）。代わりに**内側の `MCMapView` のタッチそのもの**を切る。
///
/// 切ると進行中のタッチには `touchesCancelled` が届くので、掴む直前に始まっていた慣性も
/// 一緒に止まる。android で `setTouchEnabled(false)` を使っているのと同じ意図。
@MainActor
private final class OpenMobileMapsMarkerDragSurface: MarkerDragSurface {
    private weak var holder: OpenMobileMapsMapViewHolder?

    init(holder: OpenMobileMapsMapViewHolder) { self.holder = holder }

    var isScrollEnabled: Bool {
        get { holder?.mapView.mapView?.isUserInteractionEnabled ?? true }
        set { holder?.mapView.mapView?.isUserInteractionEnabled = newValue }
    }

    /// **入れ物の座標**で受け取り、内側の座標へ畳んでから逆投影する。
    /// ジェスチャ認識器は入れ物に付けてあるので、届く座標は入れ物の系である。
    func geoPoint(atScreenPoint point: CGPoint) -> GeoPoint? {
        holder?.fromScreenOffsetSync(offset: point)
    }
}

/// ``OpenMobileMapsMarkerController`` をコアの ``MarkerEventHostProtocol`` へ橋渡しする。
///
/// **`markerController` は weak で持つこと。** コントローラ側がイベントコントローラを
/// 強参照しているので、ここを強参照にすると循環する。
@MainActor
private final class OpenMobileMapsMarkerEventHost: MarkerEventHostProtocol {
    private weak var markerController: OpenMobileMapsMarkerController?

    init(markerController: OpenMobileMapsMarkerController) { self.markerController = markerController }

    func markerId(atScreenPoint point: CGPoint) -> String? {
        // clickable / draggable の判定はコアがこのあと行う。ここでは「アイコンに
        // 当たっているか」だけを見る（当たり判定と可否を混ぜると、重なった
        // clickable と draggable のどちらを選ぶかがプロバイダごとに変わる）。
        markerController?.markerId(atScreenPoint: point) { _ in true }
    }

    func markerState(for id: String) -> MarkerState? {
        markerController?.getMarkerState(for: id)
    }

    /// タイル方式で描かれたマーカーのタップ。**このドライバーでは常に false でよい。**
    ///
    /// 他プロバイダはネイティブのシンボルを SDK のヒットテストで引くので、タイルに
    /// 焼かれたマーカー（シンボルを持たない）は引けず、この別経路が要る。
    /// こちらは ``markerId(atScreenPoint:)`` が**マネージャの座標を投影して**判定しており、
    /// タイル担当かどうかに関係なく当たるため、上の経路で既に配送済みになる。
    func handleTiledMarkerTap(atScreenPoint _: CGPoint) -> Bool { false }

    func dispatchClick(state: MarkerState) { markerController?.dispatchClick(state: state) }
    func dispatchDragStart(state: MarkerState) { markerController?.dispatchDragStart(state: state) }
    func dispatchDrag(state: MarkerState) { markerController?.dispatchDrag(state: state) }
    func dispatchDragEnd(state: MarkerState) { markerController?.dispatchDragEnd(state: state) }
    func onUpdateInfoBubble(_ markerId: String) { markerController?.onUpdateInfoBubble?(markerId) }
}

private extension MarkerDragGestureState {
    init(_ state: UIGestureRecognizer.State) {
        switch state {
        case .began: self = .began
        case .changed: self = .changed
        case .ended: self = .ended
        case .cancelled, .failed: self = .cancelled
        default: self = .other
        }
    }
}
