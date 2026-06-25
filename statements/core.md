# 作業指示書: iOS Core インターフェース変更

## 目的

`MapViewStateProtocol`、`MapViewState`、`MapViewControllerProtocol` に `fitBounds` メソッドを追加する。
新しいコードを作り込まず、既存パターンに沿った最小限の変更のみ行うこと。

---

## 変更 1: MapViewState.swift

**ファイルパス:**
`ios-sdk-core/Sources/MapConductorCore/MapViewState.swift`

**やること:**

1. `MapViewStateProtocol` に以下のメソッドを追加（`getMapViewHolder()` の前に追加）:
   ```swift
   func fitBounds(bounds: GeoRectBounds, padding: Int)
   ```

2. `MapViewState` 抽象クラスに以下の `open func` を追加（`getMapViewHolder()` の `open func` の前に追加）:
   ```swift
   open func fitBounds(bounds: GeoRectBounds, padding: Int) {
       fatalError("Override in subclass")
   }
   ```

**変更後の `MapViewStateProtocol` の全体像（参考）:**
```swift
public protocol MapViewStateProtocol: ObservableObject {
    associatedtype ActualMapDesignType

    var id: String { get }
    var cameraPosition: MapCameraPosition { get }
    var mapDesignType: ActualMapDesignType { get set }

    func moveCameraTo(cameraPosition: MapCameraPosition, durationMillis: Long?)
    func moveCameraTo(position: GeoPoint, durationMillis: Long?)

    func fitBounds(bounds: GeoRectBounds, padding: Int)

    func getMapViewHolder() -> AnyMapViewHolder?
}
```

---

## 変更 2: MapViewController.swift

**ファイルパス:**
`ios-sdk-core/Sources/MapConductorCore/controller/MapViewController.swift`

**やること:**
`MapViewControllerProtocol` に以下のメソッドを追加（`animateCamera` の後に追加）:

```swift
func fitBounds(bounds: GeoRectBounds, padding: Int)
```

**変更後の `MapViewControllerProtocol` の全体像（参考）:**
```swift
public protocol MapViewControllerProtocol {
    var holder: AnyMapViewHolder { get }
    var coroutine: CoroutineScope { get }

    func clearOverlays() async

    func setCameraMoveStartListener(listener: OnCameraMoveHandler?)
    func setCameraMoveListener(listener: OnCameraMoveHandler?)
    func setCameraMoveEndListener(listener: OnCameraMoveHandler?)

    func setMapClickListener(listener: OnMapEventHandler?)
    func setMapLongClickListener(listener: OnMapEventHandler?)

    func setMapInitializedListener(listener: OnMapInitializedHandler?)

    func moveCamera(position: MapCameraPosition)

    func animateCamera(position: MapCameraPosition, duration: Long)

    func fitBounds(bounds: GeoRectBounds, padding: Int)
}
```

---

## 禁止事項

- 新しいクラスやファイルを作成しない
- 既存のメソッドを変更しない
- コメントを追加しない
