import MapConductorCore

/// Android SDKの`MarkerClusterGroup`に合わせた、iOS側の薄いラッパーです。
/// 実体は`MarkerRenderingGroup`と同等で、`MarkerClusterStrategy`を指定して利用します。
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
        self.init(strategy: state.strategy, content: content)
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
