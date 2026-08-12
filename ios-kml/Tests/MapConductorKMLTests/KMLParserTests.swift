import XCTest
@testable import MapConductorKML

final class KMLParserTests: XCTestCase {
    private func kml(_ body: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <kml xmlns="http://www.opengis.net/kml/2.2"><Document>\(body)</Document></kml>
        """
    }

    func testParsesPlacemarkWithSharedStyle() throws {
        let features = try KMLParser.parse(
            kml(
                """
                <Style id="s"><LineStyle><color>ff0000ff</color><width>3</width></LineStyle></Style>
                <Placemark>
                  <name>line</name>
                  <styleUrl>#s</styleUrl>
                  <LineString><coordinates>139.7,35.6,0 139.8,35.7,0</coordinates></LineString>
                </Placemark>
                """
            )
        )

        XCTAssertEqual(1, features.count)
        let feature = features[0]
        XCTAssertEqual("line", feature.properties["name"] as? String)
        XCTAssertEqual(3, feature.strokeWidth)
        guard case .lineString(let coordinates) = feature.geometry else {
            return XCTFail("Expected a LineString, got \(feature.geometry)")
        }
        XCTAssertEqual(2, coordinates.count)
        XCTAssertEqual(139.7, coordinates[0].longitude, accuracy: 1e-9)
    }

    func testDeeplyNestedFoldersDoNotOverflowTheStack() throws {
        let depth = 20_000
        var sb = "<?xml version=\"1.0\"?><kml>"
        sb += String(repeating: "<Folder>", count: depth)
        sb += "<Placemark><Point><coordinates>139.7,35.6</coordinates></Point></Placemark>"
        sb += String(repeating: "</Folder>", count: depth)
        sb += "</kml>"

        let features = try KMLParser.parse(sb)

        XCTAssertEqual(1, features.count)
        guard case .point = features[0].geometry else {
            return XCTFail("Expected a Point, got \(features[0].geometry)")
        }
    }

    func testDeeplyNestedMultiGeometryDoesNotOverflowTheStack() throws {
        let depth = 20_000
        var sb = "<?xml version=\"1.0\"?><kml><Placemark>"
        sb += String(repeating: "<MultiGeometry>", count: depth)
        sb += "<Point><coordinates>139.7,35.6</coordinates></Point>"
        sb += String(repeating: "</MultiGeometry>", count: depth)
        sb += "</Placemark></kml>"

        let features = try KMLParser.parse(sb)

        XCTAssertEqual(1, features.count)
        var geometry = features[0].geometry
        var unwrapped = 0
        while case .geometryCollection(let geometries) = geometry {
            XCTAssertEqual(1, geometries.count)
            geometry = geometries[0]
            unwrapped += 1
        }
        XCTAssertEqual(depth, unwrapped)
        guard case .point = geometry else {
            return XCTFail("Expected a Point at the innermost level, got \(geometry)")
        }
    }

    func testMultiGeometryKeepsSiblingLeavesAndNesting() throws {
        let features = try KMLParser.parse(
            kml(
                """
                <Placemark><MultiGeometry>
                  <Point><coordinates>1,2</coordinates></Point>
                  <MultiGeometry>
                    <LineString><coordinates>1,2 3,4</coordinates></LineString>
                  </MultiGeometry>
                  <Polygon><outerBoundaryIs><LinearRing>
                    <coordinates>0,0 1,0 1,1 0,0</coordinates>
                  </LinearRing></outerBoundaryIs></Polygon>
                </MultiGeometry></Placemark>
                """
            )
        )

        guard case .geometryCollection(let geometries) = features[0].geometry else {
            return XCTFail("Expected a GeometryCollection, got \(features[0].geometry)")
        }
        XCTAssertEqual(3, geometries.count)
        guard case .point = geometries[0] else {
            return XCTFail("Expected a Point, got \(geometries[0])")
        }
        guard case .geometryCollection(let nested) = geometries[1] else {
            return XCTFail("Expected a nested GeometryCollection, got \(geometries[1])")
        }
        guard case .lineString = nested[0] else {
            return XCTFail("Expected a LineString, got \(nested[0])")
        }
        guard case .polygon = geometries[2] else {
            return XCTFail("Expected a Polygon, got \(geometries[2])")
        }
    }

    func testCollectsNetworkLinksIncludingLegacyUrlTag() throws {
        let document = try KMLParser.parseDocument(
            data: Data(
                kml(
                    """
                    <NetworkLink><Link><href>https://example.com/a.kml</href></Link></NetworkLink>
                    <Folder>
                      <NetworkLink><visibility>0</visibility><Link><href>hidden.kml</href></Link></NetworkLink>
                      <NetworkLink><Url><href>legacy.kml</href></Url></NetworkLink>
                    </Folder>
                    <Placemark><Point><coordinates>1,2</coordinates></Point></Placemark>
                    """
                ).utf8
            )
        )

        XCTAssertEqual(1, document.features.count)
        XCTAssertEqual(3, document.networkLinks.count)
        XCTAssertEqual("https://example.com/a.kml", document.networkLinks[0].href)
        XCTAssertEqual(false, document.networkLinks[1].visibility)
        XCTAssertEqual("legacy.kml", document.networkLinks[2].href)
    }

    func testParsesKmzArchiveUsingFirstKmlEntry() throws {
        let bytes = Self.storedZip([
            (name: "images/icon.png", data: Data([1, 2, 3])),
            (
                name: "doc.kml",
                data: Data(
                    kml("<Placemark><Point><coordinates>139.7,35.6</coordinates></Point></Placemark>").utf8
                )
            ),
        ])

        let features = try KMLParser.parse(data: bytes)

        XCTAssertEqual(1, features.count)
        guard case .point = features[0].geometry else {
            return XCTFail("Expected a Point, got \(features[0].geometry)")
        }
    }

    func testKmzWithoutKmlEntryThrows() {
        let bytes = Self.storedZip([
            (name: "readme.txt", data: Data("no kml here".utf8)),
        ])

        XCTAssertThrowsError(try KMLParser.parse(data: bytes)) { error in
            guard case KMLParseError.kmzWithoutKMLEntry = error else {
                return XCTFail("Expected KMLParseError.kmzWithoutKMLEntry, got \(error)")
            }
        }
    }

    // MARK: - Fixtures

    /// Builds an in-memory ZIP archive using the Stored (uncompressed) method.
    private static func storedZip(_ entries: [(name: String, data: Data)]) -> Data {
        var out = Data()
        var central = Data()
        for (name, data) in entries {
            let nameBytes = Data(name.utf8)
            let localOffset = UInt32(out.count)

            // Local file header
            append32(&out, 0x0403_4b50)
            append16(&out, 20)                       // version needed
            append16(&out, 0)                        // flags
            append16(&out, 0)                        // method: Stored
            append16(&out, 0)                        // time
            append16(&out, 0)                        // date
            append32(&out, 0)                        // crc (unchecked by the reader)
            append32(&out, UInt32(data.count))       // compressed size
            append32(&out, UInt32(data.count))       // uncompressed size
            append16(&out, UInt16(nameBytes.count))  // name length
            append16(&out, 0)                        // extra length
            out.append(nameBytes)
            out.append(data)

            // Central directory header
            append32(&central, 0x0201_4b50)
            append16(&central, 20)                       // version made by
            append16(&central, 20)                       // version needed
            append16(&central, 0)                        // flags
            append16(&central, 0)                        // method: Stored
            append16(&central, 0)                        // time
            append16(&central, 0)                        // date
            append32(&central, 0)                        // crc
            append32(&central, UInt32(data.count))       // compressed size
            append32(&central, UInt32(data.count))       // uncompressed size
            append16(&central, UInt16(nameBytes.count))  // name length
            append16(&central, 0)                        // extra length
            append16(&central, 0)                        // comment length
            append16(&central, 0)                        // disk number
            append16(&central, 0)                        // internal attributes
            append32(&central, 0)                        // external attributes
            append32(&central, localOffset)              // local header offset
            central.append(nameBytes)
        }
        let centralOffset = UInt32(out.count)
        let centralSize = UInt32(central.count)
        out.append(central)

        // End of central directory
        append32(&out, 0x0605_4b50)
        append16(&out, 0)                           // disk number
        append16(&out, 0)                           // central directory disk
        append16(&out, UInt16(entries.count))       // entries on this disk
        append16(&out, UInt16(entries.count))       // total entries
        append32(&out, centralSize)
        append32(&out, centralOffset)
        append16(&out, 0)                           // comment length
        return out
    }

    private static func append16(_ data: inout Data, _ value: UInt16) {
        data.append(UInt8(value & 0xff))
        data.append(UInt8(value >> 8))
    }

    private static func append32(_ data: inout Data, _ value: UInt32) {
        data.append(UInt8(value & 0xff))
        data.append(UInt8((value >> 8) & 0xff))
        data.append(UInt8((value >> 16) & 0xff))
        data.append(UInt8((value >> 24) & 0xff))
    }
}
