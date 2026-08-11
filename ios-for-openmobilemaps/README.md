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
git clone --recurse-submodules --branch 4.0.0 --depth 1 \
  https://github.com/openmobilemaps/maps-core
```

### なぜ clone が要るのか（`.package(url:)` では通らない）

maps-core 4.0.0 の `Package.swift` は、`external/djinni` に中身があると djinni を
**相対パスの依存**へ切り替える:

```swift
FileManager.default.fileExists(atPath: djinniManifest.path)
    ? .package(name: "djinni", path: "external/djinni")
    : .package(url: "https://github.com/UbiqueInnovation/djinni.git",
               .upToNextMinor(from: "1.0.9"))
```

SwiftPM は git 依存を**再帰 clone する**ので submodule の中身が必ず入る。その結果
「依存パッケージがローカルパス依存を持つ」形になり、解決できない:

```
error: exhausted attempts to resolve the dependencies graph, with the following
dependencies unresolved:
* 'djinni' at .../checkouts/maps-core/external/djinni
```

キャッシュを消した完全な初期状態でも同じなので、こちらの設定では回避できない
（上流の作りの問題）。**ローカルの clone を path 依存にすると解決が通る。**

`Package.swift` は `../maps-core` があればそちらを、無ければ公開リポジトリを見る。
上流が直れば clone を消すだけで元へ戻る。
Google Maps の `ios-maps-sdk/` も同じくローカル clone 運用（どちらも `.gitignore` 済み）。

### submodule は必ず入れること（`--recurse-submodules`）

djinni を空にしても解決は通る（URL へフォールバックする）が、**版が変わる**:

| | djinni |
|---|---|
| maps-core の submodule が指す版 | **1.4.0** |
| URL フォールバックの制約 `.upToNextMinor(from: "1.0.9")` | 1.0.10 |

生成された bridging は submodule の版に対して作られているので、上流が意図する
1.4.0 で使う。空にする回避策は取らない。

### Metal ツールチェーン

maps-core は Metal シェーダを含むので、初回に一度だけ要る:

```bash
xcodebuild -downloadComponent MetalToolchain   # 約 690MB、端末ごとに 1 回
```

Xcode 26 から Metal ツールチェーンは Xcode 本体に含まれなくなり、別ダウンロードに
なった（GUI なら Xcode → Settings → Components → Metal Toolchain）。
入っていないと maps-core のシェーダで
`cannot execute tool 'metal' due to missing Metal Toolchain` と出て落ちる。
CI でも同じコマンドでよい（対話は要らない）。

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
| — | 値の変換（座標 / 色 / ポリゴン）と Actual 型 | 済み |
| — | tilt 擬似表現（2D カメラにピッチが無いため）+ テスト | 済み |
| A | ホルダー（投影 2 つ）と傾き用の入れ物 | 済み |
| C | 地図デザイン型 | 済み |
| H | capability の宣言 | 済み |
| — | レイヤの重ね順と索引の割り当て | 済み |
| D | レンダラ — ポリライン / ポリゴン / 円 | 済み |
| D | レンダラ — グラウンドイメージ / ラスター | 済み |
| — | タイル設定（レベルの縮尺を統一ズームに合わせる）+ テスト | 済み |
| — | カメラ補間（SDK のアニメーションが尺を守らないため）+ テスト | 済み |
| B | コントローラ（カメラ） | 済み |
| E | イベント転送（カメラ / タップ / 長押し） | 済み |
| G | State サブクラス / SwiftUI の入口 | 済み |
| D | レンダラ — マーカー | 済み |
| F | ドラッグ中のパン抑止 | 済み |
| — | InfoBubble / マーカーアニメーションの配線 | 済み |
| — | マーカーのタイル方式（大量マーカー） | これから |
| — | サンプルアプリへの組み込みと実機確認 | これから |

## マーカーのタイル方式が未対応

`MarkerTilingOptions` の経路を通していないので、大量のマーカー（PostOffice ページ）も
ネイティブのアイコンとして描かれる。android 側には実装があり、ローカルのタイルサーバが
返す 404 を「透明な 1x1 PNG の 200」へ書き換える `MCTextureLoader` の派生が要る
（この SDK は 404 をエラー扱いし、そのタイルを「存在しない」と記録するため、
マーカーの無い領域だけ粗い親タイルが透けて残る）。
