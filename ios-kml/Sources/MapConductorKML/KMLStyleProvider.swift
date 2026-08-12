import Foundation

/// Resolves the render style for a KML feature.
public protocol KMLStyleProvider: AnyObject {
    func style(
        for feature: KMLFeature,
        defaultStyle: KMLTileRenderer.LayerStyle
    ) -> KMLTileRenderer.LayerStyle
}

/// Preserves the existing feature-style-over-layer-style behavior.
public final class DefaultKMLStyleProvider: KMLStyleProvider {
    public static let shared = DefaultKMLStyleProvider()

    private init() {}

    public func style(
        for feature: KMLFeature,
        defaultStyle: KMLTileRenderer.LayerStyle
    ) -> KMLTileRenderer.LayerStyle {
        KMLTileRenderer.LayerStyle(
            strokeColor: feature.strokeColor ?? defaultStyle.strokeColor,
            fillColor: feature.fillColor ?? defaultStyle.fillColor,
            strokeWidth: feature.strokeWidth ?? defaultStyle.strokeWidth,
            pointRadius: feature.pointRadius ?? defaultStyle.pointRadius
        )
    }
}
