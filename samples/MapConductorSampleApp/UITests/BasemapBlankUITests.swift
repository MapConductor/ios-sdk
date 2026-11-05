import XCTest

/**
 スタイルを当てているあいだ、バックエンド自身のベースマップを消すこと。
 そして「Adjust the map's own style」のときは**消さない**こと。

 Google Maps は自分のラベル・路線記号・POI をタイルオーバーレイの**上**に
 描くので、消さないと調整済みのスタイルの上に Google の地名が全部乗る。
 消しすぎると今度はトグルを入れたときに白紙になる。両方を見る。
 */
final class BasemapBlankUITests: XCTestCase {
    func testGoogleBasemapIsOffWithAStyleAndBackOnForCurrentDesign() {
        let app = XCUIApplication()
        app.launchEnvironment["MAPCONDUCTOR_SAMPLE_INIT_PAGE"] = "vector-style"
        app.launchEnvironment["MAPCONDUCTOR_SAMPLE_PROVIDER"] = "googlemaps"
        app.launch()
        XCTAssertTrue(
            app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'schema:'")).firstMatch
                .waitForExistence(timeout: 120),
            "スタイルが出ない"
        )
        Thread.sleep(forTimeInterval: 10)
        let blanked = XCTAttachment(screenshot: app.screenshot())
        blanked.name = "google-blanked"
        blanked.lifetime = .keepAlways
        add(blanked)

        let toggle = app.switches["currentDesignToggle"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 20), "トグルが無い")
        // SwiftUI の Toggle は要素の中心が行全体になることがあり、`tap()` が
        // ラベル側に落ちて切り替わらない。右端（つまみ側）を狙う。
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        Thread.sleep(forTimeInterval: 12)
        let restored = XCTAttachment(screenshot: app.screenshot())
        restored.name = "google-restored"
        restored.lifetime = .keepAlways
        add(restored)

        // 戻したあとも操作を受け付けること（白紙のまま固まらない）。
        XCTAssertTrue(app.buttons["Roads"].firstMatch.isHittable, "トグル後に UI が死んでいる")

        // 画の代わりにこれを見る: Google は自分のベクタースタイルを持たない
        // ので、`CurrentDesign` では「調整するものが無い」と報告する。その
        // 行が出ているなら、ベースマップを戻す側の経路が生きている。
        // （戻していなければ白紙の上にこの文言だけが出る。)
        let noStyle = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS 'not drawing a vector style'")
        ).firstMatch
        XCTAssertEqual(toggle.value as? String, "1", "トグルが切り替わっていない")
        XCTAssertTrue(
            noStyle.waitForExistence(timeout: 30),
            "CurrentDesign に切り替えたのに、調整対象が無い旨の報告が出ない"
        )
    }
}
