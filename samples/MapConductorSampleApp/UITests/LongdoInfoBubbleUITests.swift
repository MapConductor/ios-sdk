import XCTest

/// Real-touch verification of Longdo marker taps and InfoBubbles.
///
/// The multiple-info-bubbles page opens all three bubbles on load and toggles a
/// bubble when its marker is tapped; a map (background) tap closes every bubble.
/// Marker 1 sits exactly at the camera center, so its icon hangs just above the
/// view center (bottom-anchored) — a tap slightly above center hits the marker.
final class LongdoInfoBubbleUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func waitUntilGone(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while element.exists && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        return !element.exists
    }

    func testMarkerTapTogglesInfoBubble() throws {
        let app = XCUIApplication()
        app.launchEnvironment["MAPCONDUCTOR_SAMPLE_INIT_PAGE"] = "multiple-info-bubbles"
        app.launchEnvironment["MAPCONDUCTOR_SAMPLE_PROVIDER"] = "longdo"
        app.launch()

        let bubble1 = app.staticTexts["Restaurant A"]
        let bubble2 = app.staticTexts["Hotel B"]
        XCTAssertTrue(bubble1.waitForExistence(timeout: 60), "initial bubbles never appeared")
        XCTAssertTrue(bubble2.exists, "bubble 2 missing on load")
        sleep(3)

        let window = app.windows.firstMatch
        let markerTap = window
            .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .withOffset(CGVector(dx: 0, dy: -20))

        // Tap the marker: only bubble 1 toggles off. A leaked map-click would
        // clear every bubble instead.
        markerTap.tap()
        XCTAssertTrue(waitUntilGone(bubble1, timeout: 10), "marker tap did not toggle bubble 1 off")
        XCTAssertTrue(bubble2.exists, "marker tap must not clear the other bubbles")

        // Tap again: the bubble re-opens (the actual user scenario).
        markerTap.tap()
        XCTAssertTrue(bubble1.waitForExistence(timeout: 10), "marker tap did not re-open bubble 1")
        XCTAssertTrue(bubble2.exists)

        // Background tap far from any marker closes all bubbles.
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.85)).tap()
        XCTAssertTrue(waitUntilGone(bubble1, timeout: 10), "map tap did not close bubble 1")
        XCTAssertTrue(waitUntilGone(bubble2, timeout: 5), "map tap did not close bubble 2")
    }

    /// Long-press pickup drag (custom implementation; the SDK's marker dragging is disabled).
    /// Picks up a store marker on the StoreMap page, drops it in the empty ocean, then taps the
    /// drop point: the info bubble opening there proves the marker really moved.
    func testMarkerLongPressDrag() throws {
        let app = XCUIApplication()
        app.launchEnvironment["MAPCONDUCTOR_SAMPLE_INIT_PAGE"] = "map-basic"
        app.launchEnvironment["MAPCONDUCTOR_SAMPLE_PROVIDER"] = "longdo"
        app.launch()
        sleep(18)

        let window = app.windows.firstMatch
        let bubbleSignal = app.buttons["Get Directions"]
        let dropOffset = CGVector(dx: 0.25, dy: 0.28)
        let dropPoint = window.coordinate(withNormalizedOffset: dropOffset)

        // The isolated north-shore pin sits near (0.41, 0.33); walk a small grid to absorb
        // per-run layout differences.
        var dragged = false
        outer: for dy in [0.0, -0.015, 0.015] {
            for dx in [0.0, -0.02, 0.02] {
                let candidate = window.coordinate(
                    withNormalizedOffset: CGVector(dx: 0.41 + dx, dy: 0.325 + dy)
                )
                candidate.press(forDuration: 0.9, thenDragTo: dropPoint)
                sleep(2)
                dropPoint.tap()
                if bubbleSignal.waitForExistence(timeout: 4) {
                    dragged = true
                    break outer
                }
                // Close anything that opened and reset for the next probe.
                window.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.85)).tap()
                sleep(1)
            }
        }
        XCTAssertTrue(dragged, "long-press drag never moved a marker to the drop point")
    }
}
