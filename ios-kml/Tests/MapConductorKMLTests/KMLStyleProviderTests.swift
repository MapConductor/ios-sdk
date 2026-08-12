import UIKit
import XCTest
@testable import MapConductorKML

final class KMLStyleProviderTests: XCTestCase {
    func testDefaultProviderUsesFeatureValuesBeforeLayerDefaults() {
        let defaults = KMLTileRenderer.LayerStyle(
            strokeColor: .red,
            fillColor: .green,
            strokeWidth: 3,
            pointRadius: 4
        )
        let feature = KMLFeature(
            geometry: .empty,
            strokeColor: .blue,
            pointRadius: 40
        )

        let style = DefaultKMLStyleProvider.shared.style(for: feature, defaultStyle: defaults)

        XCTAssertEqual(UIColor.blue, style.strokeColor)
        XCTAssertEqual(UIColor.green, style.fillColor)
        XCTAssertEqual(3, style.strokeWidth)
        XCTAssertEqual(40, style.pointRadius)
    }
}
