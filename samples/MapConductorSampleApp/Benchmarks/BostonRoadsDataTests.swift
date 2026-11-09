import Foundation
import XCTest

@testable import MapConductorSampleApp

/// The Boston roads page's decoding (MCPG v2 with the road class and lines bits,
/// BostonRoadsData.swift). The same fixture is decoded by the React and Android tests
/// (written by the React sample's tools/boston/fixture.py).
final class BostonRoadsDataTests: XCTestCase {
    /// Two roads, fields = name | road class | lines, 1e-5 degree: a multi-byte name,
    /// an open three-point path, and a nameless two-point path stepping back south-west.
    private let fixture = hexData(
        "4d4350470200000002000000380510436166c3a92053747265657420e29895010103b284850483b8e30614140a2800060102ef56973e1313"
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

    private func assertPoints(_ points: [Double], _ expected: [Double], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(points.count, expected.count, file: file, line: line)
        for (a, b) in zip(points, expected) { XCTAssertEqual(a, b, accuracy: 1e-9, file: file, line: line) }
    }

    func testDecodesTheRoadsWithoutClosingThem() throws {
        let roads = try BostonRoadsLoader.decode(fixture)
        XCTAssertEqual(roads.count, 2)

        let first = roads[0]
        XCTAssertEqual(first.id, "roads-0")
        XCTAssertEqual(first.name, "Café Street ☕")
        XCTAssertEqual(first.road, .primary)
        assertPoints(first.points, [-71.0605, 42.35545, -71.0604, 42.35555, -71.0602, 42.3556])

        let second = roads[1]
        XCTAssertEqual(second.id, "roads-1")
        XCTAssertNil(second.name)
        XCTAssertEqual(second.road, .path)
        assertPoints(second.points, [-71.1, 42.3, -71.1001, 42.2999])
    }

    func testAPolygonFileIsNotRoads() {
        var polygons = fixture
        polygons[12] = 8 | 16 // the lines bit off
        XCTAssertThrowsError(try BostonRoadsLoader.decode(polygons))
    }

    func testTheLengthIsTheGeodesicSumOfTheSegments() throws {
        let road = try BostonRoadsLoader.decode(fixture)[0]
        // About 13.7 m + 17.4 m.
        XCTAssertEqual(road.lengthMetres, 31.1, accuracy: 0.5)
    }

    func testClassesAreStyledBiggerRoadsWiderAndHigher() {
        XCTAssertEqual(RoadClass.allCases.map(\.width), [5, 4, 3.5, 3, 2, 1.5, 1])
        XCTAssertEqual(RoadClass.allCases.map(\.zIndex), [6, 5, 4, 3, 2, 1, 0])
    }

    func testTheBundledFileHasEveryRoadOfTheCity() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "boston-city-roads", withExtension: "bin"))
        let bytes = try Data(contentsOf: url)
        XCTAssertEqual(bytes.count, 1_019_811)
        XCTAssertEqual(bytes[13], 5)
        let roads = try BostonRoadsLoader.decode(bytes)
        XCTAssertEqual(roads.count, 54_645)
        XCTAssertEqual(roads.reduce(0) { $0 + $1.vertexCount }, 234_765)
        XCTAssertEqual(roads.filter { $0.name != nil }.count, 18_838)
        let byClass = Dictionary(grouping: roads, by: \.road).mapValues(\.count)
        XCTAssertEqual(byClass, [
            .highway: 911, .primary: 2_320, .secondary: 2_829, .tertiary: 1_229,
            .local: 11_226, .service: 9_950, .path: 26_180,
        ])
        XCTAssertEqual(roads[0].name, "Saint Vincent Section")
        XCTAssertEqual(roads[0].road, .service)
        XCTAssertEqual(roads[0].vertexCount, 9)
        assertPoints(Array(roads[0].points[0..<2]), [-71.1858, 42.28788])
    }
}
