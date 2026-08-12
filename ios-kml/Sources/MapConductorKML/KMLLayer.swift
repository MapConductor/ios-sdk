import MapConductorCore
import SwiftUI

public struct KMLLayer: ViewBasedMapOverlay, Identifiable {
    public let id: String
    private let overlayState: KMLLayerState
    private let features: [KMLFeature]

    public init(
        _ state: KMLLayerState,
        features: [KMLFeature] = []
    ) {
        self.overlayState = state
        self.features = features
        self.id = state.rasterLayerState.id
    }

    public init(
        state: KMLLayerState,
        features: [KMLFeature] = []
    ) {
        self.init(state, features: features)
    }

    public init(
        features: [KMLFeature] = [],
        tileSize: Int = KMLDefaults.defaultTileSize,
        opacity: Double = KMLDefaults.defaultOpacity,
        layerStyle: KMLTileRenderer.LayerStyle = KMLTileRenderer.LayerStyle(),
        styleProvider: any KMLStyleProvider = DefaultKMLStyleProvider.shared
    ) {
        let state = KMLLayerState(
            tileSize: tileSize,
            opacity: opacity,
            layerStyle: layerStyle,
            styleProvider: styleProvider
        )
        self.init(state, features: features)
    }

    public var body: some View {
        KMLStateUpdater(overlayState: overlayState, features: features)
    }

    public func append(to content: inout MapViewContent) {
        content.rasterLayers.append(RasterLayer(state: overlayState.rasterLayerState))
    }
}

private struct KMLStateUpdater: View {
    let overlayState: KMLLayerState
    let features: [KMLFeature]

    private var updateToken: Int {
        var result: Int32 = 1
        for feature in features {
            var hasher = Hasher()
            hasher.combine(feature.id)
            hasher.combine(feature.geometry)
            hasher.combine(feature.visible)
            result = result &* 31 &+ Int32(truncatingIfNeeded: hasher.finalize())
        }
        return Int(result)
    }

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .task(id: updateToken) {
                overlayState.setFeatures(features)
            }
    }
}
