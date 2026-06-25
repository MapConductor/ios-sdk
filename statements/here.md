# 作業指示書: iOS HERE SDK の fitBounds 実装

## 前提

core の `MapViewStateProtocol`、`MapViewState`、`MapViewControllerProtocol` には既に `fitBounds` が追加済みであること。

`ios-for-here/Sources/MapConductorForHERE/GeoPointExtensions.swift` には `GeoBox.toGeoRectBounds()` が存在するが、逆方向（`GeoRectBounds` → `GeoBox`）は存在しない。

---

## 変更 1: GeoPointExtensions.swift に変換関数を追加

**ファイルパス:**
`ios-for-here/Sources/MapConductorForHERE/GeoPointExtensions.swift`

**やること:**
ファイルの末尾に以下の extension を追加する:

```swift
extension GeoRectBounds {
    func toGeoBox() -> GeoBox? {
        guard let sw = southWest, let ne = northEast else { return nil }
        return GeoBox(
            southWestCorner: GeoCoordinates(latitude: sw.latitude, longitude: sw.longitude),
            northEastCorner: GeoCoordinates(latitude: ne.latitude, longitude: ne.longitude)
        )
    }
}
```

**注意:** `GeoCoordinates` と `GeoBox` は `heresdk` モジュールで提供される。ファイル先頭に `import heresdk` がなければ追加する。

---

## 変更 2: HereMapViewState.swift

**ファイルパス:**
`ios-for-here/Sources/MapConductorForHERE/HereMapViewState.swift`

**やること:**
`moveCameraTo(cameraPosition: MapCameraPosition, durationMillis: Long?)` メソッドの後に、以下のメソッドを追加する:

```swift
public override func fitBounds(bounds: GeoRectBounds, padding: Int) {
    controller?.fitBounds(bounds: bounds, padding: padding)
}
```

---

## 変更 3: HereMapViewController.swift

**ファイルパス:**
`ios-for-here/Sources/MapConductorForHERE/controller/HereMapViewController.swift`

**やること:**
`animateCamera(position: MapCameraPosition, duration: Long)` メソッドの後に、以下のメソッドを追加する。

HERE SDK の `MapCameraUpdateFactory.lookAt(geoBox:)` を使う（Android と同じ）:

```swift
func fitBounds(bounds: GeoRectBounds, padding: Int) {
    guard let geoBox = bounds.toGeoBox() else { return }
    let cameraUpdate = MapCameraUpdateFactory.lookAt(geoBox: geoBox)
    hereHolder.mapView.camera.applyUpdate(cameraUpdate)
}
```

**注意:**
- `MapCameraUpdateFactory.lookAt(geoBox:)` の引数ラベルが `geoBox:` でない場合は `MapCameraUpdateFactory.lookAt(geoBox)` のようにラベルなしで試みること。
- `hereHolder` は `HereMapViewController` に既に定義されている。

---

## 禁止事項

- 既存のメソッドを変更しない
- コメントを追加しない
