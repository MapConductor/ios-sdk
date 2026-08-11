# MapConductor for Open Mobile Maps（iOS）

[Open Mobile Maps](https://openmobilemaps.io/)（swisstopo）の iOS ドライバー。
`android-for-openmobilemaps` と**同じ構造**で書く。3 プラットフォームを少人数で
保守するための前提なので、片方だけ都合のよい形にしないこと。

対応する Android 側: `android-sdk/android-for-openmobilemaps`
雛形と実装点の一覧: `ios-sdk/ios-for-template/README.md`

## 準備 — maps-core をローカルに clone する

**この 1 手順を踏まないとビルドできない。**

```bash
cd ios-sdk
git clone --branch 4.0.0 --depth 1 https://github.com/openmobilemaps/maps-core
cd maps-core
git submodule update --init --depth 1 external/earcut external/protozero external/vtzero
# external/djinni は **空のままにする**（下記）
```

### なぜ clone が要るのか

maps-core 4.0.0 の `Package.swift` は、`external/djinni` に中身があると djinni を
**相対パスの依存**へ切り替える:

```swift
FileManager.default.fileExists(atPath: djinniManifest.path)
    ? .package(name: "djinni", path: "external/djinni")
    : .package(url: "https://github.com/UbiqueInnovation/djinni.git", ...)
```

SwiftPM は git 依存を再帰 clone するので submodule の中身が入る。その結果
「依存パッケージがローカルパス依存を持つ」形になり、解決できない:

```
error: exhausted attempts to resolve the dependencies graph, with the following
dependencies unresolved:
* 'djinni' at .../checkouts/maps-core/external/djinni
```

自分で clone して **djinni だけ空のまま**にしておくと、maps-core は djinni を URL
から取るようになり解決が通る。`Package.swift` は `../maps-core` があればそちらを、
無ければ公開リポジトリを見るので、上流が直れば自動的に元へ戻る。

Google Maps の `ios-maps-sdk/` も同じくローカル clone 運用（どちらも `.gitignore` 済み）。

### Metal ツールチェーン

maps-core は Metal シェーダを含むので、初回に一度だけ要る:

```bash
xcodebuild -downloadComponent MetalToolchain   # 約 690MB
```

入っていないと `cannot execute tool 'metal' due to missing Metal Toolchain` で落ちる。

## ビルドとテスト

```bash
cd ios-sdk/ios-for-openmobilemaps
xcodebuild test -scheme mapconductor-for-openmobilemaps \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

## この SDK に固有の注意

### ズームは「2 の指数」ではなく縮尺の分母

他のほとんどの SDK と違い、`MCMapCameraInterface.getZoom()` が返すのは
**縮尺の分母**（1:500'000'000 の 500'000'000 の側）。統一ズームとの差は定数の
オフセットでは吸収できず、対数を挟む必要がある。
`OpenMobileMapsZoomAltitudeConverter` を参照（`WebMercatorZoomAltitudeConverter`
は使えない）。定数 `scaleAtZoom0` は android と**同じ値**にしてある。

## 進捗

| # | 実装点 | 状態 |
|---|---|---|
| — | パッケージ / maps-core の解決 / Metal | 済み |
| — | ズーム換算（縮尺の分母 ⇄ 統一ズーム）+ テスト | 済み |
| A | ホルダー（投影 2 つ） | これから |
| B | コントローラ（カメラ） | これから |
| C | 地図デザイン型 | これから |
| D | レンダラ 6 種 | これから |
| E | イベント転送 | これから |
| F | ドラッグ中のパン抑止 | これから |
| G | State サブクラス / SwiftUI の入口 | これから |
| H | capability の宣言 | これから |
