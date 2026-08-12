import Combine
import Foundation
import MapConductorCore

public final class KMLLayerState: ObservableObject {
    let rasterLayerState: RasterLayerState
    let renderer: KMLTileRenderer

    public var onClick: ((KMLFeature, GeoPoint) -> Void)?
    public var onLoadStart: (() -> Void)?
    public var onLoadComplete: ((Error?) -> Void)?

    public var opacity: Double {
        didSet { rasterLayerState.opacity = min(1.0, max(0.0, opacity)) }
    }

    public var minZoom: Int {
        didSet { scheduleUpdate() }
    }

    public var maxZoom: Int {
        didSet { scheduleUpdate() }
    }

    public var layerStyle: KMLTileRenderer.LayerStyle {
        didSet { scheduleUpdate() }
    }

    public var styleProvider: any KMLStyleProvider {
        didSet { scheduleUpdate() }
    }

    private let groupId: String
    private let tileServer: LocalTileServer
    private var version: Int64 = 0
    private var lastFeatures: [KMLFeature] = []
    private let updateQueue = DispatchQueue(label: "MapConductorKMLLayer")
    private var featureStateCancellables: [AnyCancellable] = []

    public init(
        tileSize: Int = KMLDefaults.defaultTileSize,
        opacity: Double = KMLDefaults.defaultOpacity,
        minZoom: Int = 0,
        maxZoom: Int = KMLDefaults.defaultMaxZoom,
        layerStyle: KMLTileRenderer.LayerStyle = KMLTileRenderer.LayerStyle(),
        styleProvider: any KMLStyleProvider = DefaultKMLStyleProvider.shared,
        onLoadStart: (() -> Void)? = nil,
        onLoadComplete: ((Error?) -> Void)? = nil,
        onClick: ((KMLFeature, GeoPoint) -> Void)? = nil
    ) {
        let initialOpacity = min(1.0, max(0.0, opacity))
        self.opacity = opacity
        self.minZoom = minZoom
        self.maxZoom = maxZoom
        self.layerStyle = layerStyle
        self.styleProvider = styleProvider
        self.onLoadStart = onLoadStart
        self.onLoadComplete = onLoadComplete
        self.onClick = onClick
        self.groupId = UUID().uuidString
        self.tileServer = TileServerRegistry.get(forceNoStoreCache: false)
        self.renderer = KMLTileRenderer(tileSize: tileSize)

        self.rasterLayerState = RasterLayerState(
            source: RasterLayerSource.urlTemplate(
                template: tileServer.urlTemplate(routeId: groupId, tileSize: tileSize, cacheKey: "0"),
                tileSize: tileSize,
                minZoom: minZoom,
                maxZoom: maxZoom,
                scheme: .XYZ
            ),
            opacity: initialOpacity,
            visible: false,
            id: "kml-\(groupId)"
        )

        tileServer.register(routeId: groupId, provider: renderer)
    }

    deinit {
        tileServer.unregister(routeId: groupId)
    }

    public func setFeatures(_ features: [KMLFeature]) {
        beginLoading()
        updateQueue.async { [weak self] in
            guard let self else { return }
            self.lastFeatures = features
            self.applyUpdate(features: features)
        }
    }

    public func beginLoading() {
        DispatchQueue.main.async { [weak self] in
            self?.onLoadStart?()
        }
    }

    public func completeLoading(error: Error? = nil) {
        DispatchQueue.main.async { [weak self] in
            self?.onLoadComplete?(error)
        }
    }

    public func setFeatures(_ states: [KMLFeatureState]) {
        featureStateCancellables.removeAll()
        let features = states.map { $0.toFeature() }
        setFeatures(features)
        let publisher = Publishers.MergeMany(states.map { $0.asPublisher() })
            .debounce(for: .milliseconds(Settings.Default.composeEventDebounce), scheduler: updateQueue)
            .sink { [weak self] _ in
                guard let self else { return }
                self.beginLoading()
                let updated = states.map { $0.toFeature() }
                self.lastFeatures = updated
                self.applyUpdate(features: updated)
            }
        featureStateCancellables.append(publisher)
    }

    /// Call from your map's click handler to perform feature hit-testing.
    ///
    /// Pass `pixelTolerance` and `zoom` to use a pixel-based hit threshold instead of the
    /// default world-coordinate tolerances. For example,
    /// `processClick(geoPoint: point, pixelTolerance: 15, zoom: zoom)` fires only when
    /// the click is within 15 pixels of the nearest segment.
    public func processClick(geoPoint: GeoPoint, pixelTolerance: Double? = nil, zoom: Double? = nil) {
        var lineTolSq: Double?
        var pointTolSq: Double?
        if let px = pixelTolerance, let z = zoom {
            let worldSize = Double(renderer.tileSize) * pow(2.0, z)
            let lt = px / worldSize
            let pt = px * 2.0 / worldSize
            lineTolSq = lt * lt
            pointTolSq = pt * pt
        }
        let hit = renderer.hitTest(
            longitude: geoPoint.longitude,
            latitude: geoPoint.latitude,
            lineTolSq: lineTolSq,
            pointTolSq: pointTolSq
        )
        guard let hit else { return }
        onClick?(hit.feature, hit.position)
    }

    private func scheduleUpdate() {
        beginLoading()
        updateQueue.async { [weak self] in
            guard let self else { return }
            self.applyUpdate(features: self.lastFeatures)
        }
    }

    private func applyUpdate(features: [KMLFeature]) {
        renderer.update(
            features: features,
            layerStyle: layerStyle,
            styleProvider: styleProvider
        )
        version += 1
        let nextVersion = version
        let tileSize = renderer.tileSize
        let nextSource = RasterLayerSource.urlTemplate(
            template: tileServer.urlTemplate(routeId: groupId, tileSize: tileSize, cacheKey: String(nextVersion)),
            tileSize: tileSize,
            minZoom: minZoom,
            maxZoom: maxZoom,
            scheme: .XYZ
        )
        let shouldShowLayer = !features.isEmpty
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.rasterLayerState.source = nextSource
            self.rasterLayerState.visible = shouldShowLayer
            self.onLoadComplete?(nil)
        }
    }
}
