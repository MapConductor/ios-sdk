import MapConductorCore
import XCTest

@testable import MapConductorVectorStyle

/**
 The whole chain: Rust compiler, C ABI, Swift.

 What is being checked is not the compiler -- that has its own tests and
 golden files in Rust -- but that this binding carries the answer across
 unchanged. The numbers asserted here are the ones
 `crates/mvt-style/tests/golden/versatiles-road-emphasis.json` records, so a
 binding that quietly loses or mangles something fails rather than producing
 a slightly different map.

 The same assertions exist in `VectorStyleRulesTest` on Android and in
 `bindings/js-style/test/compile.test.mjs`.
 */
final class VectorStyleRulesTests: XCTestCase {
    private lazy var style: String = {
        guard
            let url = Bundle.module.url(forResource: "versatiles-colorful", withExtension: "json"),
            let text = try? String(contentsOf: url, encoding: .utf8)
        else {
            XCTFail("the fixture is missing")
            return ""
        }
        return text
    }()

    private let roadEmphasis = """
        {
          "schemaVersion": 1,
          "rules": [
            { "selector": "all", "patch": { "color": "#000000" } },
            { "selector": { "role": "label" }, "patch": { "visible": false } },
            { "selector": { "role": "road-casing" }, "patch": { "color": "#303030" } },
            { "selector": { "role": "road" }, "patch": { "color": "#ffffff", "widthScale": 1.3 } }
          ]
        }
        """

    func testAdjustsARealStyleAndSaysWhatItDid() throws {
        let compiled = try VectorStyleRules.compile(styleJSON: style, rulesJSON: roadEmphasis)

        XCTAssertEqual(compiled.affects, .both)
        XCTAssertTrue(compiled.patchable, "this style has a background already")
        // The same counts the Rust golden records, reached through the C ABI.
        XCTAssertTrue(
            compiled.diagnostics.contains { $0.contains("schema: shortbread") },
            compiled.diagnostics.joined(separator: "\n")
        )
        XCTAssertTrue(
            compiled.diagnostics.contains { $0.contains("rule 3 matched 77 layers") },
            compiled.diagnostics.joined(separator: "\n")
        )

        XCTAssertGreaterThan(compiled.mutations.count, 400)
        // Every mutation carries what was there before, or nothing could be
        // taken back when the rules change.
        for mutation in compiled.mutations.prefix(50) {
            XCTAssertNotNil(mutation.reversed())
        }

        let parsed = try JSONSerialization.jsonObject(with: Data(compiled.styleJSON.utf8))
        let layers = (parsed as? [String: Any])?["layers"] as? [[String: Any]]
        XCTAssertEqual(layers?.count, 280, "no layer was added or lost")
    }

    func testLeavesAloneWhatNoRuleNamed() throws {
        let compiled = try VectorStyleRules.compile(
            styleJSON: style,
            rulesJSON: ##"{"schemaVersion":1,"rules":[{"selector":{"role":"water"},"patch":{"color":"#000"}}]}"##
        )
        let before = try JSONSerialization.jsonObject(with: Data(style.utf8)) as? [String: Any]
        let after =
            try JSONSerialization.jsonObject(with: Data(compiled.styleJSON.utf8)) as? [String: Any]
        XCTAssertEqual(
            (before?["sources"] as? NSDictionary), (after?["sources"] as? NSDictionary)
        )
        XCTAssertEqual(before?["name"] as? String, after?["name"] as? String)
    }

    func testDescribesWhatIsInAStyle() throws {
        let layers = try VectorStyleRules.describe(styleJSON: style)
        XCTAssertEqual(layers.count, 280)
        let casing = try XCTUnwrap(
            layers.first { $0.id.hasSuffix(":outline") && $0.roles.contains("road") })
        XCTAssertEqual(casing.roles, ["road", "road-casing"])
        XCTAssertEqual(casing.evidence.first, "shortbread:streets")
    }

    /// A rule set written for a newer build must be refused loudly, not
    /// applied in part.
    func testRefusesARulesDocumentItDoesNotUnderstand() {
        XCTAssertThrowsError(
            try VectorStyleRules.compile(
                styleJSON: style, rulesJSON: #"{"schemaVersion":99,"rules":[]}"#)
        ) { error in
            XCTAssertTrue(
                (error as? VectorStyleError)?.message.contains("schemaVersion") == true,
                "\(error)"
            )
        }
    }

    func testRefusesAStyleItCannotRead() {
        XCTAssertThrowsError(
            try VectorStyleRules.compile(
                styleJSON: "{ not json", rulesJSON: #"{"schemaVersion":1,"rules":[]}"#)
        )
        XCTAssertThrowsError(try VectorStyleRules.describe(styleJSON: "{ not json"))
    }

    func testReportsTheRulesVersionItWasBuiltWith() {
        XCTAssertEqual(VectorStyleRules.schemaVersion, 1)
    }

    /// The mutations have to survive the trip through core's parser with
    /// their values intact -- a colour that lost its quotes is a colour no
    /// renderer can read back.
    func testMutationsArriveAsCoreTypesWithTheirValues() throws {
        let compiled = try VectorStyleRules.compile(
            styleJSON: style,
            rulesJSON:
                ##"{"schemaVersion":1,"rules":[{"selector":{"layerId":"background"},"patch":{"color":"#010203"}}]}"##
        )
        let single = try XCTUnwrap(compiled.mutations.first)
        guard case let .setPaint(layerId, key, value, previous) = single else {
            return XCTFail("expected a paint mutation, got \(single)")
        }
        XCTAssertEqual(compiled.mutations.count, 1)
        XCTAssertEqual(layerId, "background")
        XCTAssertEqual(key, "background-color")
        XCTAssertEqual(value, "\"#010203\"")
        // The document says `rgb(248,244,240)`; what comes back is the same
        // colour written the one way every renderer can read -- which this
        // provider's MapLibre adapter is the reason for.
        XCTAssertEqual(previous, "\"#f8f4f0\"")
    }
}
