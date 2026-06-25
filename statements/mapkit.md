# 作業指示書: iOS MapKit SDK の fitBounds 実装

## 前提

core の `MapViewStateProtocol`、`MapViewState`、`MapViewControllerProtocol` には既に `fitBounds` が追加済みであること。

---

## 変更 1: MapKitViewState.swift

**ファイルパス:**
`ios-for-mapkit/Sources/MapConductorForMapKit/MapKitViewState.swift`

**やること:**
`moveCameraTo(cameraPosition: MapCameraPosition, durationMillis: Long?)` メソッドの後に、以下のメソッドを追加する:

```swift
public override func fitBounds(bounds: GeoRectBounds, padding: Int) {
    controller?.fitBounds(bounds: bounds, padding: padding)
}
```

---

## 変更 2: MapKitViewController.swift

**ファイルパス:**
`ios-for-mapkit/Sources/MapConductorForMapKit/controller/MapKitViewController.swift`

**やること:**
`animateCamera(position: MapCameraPosition, duration: Long)` メソッドの後に、以下のメソッドを追加する。

MapKit の `setVisibleMapRect(_:edgePadding:animated:)` を使う。`GeoRectBounds` を `MKMapRect` に変換するには南西・北東の `MKMapPoint` を経由する:

```swift
func fitBounds(bounds: GeoRectBounds, padding: Int) {
    guard let mapView = mapView,
          let sw = bounds.southWest,
          let ne = bounds.northEast else { return }
    let swPoint = MKMapPoint(CLLocationCoordinate2D(latitude: sw.latitude, longitude: sw.longitude))
    let nePoint = MKMapPoint(CLLocationCoordinate2D(latitude: ne.latitude, longitude: ne.longitude))
    let rect = MKMapRect(
        x: min(swPoint.x, nePoint.x),
        y: min(nePoint.y, swPoint.y),
        width: abs(nePoint.x - swPoint.x),
        height: abs(swPoint.y - nePoint.y)
    )
    let edgePadding = UIEdgeInsets(top: CGFloat(padding), left: CGFloat(padding), bottom: CGFloat(padding), right: CGFloat(padding))
    mapView.setVisibleMapRect(rect, edgePadding: edgePadding, animated: false)
}
```

**注意:**
- `MKMapPoint` の Y 軸は南北が逆（Y が大きいほど南）。そのため ne.y が sw.y より小さくなる。`min(nePoint.y, swPoint.y)` が矩形の左上 Y になる。
- `MKMapKit` は既に import 済み。
- `UIKit` または `CoreLocation` の `UIEdgeInsets` が使える。import に `UIKit` がなければ追加する。

---

## 禁止事項

- 既存のメソッドを変更しない
- 新しいファイルを作成しない
- コメントを追加しない
