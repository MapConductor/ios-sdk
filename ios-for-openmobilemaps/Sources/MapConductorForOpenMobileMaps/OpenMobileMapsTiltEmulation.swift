import Foundation
import MapConductorCore

/// Open Mobile Maps の 2D カメラ向けの tilt 擬似表現。
///
/// ## なぜ擬似表現なのか
///
/// `MCMapCameraInterface` にピッチが無い。`MCMapCamera3dInterface` なら本当に傾けられるが、
/// それは地図を**地球儀表示**で作ったときだけ手に入るもので、平面地図（EPSG:3857）の
/// まま傾けることはできない。`camera.asMapCamera3d()` は 2D の地図では nil を返す。
///
/// そこで ios-for-arcgis の 2D と**同じ方式・同じ定数**を使う:
///
/// - 遠近感は ``OpenMobileMapsMapSurface`` がビューを X 軸まわりに回して作る
/// - カメラ位置の付け替えはここが受け持つ
///
/// ## tilt の符号
///
/// - `tilt >= 0`: 指定位置は**ターゲット**（画面中心）。カメラが後方へ下がるだけなので
///   中心もズームも動かさない。
/// - `tilt < 0`: 指定位置は**カメラ位置**。ターゲットが進行方向（bearing）へ前進する。
///   前進量とズームオフセットは MapLibre / TomTom / Leaflet / ArcGIS2D と同一の式・同一定数。
///
/// android-for-openmobilemaps の `OpenMobileMapsTiltEmulation.kt` と同じ値・同じ式。
enum OpenMobileMapsTiltEmulation {
    /// MapLibre / TomTom / Leaflet / ArcGIS2D と同一値。プロバイダ間で挙動を揃えるため変えないこと。
    private static let targetDistanceScale = 1.83
    private static let zoomOffsetAtMaxTilt = -0.9
    static let maxTiltDegrees = 60.0

    /// 高度の算出にはプラットフォーム非依存の既定値（Google Maps 較正）を使う。
    /// ArcGIS2D と同じ理由で、ここを触るとシフト量が他プロバイダとずれる。
    private static let converter = OpenMobileMapsZoomAltitudeConverter(
        zoom0Altitude: AbstractZoomAltitudeConverter.defaultZoom0Altitude
    )

    /// 論理カメラ → 実際に SDK へ渡す中心・統一ズーム。
    static func shiftedCamera(_ position: MapCameraPosition) -> (center: GeoPoint, zoom: Double) {
        let origin = GeoPoint.from(position: position.position)
        guard position.tilt < 0 else { return (origin, position.zoom) }

        let tiltAbsDeg = min(max(abs(position.tilt), 0.0), maxTiltDegrees)
        let zoom = position.zoom + zoomOffsetAtMaxTilt * (tiltAbsDeg / maxTiltDegrees)
        let tiltAbsRad = tiltAbsDeg * .pi / 180.0
        let altitude = altitudeFor(unifiedZoom: position.zoom, latitude: origin.latitude)
        let distanceForward = altitude * cos(tiltAbsRad) * tan(tiltAbsRad) * targetDistanceScale
        let target = Spherical.computeOffset(origin: origin, distance: distanceForward, heading: position.bearing)
        return (target, zoom)
    }

    /// SDK から読み戻した中心・統一ズームを論理カメラへ戻す。
    static func restoreLogicalCamera(
        center: GeoPoint,
        zoom: Double,
        bearing: Double,
        logicalTilt: Double
    ) -> (center: GeoPoint, zoom: Double) {
        let tiltAbsDeg = min(max(abs(logicalTilt), 0.0), maxTiltDegrees)
        guard logicalTilt < 0, tiltAbsDeg > 0 else { return (center, zoom) }

        let originalZoom = zoom - zoomOffsetAtMaxTilt * (tiltAbsDeg / maxTiltDegrees)
        let tiltAbsRad = tiltAbsDeg * .pi / 180.0
        let altitude = altitudeFor(unifiedZoom: originalZoom, latitude: center.latitude)
        let distanceBackward = altitude * cos(tiltAbsRad) * tan(tiltAbsRad) * targetDistanceScale
        let originalPosition = Spherical.computeOffset(
            origin: center,
            distance: distanceBackward,
            heading: bearing + 180.0
        )
        return (originalPosition, originalZoom)
    }

    /// 統一ズームでの視距離。
    ///
    /// ``OpenMobileMapsZoomAltitudeConverter/zoomLevelToAltitude(zoomLevel:latitude:tilt:)`` は
    /// SDK の縮尺を受け取る形なので、ここでは統一ズームを一度縮尺へ戻してから渡す
    /// （他プロバイダの `converter.zoomLevelToAltitude(zoom, ...)` と同じ意味になる）。
    private static func altitudeFor(unifiedZoom: Double, latitude: Double) -> Double {
        converter.zoomLevelToAltitude(
            zoomLevel: converter.toNativeZoom(unifiedZoom),
            latitude: latitude,
            tilt: 0.0
        )
    }
}
