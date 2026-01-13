import MapConductorCore

private let markerClusterGroupClusterCircleIdPrefix = "cluster-circle-"

/// Android SDKの`MarkerClusterGroup`に合わせた、iOS側の薄いラッパーです。
public struct MarkerClusterGroup<ActualMarker>: MapOverlayItemProtocol {
    public let strategy: AnyMarkerRenderingStrategy<ActualMarker>
    public let markers: [MarkerState]
    private let overlayContent: MapViewContent

    public init(
        strategy: MarkerClusterStrategy<ActualMarker>,
        markers: [MarkerState]
    ) {
        self.strategy = AnyMarkerRenderingStrategy(strategy)
        self.markers = markers
        self.overlayContent = MapViewContent()
    }

    public init(
        state: MarkerClusterGroupState<ActualMarker>,
        markers: [MarkerState]
    ) {
        self.strategy = AnyMarkerRenderingStrategy(state.strategy)
        self.markers = markers
        self.overlayContent = MapViewContent()
    }

    public init(
        clusterRadiusPx: Double = MarkerClusterStrategy<ActualMarker>.DEFAULT_CLUSTER_RADIUS_PX,
        minClusterSize: Int = MarkerClusterStrategy<ActualMarker>.DEFAULT_MIN_CLUSTER_SIZE,
        expandMargin: Double = MarkerClusterStrategy<ActualMarker>.DEFAULT_EXPAND_MARGIN,
        clusterIconProvider: @escaping MarkerClusterStrategy<ActualMarker>.ClusterIconProvider = MarkerClusterStrategy<ActualMarker>.defaultIconProvider,
        clusterIconProviderWithTurn: MarkerClusterStrategy<ActualMarker>.ClusterIconProviderWithTurn? = nil,
        onClusterClick: ((MarkerCluster) -> Void)? = nil,
        enableZoomAnimation: Bool = false,
        enablePanAnimation: Bool = false,
        zoomAnimationDurationMillis: Int = MarkerClusterStrategy<ActualMarker>.DEFAULT_ZOOM_ANIMATION_DURATION_MILLIS,
        cameraIdleDebounceMillis: Int = MarkerClusterStrategy<ActualMarker>.DEFAULT_CAMERA_DEBOUNCE_MILLIS,
        tileSize: Double = MarkerClusterStrategy<ActualMarker>.DEFAULT_TILE_SIZE,
        @MapViewContentBuilder content: () -> MapViewContent
    ) {
        self.init(
            strategy: MarkerClusterStrategy(
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
            ),
            content: content
        )
    }

    public init(
        strategy: MarkerClusterStrategy<ActualMarker>,
        @MapViewContentBuilder content: () -> MapViewContent
    ) {
        let inner = content()
        var seenIds = Set<String>()
        let markerStates =
            (inner.markerRenderingMarkers + inner.markers.map(\.state))
            .filter { seenIds.insert($0.id).inserted }

        self.strategy = AnyMarkerRenderingStrategy(strategy)
        self.markers = markerStates

        var passthrough = inner
        passthrough.markers = []
        passthrough.markerRenderingStrategy = nil
        passthrough.markerRenderingMarkers = []
        self.overlayContent = passthrough
    }

    public init(
        state: MarkerClusterGroupState<ActualMarker>,
        @MapViewContentBuilder content: () -> MapViewContent
    ) {
        let inner = content()
        var seenIds = Set<String>()
        let markerStates =
            (inner.markerRenderingMarkers + inner.markers.map(\.state))
            .filter { seenIds.insert($0.id).inserted }

        self.strategy = AnyMarkerRenderingStrategy(state.strategy)
        self.markers = markerStates

        var passthrough = inner
        passthrough.markers = []
        passthrough.markerRenderingStrategy = nil
        passthrough.markerRenderingMarkers = []

        if state.showClusterRadiusCircle {
            let circles = state.debugInfos.map { info in
                Circle(
                    center: info.center,
                    radiusMeters: info.radiusMeters,
                    geodesic: true,
                    clickable: false,
                    strokeColor: state.clusterRadiusStrokeColor,
                    strokeWidth: state.clusterRadiusStrokeWidth,
                    fillColor: state.clusterRadiusFillColor,
                    id: "\(markerClusterGroupClusterCircleIdPrefix)\(info.id)",
                    zIndex: nil,
                    extra: info,
                    onClick: nil
                )
            }
            passthrough.circles.append(contentsOf: circles)
        }

        self.overlayContent = passthrough
    }

    public func append(to content: inout MapViewContent) {
        content.infoBubbles.append(contentsOf: overlayContent.infoBubbles)
        content.polylines.append(contentsOf: overlayContent.polylines)
        content.polygons.append(contentsOf: overlayContent.polygons)
        content.circles.append(contentsOf: overlayContent.circles)
        content.rasterLayers.append(contentsOf: overlayContent.rasterLayers)
        content.views.append(contentsOf: overlayContent.views)
        content.markerRenderingStrategy = strategy
        content.markerRenderingMarkers = markers
    }
}
