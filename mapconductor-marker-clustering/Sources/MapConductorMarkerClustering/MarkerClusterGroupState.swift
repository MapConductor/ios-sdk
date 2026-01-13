import Combine
import MapConductorCore
import UIKit

/// Android SDK の `MarkerClusterGroupState` に対応する iOS 側の State コンテナです。
/// `MarkerClusterStrategy` を内部で保持し、設定変更時に作り直します。
public final class MarkerClusterGroupState<ActualMarker>: ObservableObject {
    public typealias ClusterIconProvider = MarkerClusterStrategy<ActualMarker>.ClusterIconProvider
    public typealias ClusterIconProviderWithTurn = MarkerClusterStrategy<ActualMarker>.ClusterIconProviderWithTurn

    @Published public var clusterRadiusPx: Double { didSet { rebuildStrategy() } }
    @Published public var minClusterSize: Int { didSet { rebuildStrategy() } }
    @Published public var expandMargin: Double { didSet { rebuildStrategy() } }
    @Published public var clusterIconProvider: ClusterIconProvider { didSet { rebuildStrategy() } }
    @Published public var clusterIconProviderWithTurn: ClusterIconProviderWithTurn? { didSet { rebuildStrategy() } }
    @Published public var onClusterClick: ((MarkerCluster) -> Void)? { didSet { rebuildStrategy() } }
    @Published public var enableZoomAnimation: Bool { didSet { rebuildStrategy() } }
    @Published public var enablePanAnimation: Bool { didSet { rebuildStrategy() } }
    @Published public var zoomAnimationDurationMillis: Int { didSet { rebuildStrategy() } }
    @Published public var cameraIdleDebounceMillis: Int { didSet { rebuildStrategy() } }
    @Published public var tileSize: Double { didSet { rebuildStrategy() } }

    @Published public var showClusterRadiusCircle: Bool = false
    @Published public var clusterRadiusStrokeColor: UIColor = .red
    @Published public var clusterRadiusStrokeWidth: Double = 1.0
    @Published public var clusterRadiusFillColor: UIColor = .clear
    @Published public private(set) var debugInfos: [MarkerClusterDebugInfo] = []

    public private(set) var strategy: MarkerClusterStrategy<ActualMarker>
    private var debugInfoCancellable: AnyCancellable?

    public init(
        clusterRadiusPx: Double = MarkerClusterStrategy<ActualMarker>.DEFAULT_CLUSTER_RADIUS_PX,
        minClusterSize: Int = MarkerClusterStrategy<ActualMarker>.DEFAULT_MIN_CLUSTER_SIZE,
        expandMargin: Double = MarkerClusterStrategy<ActualMarker>.DEFAULT_EXPAND_MARGIN,
        clusterIconProvider: @escaping ClusterIconProvider = MarkerClusterStrategy<ActualMarker>.defaultIconProvider,
        clusterIconProviderWithTurn: ClusterIconProviderWithTurn? = nil,
        onClusterClick: ((MarkerCluster) -> Void)? = nil,
        enableZoomAnimation: Bool = false,
        enablePanAnimation: Bool = false,
        zoomAnimationDurationMillis: Int = MarkerClusterStrategy<ActualMarker>.DEFAULT_ZOOM_ANIMATION_DURATION_MILLIS,
        cameraIdleDebounceMillis: Int = MarkerClusterStrategy<ActualMarker>.DEFAULT_CAMERA_DEBOUNCE_MILLIS,
        tileSize: Double = MarkerClusterStrategy<ActualMarker>.DEFAULT_TILE_SIZE
    ) {
        self.clusterRadiusPx = clusterRadiusPx
        self.minClusterSize = minClusterSize
        self.expandMargin = expandMargin
        self.clusterIconProvider = clusterIconProvider
        self.clusterIconProviderWithTurn = clusterIconProviderWithTurn
        self.onClusterClick = onClusterClick
        self.enableZoomAnimation = enableZoomAnimation
        self.enablePanAnimation = enablePanAnimation
        self.zoomAnimationDurationMillis = zoomAnimationDurationMillis
        self.cameraIdleDebounceMillis = cameraIdleDebounceMillis
        self.tileSize = tileSize

        self.strategy =
            MarkerClusterStrategy<ActualMarker>(
                clusterRadiusPx: clusterRadiusPx,
                minClusterSize: minClusterSize,
                expandMargin: expandMargin,
                clusterIconProvider: clusterIconProvider,
                clusterIconProviderWithTurn: clusterIconProviderWithTurn,
                onClusterClick: onClusterClick,
                enableZoomAnimation: enableZoomAnimation,
                enablePanAnimation: enablePanAnimation,
                zoomAnimationDurationMillis: zoomAnimationDurationMillis,
                cameraIdleDebounceMillis: cameraIdleDebounceMillis,
                tileSize: tileSize
            )
        bindDebugInfo()
    }

    private func rebuildStrategy() {
        strategy.clear()
        strategy =
            MarkerClusterStrategy<ActualMarker>(
                clusterRadiusPx: clusterRadiusPx,
                minClusterSize: minClusterSize,
                expandMargin: expandMargin,
                clusterIconProvider: clusterIconProvider,
                clusterIconProviderWithTurn: clusterIconProviderWithTurn,
                onClusterClick: onClusterClick,
                enableZoomAnimation: enableZoomAnimation,
                enablePanAnimation: enablePanAnimation,
                zoomAnimationDurationMillis: zoomAnimationDurationMillis,
                cameraIdleDebounceMillis: cameraIdleDebounceMillis,
                tileSize: tileSize
            )
        bindDebugInfo()
    }

    private func bindDebugInfo() {
        debugInfoCancellable = strategy.debugInfoFlow
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.debugInfos = $0
            }
    }
}
