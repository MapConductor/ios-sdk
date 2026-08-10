# 地図SDKドライバーの書き方（iOS）

このモジュールは **動く最小のドライバー** です。読んで、コピーして、`Template` を
あなたの地図SDK名に置き換えるところから始めてください。

`TemplateMap` が「あなたが使う地図SDK」の代役です。**置き換えるのはそこだけ**で、
まわりのホルダー・コントローラ・レンダラの**形はそのまま**使えます。

android-sdk の `android-for-template`、react-sdk の `react-for-template` と
**同じ構造**にしてあります。3 プラットフォームを少人数で保守するための前提です。

---

## 1. 何を書くのか

| # | 実装点 | 個数 | ファイル |
|---|---|---|---|
| A | ホルダー — `mapView` / `map` / 投影 2 つ | 4 | `TemplateMap.swift` |
| B | コントローラ — `holder` / カメラ読み書き / `fitBounds` | 5 | `TemplateMapViewController.swift` |
| C | 地図デザイン型 | 3 | `TemplateMap.swift` |
| D | **レンダラ 6 種 × create / update / remove** | 25 | `TemplateOverlays.swift` |
| E | SDK イベントの転送 | 6 | `installListeners()` |
| F | ドラッグ中のパン抑止 | 1 | `TemplateMarkerDragSurface` |
| G | State サブクラス | 3 | `TemplateMapView.swift` |
| H | capability の宣言 | 1 | `declareCapabilities(into:)` |

D と A（29 個）は SDK 固有の翻訳なので減らせません。残りはほぼ定型です。

## 2. 何を書かなくてよいのか

以下はすべてコアが持っています。**書き始める前にこの一覧を読んでください。**
移行前のプロバイダはこれらを各自で書いており、それが重複の正体でした。

- **クリックのカスケード** — `marker → circle → groundImage → polyline → polygon → map`。
  `dispatchOverlayTap(position:)` を呼ぶだけ。移行前は iOS だけで 3 通りの順序があり、
  ios-for-longdo にいたっては先勝ちが無く全部に配送していました。
- **オーバーレイの当たり判定** — 各 `Manager` が持っています（測地線ポリゴンの
  巻き数判定、穴の除外、球面距離、線分への近接）。
- **`clickable = false` の透過** — 握り潰しではなく次の層へ流します。
- **マーカーのヒットテスト** — `AbstractMarkerController.find`。
- **Capable ファサード** — `registerOverlayController` するだけで既定が働きます。
- **マーカーのタップ／ドラッグの状態遷移** — `DefaultMarkerEventController`。
  「掴む前の `isScrollEnabled` へ戻す」もコアがやります。
- **VisibleRegion の組み立て** — `holder.buildVisibleRegion()` が 4 隅を逆投影します。
- **ズームの往復換算** — `WebMercatorZoomAltitudeConverter`。
- **オーバーレイの差分計算** — `OverlayCollector` + `bindOverlayCollector`。

## 3. 手順

1. `ios-for-template` をコピーして `ios-for-<sdk>` にする
2. `TemplateMap.swift` の `TemplateMap` を実際の SDK の地図型に置き換える
3. `TemplateOverlays.swift` の 6 レンダラを SDK のオブジェクト生成に書き換える（**ここが本体**）
4. `TemplateMapViewController.swift` のカメラ換算とイベント転送を SDK に合わせる
5. `TemplateMapView.swift` の `Color.clear` を `UIViewRepresentable { SDK の MapView }` に置き換える
6. `TemplateDriverConformanceTests.swift` をそのまま動かす
7. **実機で確かめる**（§5）

```bash
xcodebuild test -scheme mapconductor-for-template \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  SWIFT_ENABLE_EXPLICIT_MODULES=NO
```

---

## 4. つまずくところ（実際に作り込んだ不具合）

### 4-1. コントローラを `registerOverlayController` し忘れる

Capable ファサードもクリックカスケードも**黙って**効かなくなります。
「追加したのに表示されない」「タップしても無反応」の大半はこれです。

移行時に調べたところ、**iOS 9 プロバイダ / react 13 プロバイダのどれ 1 つとして
呼んでいませんでした**（全部に追加が必要だった）。

→ `MapDriverConformance.checkOverlaySlots()` が 1 本で捕まえます。必ず入れてください。

### 4-2. `SlottedOverlayController` を実装し忘れる

