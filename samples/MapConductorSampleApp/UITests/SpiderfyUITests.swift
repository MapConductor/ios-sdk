import XCTest

/// On-device verification of the marker-clustering updates ported from the
/// React SDK: prepareExpand, recomputed cluster centers, and spiderfy.
///
/// The app is launched directly on the Post Office Cluster page (MapLibre,
/// Tokyo Station, zoom 13 == spiderfyMinZoom). Cluster screen positions are
/// data-dependent, so the test walks a grid of candidate points near screen
/// center until one tap opens a fan, using the demo's spiderfyStatus overlay
/// (wired to onSpiderfyChange) as the ground truth.
final class SpiderfyUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// 条件が真になるまで待つ。時間ではなく結果を待つための道具。
    private func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        return condition()
    }

    private func waitForLabel(
        _ element: XCUIElement,
        _ expected: String,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists && element.label == expected { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        return element.exists && element.label == expected
    }

    func testSpiderfyOpenCollapseAndPrepareExpand() throws {
        let app = XCUIApplication()
        app.launchEnvironment["MAPCONDUCTOR_SAMPLE_INIT_PAGE"] = "marker-postoffice-cluster"
        app.launchEnvironment["MAPCONDUCTOR_SAMPLE_PROVIDER"] = "maplibre"
        app.launch()

        let status = app.staticTexts["spiderfyStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 30), "status overlay never appeared")

        // prepareExpand must have fired for the initial marker render.
        //
        // 固定 sleep で待たない。マップ読み込み・郵便局データの取り込み・最初のクラスタ描画に
        // かかる時間は端末の状態でかなり変わる（他のテストのあとに走ると目に見えて遅い）。
        // 以前はここが `sleep(15)` + `waitForExistence(5)` だったため、スイート全体を
        // 回したときだけ落ちていた。状態が変わるまで粘る形にして、時間ではなく結果を待つ。
        let prep = app.staticTexts["prepareExpandStatus"]
        XCTAssertTrue(prep.waitForExistence(timeout: 60), "prepareExpand の読み出しが出ない")
        let firedByDeadline = waitUntil(timeout: 120) { prep.label != "prepare:0" }
        attach(app, "01_loaded")
        XCTAssertTrue(firedByDeadline, "prepareExpand never fired on initial render")

        let window = app.windows.firstMatch
        // Cluster layout shifts slightly between runs (camera zoom settles at
        // marginally different values), so fixed positions are unreliable.
        // Walk a dense grid instead — spacing ~78pt is below the cluster
        // marker hit radius (icon + tap tolerance), so any cluster inside the
        // scanned region gets hit. Stop at the first tap that opens a fan.
        var candidates: [(Double, Double)] = []
        for row in 0..<9 {
            for col in 0..<10 {
                let x = 0.08 + Double(col) * (0.84 / 9.0)
                let y = 0.10 + Double(row) * (0.68 / 8.0)
                // Skip the provider dropdown (top-right) and Controls (bottom).
                if y < 0.14 && x > 0.68 { continue }
                candidates.append((x, y))
            }
        }

        var openedAt: XCUICoordinate?
        for (index, frac) in candidates.enumerated() {
            let point = window.coordinate(
                withNormalizedOffset: CGVector(dx: frac.0, dy: frac.1))
            point.tap()
            if waitForLabel(status, "SPIDERFY_ON", timeout: 1.5) {
                attach(app, "02_spiderfy_open_tap\(index)")
                openedAt = point
                break
            }
        }
        guard let clusterPoint = openedAt else {
            attach(app, "02_no_cluster_hit")
            XCTFail("no candidate tap opened a spiderfy fan")
            return
        }

        // Re-tapping the kept cluster marker collapses the fan.
        clusterPoint.tap()
        XCTAssertTrue(
            waitForLabel(status, "SPIDERFY_OFF", timeout: 5),
            "re-tap did not collapse the fan")
        attach(app, "03_retap_collapsed")

        // Open again, then pan the map: recluster must auto-collapse.
        clusterPoint.tap()
        XCTAssertTrue(
            waitForLabel(status, "SPIDERFY_ON", timeout: 5),
            "second open failed")
        attach(app, "04_reopened")

        let dragFrom = window.coordinate(
            withNormalizedOffset: CGVector(dx: 0.50, dy: 0.78))
        let dragTo = window.coordinate(
            withNormalizedOffset: CGVector(dx: 0.64, dy: 0.88))
        dragFrom.press(forDuration: 0.1, thenDragTo: dragTo)
        XCTAssertTrue(
            waitForLabel(status, "SPIDERFY_OFF", timeout: 12),
            "pan-triggered recluster did not collapse the fan")
        attach(app, "05_pan_collapsed")
    }
}
