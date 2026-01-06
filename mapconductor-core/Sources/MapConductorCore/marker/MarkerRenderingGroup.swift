public struct MarkerRenderingGroup<ActualMarker>: MapOverlayItemProtocol {
    public let strategy: AnyMarkerRenderingStrategy<ActualMarker>
    public let markers: [MarkerState]

    public init<Strategy: MarkerRenderingStrategyProtocol>(
        strategy: Strategy,
        markers: [MarkerState]
    ) where Strategy.ActualMarker == ActualMarker {
        self.strategy = AnyMarkerRenderingStrategy(strategy)
        self.markers = markers
    }

    public func append(to content: inout MapViewContent) {
        content.markerRenderingStrategy = strategy
        content.markerRenderingMarkers = markers
    }
}
