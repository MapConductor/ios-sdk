import Foundation
import XCTest

@testable import MapConductorSampleApp

/// The Boston page's MCPG v2 decoding (BostonData.swift). The same fixture is
/// decoded by the React (bostonData.test.ts) and Android (BostonDataTest.kt) tests.
final class BostonDataTests: XCTestCase {
    /// Two polygons with every field (fields = 15), written by the generator (the React
    /// sample's tools/boston/fixture.py): the same polygons at 1e-6 and at 1e-5 degree.
    private let fixture = hexData(
        "4d43504702000000020000000f067c020109436166c3a920e298950204f4abb228a7b0e24300d00fd00f0000cf0f03db0bd804"
            + "d8040000a006000802000103ffea068ff40414142700"
    )
    private let fixture5 = hexData(
        "4d43504702000000020000000f057c020109436166c3a920e298950204b284850483b8e30600c801c8010000c7010395013c3c"
            + "000050000802000103bf57e73e02020300"
    )

    private static func hexData(_ hex: String) -> Data {
        var bytes: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            bytes.append(UInt8(hex[index..<next], radix: 16)!)
            index = next
        }
        return Data(bytes)
    }

    private func assertRing(_ ring: [Double], _ expected: [Double], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(ring.count, expected.count, file: file, line: line)
        for (a, b) in zip(ring, expected) { XCTAssertEqual(a, b, accuracy: 1e-9, file: file, line: line) }
    }

    func testDecodesEveryFieldAndClosesEachRingAgain() throws {
        try assertDecodesEveryField(fixture)
    }

    func testDecodesEveryFieldAt1e5Degree() throws {
        try assertDecodesEveryField(fixture5)
    }

    private func assertDecodesEveryField(_ bytes: Data) throws {
        let polygons = try BostonDataLoader.decode(bytes, idPrefix: "t")
        XCTAssertEqual(polygons.count, 2)

        let first = polygons[0]
        XCTAssertEqual(first.id, "t-0")
        XCTAssertEqual(first.height, 12.3)
        XCTAssertEqual(first.use, .condo)
        XCTAssertEqual(first.level, 1)
        XCTAssertEqual(first.name, "Café ☕")
        XCTAssertEqual(first.rings.count, 2)
        assertRing(first.rings[0], [-71.0605, 42.35545, -71.0595, 42.35545, -71.0595, 42.35645, -71.0605, 42.35645, -71.0605, 42.35545])
        assertRing(first.rings[1], [-71.0602, 42.3557, -71.0602, 42.356, -71.0598, 42.356, -71.0602, 42.3557])

        let second = polygons[1]
        XCTAssertEqual(second.id, "t-1")
        XCTAssertNil(second.height)
        XCTAssertEqual(second.use, .unknown)
        XCTAssertEqual(second.level, 2)
        XCTAssertNil(second.name)
        assertRing(second.rings[0], [-71.1, 42.3, -71.09999, 42.30001, -71.09999, 42.29999, -71.1, 42.3])
    }

    func testRejectsAVersion1File() {
        var v1 = fixture
        v1[4] = 1
        XCTAssertThrowsError(try BostonDataLoader.decode(v1, idPrefix: "t"))
    }

    func testTheBundledDowntownFileHasEveryBuildingOfTheThreeAreas() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "boston-downtown", withExtension: "bin"))
        let polygons = try BostonDataLoader.decode(Data(contentsOf: url), idPrefix: "downtown")
        XCTAssertEqual(polygons.count, 9467)
        XCTAssertEqual(polygons.reduce(0) { $0 + $1.vertexCount }, 73289)
        XCTAssertEqual(polygons.reduce(0) { $0 + $1.rings.count }, 9504)
        XCTAssertEqual(Dictionary(grouping: polygons, by: \.level).mapValues(\.count), [0: 605, 1: 2222, 2: 6640])
        XCTAssertEqual(polygons.filter { $0.height == nil }.count, 362)
        XCTAssertEqual(polygons.filter { $0.name != nil }.count, 762)
        XCTAssertEqual(Set(polygons.map(\.id)).count, 9467)
        let first = try XCTUnwrap(polygons.first)
        XCTAssertEqual(first.height, 5.2)
        XCTAssertEqual(first.level, 2)
        assertRing(Array(first.rings[0][0..<2]), [-71.076105, 42.373684])
        assertRing(Array(first.rings[0][16..<18]), [-71.076105, 42.373684])
    }

    func testTheBundledCityBuildingsFileHasEveryBuildingAt1e6Degree() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "boston-city-buildings", withExtension: "bin"))
        let bytes = try Data(contentsOf: url)
        XCTAssertEqual(bytes[13], 6)
        let polygons = try BostonDataLoader.decode(bytes, idPrefix: "buildings")
        XCTAssertEqual(polygons.count, 105_599)
        XCTAssertEqual(polygons.reduce(0) { $0 + $1.vertexCount }, 722_875)
    }

    func testTheBundledCityParcelsFileHasEveryParcelWithALandUseAt1e5Degree() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "boston-city-parcels", withExtension: "bin"))
        let bytes = try Data(contentsOf: url)
        XCTAssertEqual(bytes[13], 5)
        let polygons = try BostonDataLoader.decode(bytes, idPrefix: "parcels")
        XCTAssertEqual(polygons.count, 98_815)
        XCTAssertEqual(polygons.reduce(0) { $0 + $1.vertexCount }, 774_844)
        XCTAssertTrue(polygons.allSatisfy { $0.use != nil && $0.rings.allSatisfy { $0.count >= 8 } })
    }

    func testAreaIsTheOutlineLessItsHoles() throws {
        let polygon = try BostonDataLoader.decode(fixture, idPrefix: "t")[0]
        let outline = BostonBuilding(id: "o", level: 0, height: nil, name: nil, use: nil, rings: [polygon.rings[0]])
        let hole = BostonBuilding(id: "h", level: 0, height: nil, name: nil, use: nil, rings: [polygon.rings[1]])
        XCTAssertEqual(polygon.areaSquareMetres, outline.areaSquareMetres - hole.areaSquareMetres, accuracy: 1e-6)
        // About 82 m x 111 m.
        XCTAssertEqual(outline.areaSquareMetres, 9100, accuracy: 100)
    }
}
