import Combine
import Foundation
import MapConductorCore
import MapConductorTileServer

public final class HeatmapOverlay: ObservableObject {
    public let rasterLayerState: RasterLayerState
    public let pointCollector: HeatmapPointCollector
    public let renderer: HeatmapTileRenderer
    public let cameraController: HeatmapCameraController

    public var radiusPx: Int {
        didSet { scheduleUpdate() }
    }

    public var opacity: Double {
        didSet {
            rasterLayerState.opacity = clampOpacity(opacity)
        }
    }

    public var gradient: HeatmapGradient {
        didSet { scheduleUpdate() }
    }

    public var maxIntensity: Double? {
        didSet { scheduleUpdate() }
    }

    public var weightProvider: (HeatmapPointState) -> Double {
        didSet { scheduleUpdate() }
    }

    private let groupId: String
    private let tileServer: LocalTileServer
    private var version: Int64 = 0
    private var cancellables: Set<AnyCancellable> = []
    private let updateQueue = DispatchQueue(label: "MapConductorHeatmapOverlay")
    private var explicitPoints: [HeatmapPoint]?
    private var lastPointsFingerprint: Int?

    public init(
        radiusPx: Int = HeatmapDefaults.defaultRadiusPx,
        opacity: Double = HeatmapDefaults.defaultOpacity,
        gradient: HeatmapGradient = .default,
        maxIntensity: Double? = nil,
        weightProvider: @escaping (HeatmapPointState) -> Double = HeatmapOverlay.defaultWeightProvider
    ) {
        let initialOpacity = min(1.0, max(0.0, opacity))
        self.radiusPx = radiusPx
        self.opacity = opacity
        self.gradient = gradient
        self.maxIntensity = maxIntensity
        self.weightProvider = weightProvider
        self.groupId = UUID().uuidString
        self.tileServer = TileServerRegistry.get()
        self.renderer = HeatmapTileRenderer()
        self.cameraController = HeatmapCameraController(renderer: renderer)
        self.pointCollector = HeatmapPointCollector()

        self.rasterLayerState = RasterLayerState(
            source: RasterSource.urlTemplate(
                template: tileServer.urlTemplate(routeId: groupId, version: version),
                tileSize: renderer.tileSize,
                scheme: .XYZ
            ),
            opacity: initialOpacity,
            visible: true,
            id: "heatmap-\(groupId)",
            extra: version
        )

        tileServer.register(routeId: groupId, provider: renderer)

        pointCollector.flow
            .debounce(for: .milliseconds(50), scheduler: updateQueue)
            .sink { [weak self] _ in
                self?.scheduleUpdate()
            }
            .store(in: &cancellables)
    }

    deinit {
        tileServer.unregister(routeId: groupId)
    }

    public func onCameraChanged(_ cameraPosition: MapCameraPosition) {
        Task { [weak self] in
            await self?.cameraController.onCameraChanged(mapCameraPosition: cameraPosition)
        }
    }

    public func setPoints(_ points: [HeatmapPoint]) {
        updatePointsIfNeeded(points)
    }

    public func updatePointsIfNeeded(_ points: [HeatmapPoint]) {
        updateQueue.async { [weak self] in
            guard let self else { return }
            let fingerprint = HeatmapOverlay.pointsFingerprint(points)
            if self.lastPointsFingerprint == fingerprint {
                return
            }
            self.lastPointsFingerprint = fingerprint
            self.explicitPoints = points
            self.applyUpdate()
        }
    }

    private func scheduleUpdate() {
        updateQueue.async { [weak self] in
            self?.applyUpdate()
        }
    }

    private func applyUpdate() {
        let points: [HeatmapPoint]
        if let explicitPoints {
            points = explicitPoints
        } else {
            points = pointCollector.flow.value.values.compactMap { state -> HeatmapPoint? in
                let weight = weightProvider(state)
                guard !weight.isNaN, weight > 0.0 else { return nil }
                return HeatmapPoint(position: state.position, weight: weight)
            }
        }

        renderer.update(
            points: points,
            radiusPx: max(1, radiusPx),
            gradient: gradient,
            maxIntensity: maxIntensity
        )

        version += 1
        rasterLayerState.source = RasterSource.urlTemplate(
            template: tileServer.urlTemplate(routeId: groupId, version: version),
            tileSize: renderer.tileSize,
            scheme: .XYZ
        )
        rasterLayerState.extra = version
    }

    private func clampOpacity(_ value: Double) -> Double {
        min(1.0, max(0.0, value))
    }

    public static let defaultWeightProvider: (HeatmapPointState) -> Double = { state in
        let weight = state.weight
        if weight.isNaN { return 1.0 }
        return weight
    }

    private static func pointsFingerprint(_ points: [HeatmapPoint]) -> Int {
        var result: Int32 = 0
        for point in points {
            result = result &* 31 &+ Int32(truncatingIfNeeded: javaHash(point.position.latitude))
            result = result &* 31 &+ Int32(truncatingIfNeeded: javaHash(point.position.longitude))
            result = result &* 31 &+ Int32(truncatingIfNeeded: javaHash(point.weight))
        }
        return Int(result)
    }
}

private func javaHash(_ value: Double) -> Int {
    let bits = value.bitPattern
    let combined = bits ^ (bits >> 32)
    return Int(Int32(truncatingIfNeeded: combined))
}