**Swift は Kotlin と違い、プロトコル適合を書き忘れてもコンパイルが通ります。**
`registerOverlayController` は `AnyOverlayController` を受けるので型エラーになりません。
コアのコントローラ（`CircleController` など）を継承していれば付いてきますが、
**継承せず自前で組んだ**とき（複数レンダラを束ねる「コンダクタ」を作りたくなったとき）に漏れます。

実際 maplibre / maptiler / mapbox の `GroundImageController` がこれで、
スロットに載っていませんでした。

### 4-3. `viewportSizePx()` を書き忘れる

`visibleRegion` が**黙って nil** になります。既定実装は `mapView as? UIView` の
`bounds.size` なので、地図ビューが `UIView` なら書かなくてよく、そうでなければ必須です。
`TemplateDriverConformanceTests.testCameraRoundTrips` が見ています。

（この雛形を書いている最中に、コア側の `viewportSizePx()` がプロトコル要件では
なく拡張にしか無く、**ドライバーが override しても呼ばれない**ことが判明しました。
要件へ移して直してあります。雛形が最初に見つけた不具合です。）

### 4-4. マーカーのドラッグで参照の持ち方を間違える

`DefaultMarkerEventController` に渡す `MarkerDragSurface` は、その場で作る薄い
アダプタです。**コアが強参照で持ちます**（他に持ち主がいないため）。
逆に `MarkerEventHostProtocol` の実装が持つマーカーコントローラは
**weak にしてください**（コントローラ側がイベントコントローラを強参照しているため）。

移行中にコアが `surface` を weak で持っていて、**ドラッグだけが黙って死にました**。
タップは `surface` を使わないので通ってしまい、クリックの実機確認では気づけません。

### 4-5. `getMapViewHolder()` の絞り込みを消す

State サブクラスの `getMapViewHolder()` は戻り型を絞るためだけに見えますが、
消すとアプリ側の `state.getMapViewHolder()?.map` が静的型を失います（ソース非互換）。
**1 行に縮めるのは可、消すのは不可。** `scripts/api-surface.sh check` が落とします。

### 4-6. `unsupported` と `unknown` を混同する

宣言が無い（`unknown`）は「まだ宣言していない」であって「使えない」ではありません。
地図の初期化途中もここに入ります。`unsupported` にすると**コアが動いている機能を止めます**。
別経路で動いているなら `degraded` / `approximated` にしてください。**理由は必ず書く**
（書かないと診断ログがアプリ開発者に何も伝えません）。

---

## 5. 実機で確かめること

適合テストが緑でも、以下は**実機でしか確かめられません**。

| ページ | 回帰を示す症状 |
|---|---|
| `marker-basic` | 吹き出しが出ない / 地図イベントも同時に飛ぶ（＝カスケードが止まっていない） |
| `circle` / `groundImage` | 内側でイベントが出ない、外側で出る |
| `polyline-click` | 表示座標がタップ点になっている（線上の最近点でなければならない） |
| `polygon-click` | Inside/Outside 判定、座標が `-180..180` に収まる |
| `polygon-hole` | 穴の中が Outside になる |
| `polygon-basic` | 頂点マーカーのドラッグ（§5-1） |

### 5-1. マーカードラッグの偽陽性の罠

**前後比較では検出できません。** 指を離すとマーカーは最終位置へスナップするので、
壊れていても「開始前」と「終了後」のスクショは正しく見えます。壊れ方は
**「ドラッグ中だけ指に追従しない」**。したがって**指が下りている間**のフレームを
撮る必要があります。

XCUITest のジェスチャ API はメインスレッドを塞ぐので、
`press(forDuration:thenDragTo:withVelocity:thenHoldForDuration:)` で指を下ろしたまま
止め、その間に別キューからスクリーンショットを撮ります。

加えて **「離した後に地図をパンできるか」** を必ず確認してください
（`isScrollEnabled` を掴む前の値へ戻す経路）。

---

## 6. 適合スイート

```swift
try MapDriverConformance.checkOverlaySlots(controller.overlayControllers.all())
try MapDriverConformance.checkZoomConverter(controller.zoomConverter)
try MapDriverConformance.checkCascadeOrder()
try MapDriverConformance.checkCapabilityDeclarations(registry)
try MapDriverConformance.checkProjectionRoundTrip(toScreen:fromScreen:samples:)
```

XCTest に依存しない（素の関数と例外だけ）ので、どのテストランナーからでも使えます。
android-sdk / react-sdk にも同じ名前・同じ 5 つのチェックがあります。
