# MapConductor iOS SDK

- [English Doc](./README.md)
- [Spanish Doc](./README.es-419.md)

**複数のマッププロバイダーに対応する、ひとつのiOSマップAPI。**

MapConductor iOS SDKは、SwiftUIベースの単一で一貫したAPIを通じて複数のマップSDKを扱えるようにする、iOS向けマッピングライブラリです。

Google Maps、Mapbox、Apple MapKit、ArcGIS、HERE Maps、MapLibreごとに異なるマップコードを書く代わりに、MapConductorはマップ、カメラの状態、マーカー、図形、オーバーレイ、高度なマップ機能のための共通の抽象化を提供します。

マップUIは一度だけ書きます。
プロダクトに合ったマッププロバイダーを選びましょう。

---

## なぜMapConductorなのか?

モバイルのマップ開発は、特定のマップSDKに強く依存してしまうことがよくあります。各プロバイダーは独自のAPI設計、ライフサイクルモデル、レンダリングの挙動、機能セットを持っています。これにより、プロバイダーの切り替えや複数のマップバックエンドのサポート、最新のSwiftUIアプリケーションにおけるマップ関連コードのクリーンな維持が難しくなります。

MapConductorは、主要なiOSマップSDKの上に共通レイヤーを提供することでこれを解決します。

MapConductorを使うと、以下のことができます:

* マップUIにSwiftUIファーストのAPIを使う
* 少ない書き換え作業でサポートされているマッププロバイダーを切り替える
* マーカー、円、ポリライン、ポリゴン、オーバーレイのロジックを共有する
* プロバイダーに依存しないヒートマップやマーカークラスタリングなどのマップ機能を構築する
* アプリケーションコードをSDK固有の差異ではなくマップの挙動に集中させる

![](./images/ja-comic-why-mapconductor.jpg)

---

## サポートされているマッププロバイダー

MapConductorは現在、以下のiOSマッププロバイダーをサポートしています:

| プロバイダー      | パッケージ                       | プロダクト                        |
| ---------------- | ------------------------------ | ------------------------------- |
| Google Maps     | `ios-for-googlemaps`          | `MapConductorForGoogleMaps`    |
| Mapbox          | `ios-for-mapbox`              | `MapConductorForMapbox`        |
| Apple MapKit    | `ios-for-mapkit`              | `MapConductorForMapKit`        |
| ArcGIS          | `ios-for-arcgis`              | `MapConductorForArcGIS`        |
| HERE Maps       | `ios-for-here`                | `MapConductorForHERE`          |
| MapLibre        | `ios-for-maplibre`            | `MapConductorForMapLibre`      |

アプリ用に1つのプロバイダーを選んでもよいですし、後でプロバイダーを変更できるようにコードを構成することもできます。

---

## コア機能

MapConductorは、一般的なマップUIおよび地理空間機能に対して統一されたAPIを提供します:

* 複数プロバイダー向けのマップビューコンポーネント
* カメラの状態とカメラ位置
* マーカー
* カスタムマーカーアイコン
* メートル単位の半径を持つ円
* ポリライン
* ポリゴン
* グラウンドイメージ
* ラスタータイルレイヤー
* ヒートマップ
* マーカークラスタリング
* GeoJSONレイヤー
* `GeoPoint`などの共有ジオメトリ型
* SwiftUI上に構築された、マップオブジェクトのためのリアクティブな状態管理

目的は各プロバイダーSDKをラップするだけでなく、可能な限り異なるマップエンジン間で一貫した動作を提供することです。

---

## インストール

Xcode (File → Add Package Dependencies) または `Package.swift` に直接、必要なパッケージを追加してください。

