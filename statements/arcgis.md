# 作業指示書: iOS ArcGIS SDK の fitBounds 実装

## 前提

core の `MapViewStateProtocol`、`MapViewState`、`MapViewControllerProtocol` には既に `fitBounds` が追加済みであること。

---

## 変更 1: ArcGISMapViewState.swift

**ファイルパス:**
`ios-for-arcgis/Sources/MapConductorForArcGIS/ArcGISMapViewState.swift`

**やること:**
`moveCameraTo(cameraPosition: MapCameraPosition, durationMillis: Long?)` メソッドの後に、以下のメソッドを追加する:

```swift
public override func fitBounds(bounds: GeoRectBounds, padding: Int) {
    controller?.fitBounds(bounds: bounds, padding: padding)
}
```

---

## 変更 2: ArcGISMapViewController.swift

**ファイルパス:**
`ios-for-arcgis/Sources/MapConductorForArcGIS/controller/ArcGISMapViewController.swift`

**やること:**
`animateCamera(position: MapCameraPosition, duration: Long)` メソッドの後に、以下のメソッドを追加する。

ArcGIS の `Viewpoint(boundingGeometry:)` に `Envelope` を渡してバウンズを表示する:

```swift
func fitBounds(bounds: GeoRectBounds, padding: Int) {
    guard let sw = bounds.southWest,
          let ne = bounds.northEast else { return }
    let envelope = Envelope(
        xMin: sw.longitude,
        yMin: sw.latitude,
        xMax: ne.longitude,
        yMax: ne.latitude,
        spatialReference: .wgs84
    )
    let viewpoint = Viewpoint(boundingGeometry: envelope)
    Task {
        typedHolder.mapView.proxy?.proxy.setViewpoint(viewpoint)
    }
}
```

**注意:**
- `Envelope`、`Viewpoint`、`SpatialReference` は `ArcGIS` モジュールで提供される。import 済みのはず。
- `typedHolder` は `ArcGISMapViewController` に既に定義されている。
- `setViewpoint` のシグネチャが `setViewpoint(_ viewpoint: Viewpoint)` でない場合は、`setViewpointAnimated` の使用例を参考に正しいメソッドを探すこと。

---

## 禁止事項

- 既存のメソッドを変更しない
- コメントを追加しない
