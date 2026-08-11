import Foundation
import MapConductorCore

/// このドライバーで何ができて何ができないかの宣言（実装点 H）。
///
/// **「宣言しない」＝「使えない」ではない**（`MapCapabilityStatus` の Unknown）。
/// コアは Unknown を非対応と断定しないので、書かなければ従来どおり動く。
/// 書く価値があるのは「**できない**と分かっているもの」で、それを宣言しておくと
/// 該当機能が黙って無反応になる代わりに理由つきのログを 1 回出す。
///
/// コントローラの外に出してあるのは、**SDK のネイティブ初期化無しで検証できるようにする**ため。
/// コントローラを組み立てるにはレイヤ（`MCPolygonLayerInterface.create()` など Metal と
/// C++ に触る呼び出し）が要るので、素のユニットテストからは作れない。
///
/// android-for-openmobilemaps の `OpenMobileMapsCapabilities.kt` と同じ宣言。
public enum OpenMobileMapsCapabilities {
    public static func declare(into registry: MutableMapServiceRegistry) {
        registry.declare(.screenProjectionSync, .supported)
        registry.declare(.polygonHoles, .supported)
        registry.declare(.clickPassthrough, .supported)
        registry.declare(.markerDrag, .supported)
        registry.declare(
            .cameraTilt,
            .approximated(
                "the 2d camera has no pitch; tilt is emulated by rotating the view and "
                    + "shifting the camera target (same method as ios-for-arcgis 2d)"
            )
        )
        registry.declareUnsupported(
            .gestureTilt,
            "the 2d camera has no pitch, so there is no tilt gesture to enable or disable"
        )
        registry.declareUnsupported(
            .gestureScroll,
            "the sdk exposes no per-gesture toggle; only the whole touch handler can be turned off"
        )
        registry.declareUnsupported(
            .gestureZoom,
            "the sdk exposes no per-gesture toggle; only the whole touch handler can be turned off"
        )
    }
}
