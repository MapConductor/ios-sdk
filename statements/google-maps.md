# 作業指示書: iOS GoogleMaps SDK の fitBounds 実装

## 前提

core の `MapViewStateProtocol`、`MapViewState`、`MapViewControllerProtocol` には既に `fitBounds` が追加済みであること。

---

## 変更 1: GoogleMapViewState.swift

**ファイルパス:**
`ios-for-googlemaps/Sources/MapConductorForGoogleMaps/GoogleMapViewState.swift`

**やること:**
`moveCameraTo(cameraPosition: MapCameraPosition, durationMillis: Long?)` メソッドの後に、以下のメソッドを追加する:

```swift
public override func fitBounds(bounds: GeoRectBounds, padding: Int) {
    controller?.fitBounds(bounds: bounds, padding: padding)
}
```

---

## 変更 2: GoogleMapViewController.swift

**ファイルパス:**
`ios-for-googlemaps/Sources/MapConductorForGoogleMaps/controller/GoogleMapViewController.swift`

**やること:**
`animateCamera(position: MapCameraPosition, duration: Long)` メソッドの後に、以下のメソッドを追加する。

Google Maps SDK の `GMSCameraUpdate.fit(_:withPadding:)` を使う。`GMSCoordinateBounds` は南西・北東座標から生成する:

```swift
func fitBounds(bounds: GeoRectBounds, padding: Int) {
    guard let mapView = mapView,
          let sw = bounds.southWest,
          let ne = bounds.northEast else { return }
    let coordinateBounds = GMSCoordinateBounds(
        coordinate: CLLocationCoordinate2D(latitude: sw.latitude, longitude: sw.longitude),
        coordinate: CLLocationCoordinate2D(latitude: ne.latitude, longitude: ne.longitude)
    )
    let update = GMSCameraUpdate.fit(coordinateBounds, withPadding: CGFloat(padding))
    mapView.moveCamera(update)
}
```

---

## 禁止事項

- 既存のメソッドを変更しない
- 新しいファイルを作成しない
- コメントを追加しない