```swift
dependencies: [
    .package(url: "https://github.com/MapConductor/ios-sdk-core", from: "1.0.0"),
    .package(url: "https://github.com/MapConductor/ios-for-googlemaps", from: "1.0.0"), // または選択したプロバイダー

    // オプションの機能パッケージ
    .package(url: "https://github.com/MapConductor/ios-heatmap", from: "1.0.0"),
    .package(url: "https://github.com/MapConductor/ios-marker-cluster", from: "1.0.0"),
    .package(url: "https://github.com/MapConductor/ios-geojson-layer", from: "1.0.0"),
],
```

次に、ターゲットにプロダクトを追加します。

```swift
.target(
    name: "YourApp",
    dependencies: [
        .product(name: "MapConductorCore", package: "ios-sdk-core"),
        .product(name: "MapConductorForGoogleMaps", package: "ios-for-googlemaps"),
    ]
)
```

各マッププロバイダーは、それぞれ独自のAPIキー、アクセストークン、またはXcodeプロジェクトの設定(Info.plistのエントリなど)が必要な場合があります。使用するプロバイダーのセットアップガイドを確認してください。

---

## 基本的な例

以下の例は、マーカーと円を含むシンプルなSwiftUIマップを示しています。

```swift
import SwiftUI
import MapConductorCore
import MapConductorForGoogleMaps

struct ContentView: View {
    @StateObject private var mapState = GoogleMapViewState(
        cameraPosition: MapCameraPosition(
            position: GeoPoint(latitude: 35.6762, longitude: 139.6503),
            zoom: 12
        )
    )

    var body: some View {
        GoogleMapView(state: mapState) {
            Marker(position: GeoPoint(latitude: 35.6762, longitude: 139.6503))
            Circle(
                center: GeoPoint(latitude: 35.6762, longitude: 139.6503),
                radiusMeters: 500
            )
        }
    }
}
```

この例ではGoogle Mapsを使用していますが、マップオブジェクトはMapConductorの概念を使って書かれています。同じオーバーレイのロジックを他のサポートされているプロバイダーに適用できます。

---

## マッププロバイダーの切り替え

MapConductorの主な考え方の1つは、マッププロバイダーを変更してもマップオーバーレイを書き直す必要がないということです。

stateとviewを変えるだけで、すべてのオーバーレイはそのまま動作します:

```swift
// Google Maps
GoogleMapView(state: googleMapState) { /* overlays */ }

// Mapbox
MapboxMapView(state: mapboxState) { /* overlays */ }

// Apple MapKit
MapKitMapView(state: mapKitState) { /* overlays */ }

// ArcGIS
ArcGISMapView(state: arcgisState) { /* overlays */ }

// HERE Maps
HEREMapView(state: hereMapState) { /* overlays */ }

// MapLibre
MapLibreMapView(state: maplibreState) { /* overlays */ }
```

再利用可能なマップコンテンツには、どのプロバイダーのビューがレンダリングするかにかかわらず、マーカー、円、ポリライン、ポリゴン、ヒートマップ、クラスター、その他のMapConductorコンポーネントを含めることができます。

プロバイダー固有のセットアップは依然として必要ですが、アプリケーションレベルのマップUIはより高いポータビリティを維持できます。

---

## モジュール概要

