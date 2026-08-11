import Foundation
import MapConductorCore

/// Open Mobile Maps のズーム ⇄ 統一ズーム（Google 準拠）の変換。
///
/// ## なぜ ``WebMercatorZoomAltitudeConverter`` を使えないのか
///
/// 他のほとんどの SDK は「ズーム = 2 の指数」なので、統一ズームとの差は定数の
/// オフセット（MapLibre 系なら 1.0）で吸収できる。**Open Mobile Maps のズームは
/// 縮尺の分母**（1:500'000'000 の 500'000'000 の側）で、指数ではない。したがって
/// オフセットの足し算では変換できず、対数を挟む必要がある。
///
/// ```
/// unifiedZoom = log2(scaleAtZoom0 / nativeScale)
/// nativeScale = scaleAtZoom0 / 2^unifiedZoom
/// ```
///
/// ## scaleAtZoom0 の導出（実測値ではない）
///
/// SDK は縮尺の分母から「地図単位 / 物理ピクセル」をこう作る（`MapCamera2d`）:
///
/// ```
/// mapUnitsPerPixel = nativeScale * 0.0254 / screenDensityPpi
/// ```
///
/// 統一ズーム Z での Web メルカトルの地図単位 / 物理ピクセルは
/// `156543.034 / (2^Z * density)`。`screenDensityPpi` に 160 × density を渡すと
/// density が約分され、
///
/// ```
/// scaleAtZoom0 = 156543.034 x 160 / 0.0254 = 986'097'220
/// ```
///
/// が端末密度によらない定数として出る。**android-for-openmobilemaps と同じ定数**。
/// ここがプラットフォームでずれると、同じ統一ズームを渡しても iOS と android で
/// 縮尺が変わり、並べて見比べるサンプルが成立しなくなる。
///
/// ## 高度はこの SDK では使わない
///
/// ``zoomLevelToAltitude(zoomLevel:latitude:tilt:)`` /
/// ``altitudeToZoomLevel(altitude:latitude:tilt:)`` はカメラが高度で定義される SDK
/// （HERE / ArcGIS）のためのもの。Open Mobile Maps のカメラはズームなので、
/// 統一ズームを経由した Web メルカトルの参照式をそのまま持たせてある。
public final class OpenMobileMapsZoomAltitudeConverter: ZoomAltitudeConverterProtocol {
    /// 統一ズーム 0 での SDK の縮尺の分母。上のコメントの導出どおりの計算値。
    ///
    /// `156543.033928 x 160 / 0.0254`。
    public static let scaleAtZoom0: Double = 986_097_222.0

    public let zoom0Altitude: Double

    public init(zoom0Altitude: Double = AbstractZoomAltitudeConverter.defaultZoom0Altitude) {
        self.zoom0Altitude = zoom0Altitude
    }

    /// SDK の縮尺 → 統一ズーム。
    public func toUnifiedZoom(_ nativeScale: Double) -> Double {
        guard nativeScale > 0 else { return AbstractZoomAltitudeConverter.minZoomLevel }
        return clampZoom(log2(Self.scaleAtZoom0 / nativeScale))
    }

    /// 統一ズーム → SDK の縮尺。
    public func toNativeZoom(_ unifiedZoom: Double) -> Double {
        Self.scaleAtZoom0 / pow(AbstractZoomAltitudeConverter.zoomFactor, clampZoom(unifiedZoom))
    }

    public func zoomLevelToAltitude(zoomLevel: Double, latitude: Double, tilt: Double) -> Double {
        let unifiedZoom = toUnifiedZoom(zoomLevel)
        let distance = (zoom0Altitude * cosLatitudeFactor(latitude))
            / pow(AbstractZoomAltitudeConverter.zoomFactor, unifiedZoom)
        return clamp(
            distance * cosTiltFactor(tilt),
            AbstractZoomAltitudeConverter.minAltitude,
            AbstractZoomAltitudeConverter.maxAltitude
        )
    }

    public func altitudeToZoomLevel(altitude: Double, latitude: Double, tilt: Double) -> Double {
        let clampedAltitude = clamp(
            altitude,
            AbstractZoomAltitudeConverter.minAltitude,
            AbstractZoomAltitudeConverter.maxAltitude
        )
        let distance = clampedAltitude / cosTiltFactor(tilt)
        let unifiedZoom = log2((zoom0Altitude * cosLatitudeFactor(latitude)) / distance)
        return toNativeZoom(unifiedZoom)
    }

    /// 緯度による水平スケール補正。極付近で発散しないようクランプする。
    private func cosLatitudeFactor(_ latitudeDeg: Double) -> Double {
        let clamped = clamp(latitudeDeg, -85.0, 85.0)
        return Swift.max(AbstractZoomAltitudeConverter.minCosLat, abs(cos(clamped * .pi / 180.0)))
    }

    /// 傾きによる視距離補正。真横（90°）で発散しないようクランプする。
    private func cosTiltFactor(_ tiltDeg: Double) -> Double {
        let clamped = clamp(tiltDeg, 0.0, 90.0)
        return Swift.max(AbstractZoomAltitudeConverter.minCosTilt, cos(clamped * .pi / 180.0))
    }

    private func clampZoom(_ value: Double) -> Double {
        clamp(value, AbstractZoomAltitudeConverter.minZoomLevel, AbstractZoomAltitudeConverter.maxZoomLevel)
    }

    private func clamp(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
        Swift.min(Swift.max(value, lower), upper)
    }
}
