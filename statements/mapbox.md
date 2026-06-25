# 作業指示書: iOS Mapbox SDK の fitBounds 実装

## 前提

core の `MapViewStateProtocol`、`MapViewState`、`MapViewControllerProtocol` には既に `fitBounds` が追加済みであること。

---

## 変更 1: MapboxViewState.swift

**ファイルパス:**
`ios-for-mapbox/Sources/MapConductorForMapbox/MapboxViewState.swift`

**やること:**
`moveCameraTo(cameraPosition: MapCameraPosition, durationMillis: Long?)` メソッドの後に、以下のメソッドを追加する:

```swift
public override func fitBounds(bounds: GeoRectBounds, padding: Int) {
    controller?.fitBounds(bounds: bounds, padding: padding)
}
```

---

## 変更 2: MapboxViewController.swift

**ファイルパス:**
`ios-for-mapbox/Sources/MapConductorForMapbox/controller/MapboxViewController.swift`

**やること:**
`animateCamera(position: MapCameraPosition, duration: Long)` メソッドの後に、以下のメソッドを追加する。

Mapbox SDK の `mapboxMap.camera(for: CoordinateBounds, padding: UIEdgeInsets, bearing: nil, pitch: nil)` で CameraOptions を取得し `setCamera(to:)` で適用する:

```swift
func fitBounds(bounds: GeoRectBounds, padding: Int) {
    guard let mapView = mapView,
          let sw = bounds.southWest,
          let ne = bounds.northEast else { return }
    let coordinateBounds = CoordinateBounds(
        southwest: CLLocationCoordinate2D(latitude: sw.latitude, longitude: sw.longitude),
        northeast: CLLocationCoordinate2D(latitude: ne.latitude, longitude: ne.longitude)
    )
    let edgeInsets = UIEdgeInsets(top: CGFloat(padding), left: CGFloat(padding), bottom: CGFloat(padding), right: CGFloat(padding))
    let cameraOptions = mapView.mapboxMap.camera(for: coordinateBounds, padding: edgeInsets, bearing: nil, pitch: nil)
    mapView.mapboxMap.setCamera(to: cameraOptions)
}
```

**注意:**
- `CoordinateBounds` は `MapboxMaps` モジュールが提供する型。import 済みのはず。
- `UIEdgeInsets` は `UIKit` から。import がなければ追加する。

---

## 禁止事項

- 既存のメソッドを変更しない
- 新しいファイルを作成しない
- コメントを追加しない
