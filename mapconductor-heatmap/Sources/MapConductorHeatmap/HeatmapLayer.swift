import MapConductorCore

public struct HeatmapLayer: MapOverlayItemProtocol, Identifiable {
    public let id: String
    public let overlay: HeatmapOverlay

    public init(
        overlay: HeatmapOverlay,
        points: [HeatmapPoint] = []
    ) {
        self.overlay = overlay
        self.overlay.updatePointsIfNeeded(points)
        self.id = overlay.rasterLayerState.id
    }

    public init(
        points: [HeatmapPoint],
        radiusPx: Int = HeatmapDefaults.defaultRadiusPx,
        opacity: Double = HeatmapDefaults.defaultOpacity,
        gradient: HeatmapGradient = .default,
        maxIntensity: Double? = nil,
        weightProvider: @escaping (HeatmapPointState) -> Double = HeatmapOverlay.defaultWeightProvider
    ) {
        let overlay = HeatmapOverlay(
            radiusPx: radiusPx,
            opacity: opacity,
            gradient: gradient,
            maxIntensity: maxIntensity,
            weightProvider: weightProvider
        )
        overlay.updatePointsIfNeeded(points)
        self.overlay = overlay
        self.id = overlay.rasterLayerState.id
    }

    public func append(to content: inout MapViewContent) {
        content.rasterLayers.append(RasterLayer(state: overlay.rasterLayerState))
    }
}
