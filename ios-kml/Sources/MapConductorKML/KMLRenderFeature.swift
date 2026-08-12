import CoreGraphics
import Foundation
import UIKit

/// 1 フィーチャーを描くのに必要な形に前処理したもの。
///
/// 元の緯度経度ジオメトリは**捨てる**（`source` の geometry を `.empty` にする）。
/// 座標は `worldGeometry` が世界座標で持っており、描画も当たり判定もそちらを使う。
/// 両方持つとメモリが倍になり、大きなデータで OOM になる。
struct RenderFeature {
    let source: KMLFeature
    let worldGeometry: WorldGeometry
    let bounds: WorldBounds
    let fillColor: UIColor
    let strokeColor: UIColor
    let strokeWidth: CGFloat
    let pointRadius: CGFloat
}

/// スタイルを解決し、``RenderFeature`` を組み立てる部分。
///
/// android-sdk の android-kml の `KMLRenderFeature.kt` と同じ。
enum KMLRenderFeatureBuilder {
    static func build(
        _ feature: KMLFeature,
        layerStyle: KMLTileRenderer.LayerStyle,
        styleProvider: any KMLStyleProvider
    ) -> RenderFeature {
        let style = styleProvider.style(for: feature, defaultStyle: layerStyle)
        let worldGeometry = KMLWorld.toWorldGeometry(feature.geometry)
        let stripped = KMLFeature(id: feature.id, geometry: .empty, properties: feature.properties)
        return RenderFeature(
            source: stripped,
            worldGeometry: worldGeometry,
            bounds: KMLWorld.computeBounds(worldGeometry),
            fillColor: style.fillColor,
            strokeColor: style.strokeColor,
            strokeWidth: style.strokeWidth,
            pointRadius: style.pointRadius
        )
    }
}
