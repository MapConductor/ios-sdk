import Foundation
import MapConductorCore

/// カメラアニメーションの補間。
///
/// ## SDK のアニメーションを使わない
///
/// `moveToCenterPositionZoom(..., animated: true)` は**尺を指定できず、実測で常に約 300ms**
/// で着地する。アプリが 1000ms と言っても 300ms で終わるので、他プロバイダと並べると
/// 明らかに先に着いてしまう。フレームを刻んで `animated: false` の移動を繰り返し、
/// こちらで尺を守る。ここはその補間の中身。
///
/// android-for-openmobilemaps の `OpenMobileMapsCameraAnimation.kt` と同じ式。
enum OpenMobileMapsCameraAnimation {
    /// 経度 180 度ぶんのメルカトル距離（m）。
    private static let maxExtentMeters = 20_037_508.342_789_244

    /// メルカトルが破綻しない緯度の上限。
    private static let maxLatitude = 85.051_128_78

    /// `from` から `to` へ `t`（0..1）だけ進んだカメラ。
    ///
    /// `t` は**イージング適用後**の値を渡すこと（ここでは線形に混ぜるだけ）。
    static func interpolate(from: MapCameraPosition, to: MapCameraPosition, t: Double) -> MapCameraPosition {
        MapCameraPosition(
            position: interpolatePosition(from: from.position, to: to.position, t: t),
            zoom: from.zoom + (to.zoom - from.zoom) * t,
            bearing: interpolateBearing(from: from.bearing, to: to.bearing, t: t),
            tilt: from.tilt + (to.tilt - from.tilt) * t,
            paddings: to.paddings
        )
    }

    /// 中心の補間。メルカトルのメートル空間で線形に混ぜる。
    ///
    /// 経度は**近い方向へ**回る。±180 度を跨ぐ移動で世界を逆回りしないため
    /// （東京 → ホノルルが太平洋ではなくユーラシア大陸経由になる、という形で出る）。
    private static func interpolatePosition(
        from: any GeoPointProtocol,
        to: any GeoPointProtocol,
        t: Double
    ) -> GeoPoint {
        let fromX = longitudeToMercatorX(from.longitude)
        var deltaX = longitudeToMercatorX(to.longitude) - fromX
        if deltaX > maxExtentMeters { deltaX -= 2 * maxExtentMeters }
        if deltaX < -maxExtentMeters { deltaX += 2 * maxExtentMeters }

        let fromY = latitudeToMercatorY(from.latitude)
        let y = fromY + (latitudeToMercatorY(to.latitude) - fromY) * t

        return GeoPoint(
            latitude: mercatorYToLatitude(y),
            longitude: mercatorXToLongitude(fromX + deltaX * t)
        )
    }

    /// 方位の補間。近い方向へ回り、0 以上 360 未満へ正規化して返す。
    static func interpolateBearing(from: Double, to: Double, t: Double) -> Double {
        var delta = (to - from).truncatingRemainder(dividingBy: 360.0)
        if delta > 180.0 { delta -= 360.0 }
        if delta < -180.0 { delta += 360.0 }
        let bearing = (from + delta * t).truncatingRemainder(dividingBy: 360.0)
        return bearing < 0 ? bearing + 360.0 : bearing
    }

    /// イージング。android 標準の `AccelerateDecelerateInterpolator` と同じ余弦カーブ。
    ///
    /// Google Maps のカメラアニメーションもこの系統なので、並べたときの見え方が揃う。
    static func ease(_ t: Double) -> Double {
        (1.0 - cos(min(max(t, 0.0), 1.0) * .pi)) / 2.0
    }

    private static func longitudeToMercatorX(_ longitude: Double) -> Double {
        longitude * maxExtentMeters / 180.0
    }

    private static func mercatorXToLongitude(_ x: Double) -> Double {
        let longitude = x * 180.0 / maxExtentMeters
        return (longitude + 180.0).truncatingRemainder(dividingBy: 360.0).nonNegativeMod(360.0) - 180.0
    }

    private static func latitudeToMercatorY(_ latitude: Double) -> Double {
        let clamped = min(max(latitude, -maxLatitude), maxLatitude)
        return log(tan((90.0 + clamped) * .pi / 360.0)) * maxExtentMeters / .pi
    }

    private static func mercatorYToLatitude(_ y: Double) -> Double {
        180.0 / .pi * (2.0 * atan(exp(y * .pi / maxExtentMeters)) - .pi / 2.0)
    }
}

private extension Double {
    /// Kotlin の `((x % m) + m) % m` に相当。Swift の `%` は負の値で負を返す。
    func nonNegativeMod(_ modulus: Double) -> Double {
        let r = truncatingRemainder(dividingBy: modulus)
        return r < 0 ? r + modulus : r
    }
}
