# 作業指示書: iOS MapLibre SDK の fitBounds 実装

## 前提

core の `MapViewStateProtocol`、`MapViewState`、`MapViewControllerProtocol` には既に `fitBounds` が追加済みであること。

---

## 変更 1: MapLibreViewState.swift

**ファイルパス:**
`ios-for-maplibre/Sources/MapConductorForMapLibre/MapLibreViewState.swift`

**やること:**
`moveCameraTo(cameraPosition: MapCameraPosition, durationMillis: Long?)` メソッドの後に、以下のメソッドを追加する:

```swift
public override func fitBounds(bounds: GeoRectBounds, padding: Int) {
    controller?.fitBounds(bounds: bounds, padding: padding)
}
```

---

## 変更 2: MapLibreViewController.swift

**ファイルパス:**
`ios-for-maplibre/Sources/MapConductorForMapLibre/controller/MapLibreViewController.swift`

**やること:**
`animateCamera(position: MapCameraPosition, duration: Long)` メソッドの後に、以下のメソッドを追加する。

MapLibre の `setVisibleCoordinateBounds(_:edgePadding:animated:)` を使う。`MLNCoordinateBounds` は `MLNCoordinateBoundsMake(sw, ne)` で生成する:

```swift
func fitBounds(bounds: GeoRectBounds, padding: Int) {
    guard let mapView = mapView,
          let sw = bounds.southWest,
          let ne = bounds.northEast else { return }
    let coordinateBounds = MLNCoordinateBoundsMake(
        CLLocationCoordinate2D(latitude: sw.latitude, longitude: sw.longitude),
        CLLocationCoordinate2D(latitude: ne.latitude, longitude: ne.longitude)
    )
    let edgePadding = UIEdgeInsets(top: CGFloat(padding), left: CGFloat(padding), bottom: CGFloat(padding), right: CGFloat(padding))
    mapView.setVisibleCoordinateBounds(coordinateBounds, edgePadding: edgePadding, animated: false)
}
```

**注意:**
- `MLNCoordinateBoundsMake` は MapLibre の C関数ラッパー。`MapLibre` import 済みであれば使える。
- `UIEdgeInsets` は `UIKit` から。import がなければ追加する。

---

## 禁止事項

- 既存のメソッドを変更しない
- 新しいファイルを作成しない
- コメントを追加しない