| モジュール                     | パッケージ                          | プロダクト                         | 説明                                                          |
| ----------------------------- | --------------------------------- | --------------------------------- | --------------------------------------------------------------------- |
| `ios-sdk-core`                | `mapconductor-core`               | `MapConductorCore`               | コアの抽象化、ジオメトリ型、オーバーレイの状態                    |
| `ios-for-googlemaps`          | `mapconductor-for-googlemaps`     | `MapConductorForGoogleMaps`      | Google Mapsプロバイダー実装                                  |
| `ios-for-mapbox`              | `ios-for-mapbox`                  | `MapConductorForMapbox`          | Mapboxプロバイダー実装                                       |
| `ios-for-mapkit`              | `mapconductor-for-mapkit`         | `MapConductorForMapKit`          | Apple MapKitプロバイダー実装                                 |
| `ios-for-arcgis`              | `mapconductor-for-arcgis`         | `MapConductorForArcGIS`          | ArcGISプロバイダー実装                                       |
| `ios-for-here`                | `mapconductor-for-here`           | `MapConductorForHERE`            | HERE Mapsプロバイダー実装                                    |
| `ios-for-maplibre`            | `mapconductor-for-maplibre`       | `MapConductorForMapLibre`        | MapLibreプロバイダー実装                                     |
| `ios-heatmap`                 | `mapconductor-heatmap`            | `MapConductorHeatmap`            | プロバイダーに依存しないヒートマップオーバーレイ                                 |
| `ios-marker-cluster`          | `mapconductor-marker-cluster`     | `MapConductorMarkerCluster`      | マーカークラスタリングのサポート                                            |
| `ios-geojson-layer`           | `mapconductor-geojson-layer`      | `MapConductorGeoJSONLayer`       | GeoJSONレイヤーのサポート                                                 |

---

## 機能対応状況

| 機能               | Google Maps | Mapbox   | MapKit   | ArcGIS   | HERE Maps | MapLibre |
| ------------------ | -----------: | --------: | --------: | --------: | --------: | --------: |
| Map               |     &#x2611; | &#x2611; | &#x2611; | &#x2611; | &#x2611; | &#x2611; |
| Marker            |     &#x2611; | &#x2611; | &#x2611; | &#x2611; | &#x2611; | &#x2611; |
| Circle            |     &#x2611; | &#x2611; | &#x2611; | &#x2611; | &#x2611; | &#x2611; |
| Polyline          |     &#x2611; | &#x2611; | &#x2611; | &#x2611; | &#x2611; | &#x2611; |
| Polygon           |     &#x2611; | &#x2611; | &#x2611; | &#x2611; | &#x2611; | &#x2611; |
| Ground Image      |     &#x2611; | &#x2611; | &#x2611; | &#x2611; | &#x2611; | &#x2611; |
| Heatmap           |     &#x2611; | &#x2611; | &#x2611; | &#x2611; | &#x2611; | &#x2611; |
| Marker Clustering |     &#x2611; | &#x2611; | &#x2611; | &#x2611; | &#x2611; | &#x2611; |
| Raster Tile Layer |     &#x2611; | &#x2611; | &#x2611; | &#x2611; | &#x2611; | &#x2611; |
| Vector Tile Layer |     &#x2610; | &#x2610; | &#x2610; | &#x2610; | &#x2610; | &#x2610; |

MapConductorは活発に開発が進められています。最新のプロバイダー固有の挙動や制限事項については、ドキュメントとリリースノートを確認してください。

---

## こんな方に向いています

MapConductorは、以下のような方に役立ちます:

* SwiftUIとマップを使ったiOSアプリを構築している
* 複数のマッププロバイダーを評価している
* あるマップSDKから別のものへの移行を計画している
* 異なる顧客や地域の要件にわたってマップ機能を保守している
* 再利用可能なマップUIコンポーネントを構築している
* モバイルマップ向けのオープンソースの抽象化レイヤーを探している

各プロバイダーSDKがその機能をどのように実装することを期待しているかではなく、マップに何を表示すべきかをアプリケーションコードで記述したい場合に特に役立ちます。

---

## サンプル

すべてのモジュールを紹介するフル機能のデモアプリについては、[samples/MapConductorSampleApp](samples/MapConductorSampleApp)を参照してください。

---

## プロジェクトの状況

MapConductor iOS SDKはリリース済みで、活発に開発が進められています。

このプロジェクトは、主要なiOSマッププロバイダーにわたって、マップ開発をより柔軟でポータブル、かつSwiftUIフレンドリーにすることを目指しています。一部の高度な機能は実験的であったり、プロバイダー固有の差異がある場合があります。

フィードバック、Issue、コントリビューションを歓迎します。

---

## ライセンス

MapConductor iOS SDKはApache License 2.0のもとでリリースされています。
