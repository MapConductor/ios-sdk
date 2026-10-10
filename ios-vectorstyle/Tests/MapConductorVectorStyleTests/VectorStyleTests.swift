import MapConductorCore
import UIKit
import XCTest

@testable import MapConductorVectorStyle

/**
 What ``VectorStyle`` does to a map, against a map that is only a recorder.

 No provider is involved on purpose. What is being checked is the contract
 every provider will be held to -- which route a backend's capabilities put
 it on, that changing the rules does not reload anything, and that disposing
 leaves nothing behind -- and a fake host is the only way to check all of
 those without three real maps.

 Kept in step with `VectorStyleTest` on Android.
 */
final class VectorStyleTests: XCTestCase {
    private let style = """
        {"version":8,"name":"test",
         "sources":{"s":{"type":"vector","tiles":["https://x/{z}/{x}/{y}"],"attribution":"© Someone"}},
         "layers":[
           {"id":"bg","type":"background","paint":{"background-color":"#f8f4f0"}},
           {"id":"water","type":"fill","source":"s","source-layer":"water","paint":{"fill-color":"#a0c8f0"}},
           {"id":"roads","type":"line","source":"s","source-layer":"transportation",
            "paint":{"line-color":"#888","line-width":2}},
           {"id":"labels","type":"symbol","source":"s","source-layer":"place","paint":{"text-color":"#333"}}
         ]}
        """

    private func rules(_ color: String) -> StyleRules {
        StyleRules.parse(
            #"{"schemaVersion":1,"rules":[{"selector":{"role":"road"},"patch":{"color":"\#(color)"}}]}"#
        )
    }

    // MARK: - the fake map

    private final class Host: MapStyleHost, @unchecked Sendable {
        let registry = MutableMapServiceRegistry()
        private let lock = NSLock()
        private var _shown: [String?] = []
        private var _applied: [[StyleMutation]] = []
        private var _diagnostics: [String] = []
        private var _credited: [String] = []
        var rasters: [String] = []
        var styleLoadedAttached = false
        let vectorStyleUrl: String?

        /// Set to fail the mutations whose key matches, as iOS MapLibre does.
        var refuse: @Sendable (StyleMutation) -> Bool = { _ in false }

        var shown: [String?] { lock.lock(); defer { lock.unlock() }; return _shown }
        var applied: [[StyleMutation]] { lock.lock(); defer { lock.unlock() }; return _applied }
        var diagnostics: [String] { lock.lock(); defer { lock.unlock() }; return _diagnostics }
        var credited: [String] { lock.lock(); defer { lock.unlock() }; return _credited }

        private final class Vector: VectorStyleSupport {
            let host: Host
            init(_ host: Host) { self.host = host }
            func showStyle(url: String, attributionRules: [AttributionRule]) {
                host.lock.lock()
                host._shown.append(url)
                host._credited.append(contentsOf: attributionRules.map(\.attribution))
                host.lock.unlock()
            }

            func clearStyle() {
                host.lock.lock()
                host._shown.append(nil)
                host.lock.unlock()
            }
        }

        lazy var store = StyleMutationStore { [weak self] list in
            guard let self else { return [] }
            lock.lock()
            _applied.append(list)
            lock.unlock()
            return list.filter(refuse)
        }

        init(vector: Bool, mutations: Bool, vectorStyleUrl: String? = nil) {
            self.vectorStyleUrl = vectorStyleUrl
            if vector { registry.put(VectorStyleSupportKey.self, Vector(self)) }
            if mutations { registry.put(VectorStyleMutationSupportKey.self, store) }
        }

        var serviceRegistry: MapServiceRegistry { registry }
        var tileServer: LocalTileServer { TileServerRegistry.get() }

        func onStyleLoaded(_: @escaping () -> Void) -> MapStyleInstallation {
            styleLoadedAttached = true
            return MapStyleInstallation(dispose: { [weak self] in self?.styleLoadedAttached = false })
        }

        func upsertRaster(_ state: RasterLayerState) { rasters.append(state.id) }
        func removeRaster(id: String) { rasters.removeAll { $0 == id } }

        func report(_ diagnostics: [String]) {
            lock.lock()
            _diagnostics.append(contentsOf: diagnostics)
            lock.unlock()
        }
    }

    private final class Rasteriser: VectorStyleRasteriser, @unchecked Sendable {
        var installed: [String] = []
        var restyled: [String] = []
        var disposals = 0

        private final class Work: VectorStyleRasterisation {
            let owner: Rasteriser
            init(_ owner: Rasteriser) { self.owner = owner }
            func restyle(styleJSON: String, affects _: StyleAffects) {
                owner.restyled.append(styleJSON)
            }

            func dispose() { owner.disposals += 1 }
        }

        func install(host _: MapStyleHost, styleJSON: String, affects _: StyleAffects)
            -> VectorStyleRasterisation
        {
            installed.append(styleJSON)
            return Work(self)
        }
    }

    /// The work happens on a queue; wait for it to land rather than guess.
    private func settle(_ host: Host, until: () -> Bool) {
        let deadline = Date().addingTimeInterval(10)
        while !until(), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertTrue(until(), "nothing happened: \(host.diagnostics)")
    }

    // MARK: - the routes

    /**
     A map that reads styles and takes patches gets the author's document and
     the differences on top -- not the adjusted document. The next rule
     change produces differences against the original, and a map holding an
     already-adjusted document would read them as something else.
     */
    func testAMapThatReadsStylesIsGivenTheOriginalAndTheDifferences() {
        let host = Host(vector: true, mutations: true)
        let installation = VectorStyle(document: .text(style), rules: rules("#ffffff"))
            .install(host: host)
        defer { installation.dispose() }

        settle(host) { !host.applied.isEmpty }

        XCTAssertEqual(host.shown.count, 1)
        XCTAssertTrue(host.shown[0]?.contains("/docs/") == true, "\(host.shown)")
        let paints = host.applied.flatMap { $0 }
        XCTAssertEqual(paints.count, 1)
        guard case let .setPaint(layerId, _, value, previous) = paints[0] else {
            return XCTFail("expected a paint mutation")
        }
        XCTAssertEqual(layerId, "roads")
        XCTAssertEqual(value, "\"#ffffff\"")
        // The document says `#888`; what comes back is the same colour in
        // the one form every renderer can read -- which this platform's
        // MapLibre adapter is the reason for.
        XCTAssertEqual(previous, "\"#888888\"")
        XCTAssertTrue(host.credited.contains("© Someone"), "the style's credit was not carried")
    }

    /**
     The point of the whole design: moving a slider sends new differences and
     the map is never handed a document again.
     */
    func testChangingTheRulesDoesNotReloadAnything() {
        let host = Host(vector: true, mutations: true)
        let installation = VectorStyle(document: .text(style), rules: rules("#ffffff"))
            .install(host: host)
        defer { installation.dispose() }
        settle(host) { !host.applied.isEmpty }
        let servedOnce = host.shown.count

        let again = VectorStyle(document: .text(style), rules: rules("#ff0000"))
        XCTAssertTrue(installation.update(again), "an adjustment-only change was refused")
        settle(host) { host.applied.count > 1 }

        XCTAssertEqual(host.shown.count, servedOnce, "the map was handed a document again")
        guard case let .setPaint(_, _, value, previous) = host.applied.last!.first! else {
            return XCTFail("expected a paint mutation")
        }
        XCTAssertEqual(value, "\"#ff0000\"")
        XCTAssertEqual(previous, "\"#888888\"", "still relative to the author's style")
    }

    /// A different document is a different style, so the view has to redo it.
    func testADifferentDocumentIsNotAnUpdate() {
        let host = Host(vector: true, mutations: true)
        let installation = VectorStyle(document: .text(style), rules: rules("#ffffff"))
            .install(host: host)
        defer { installation.dispose() }
        settle(host) { !host.applied.isEmpty }
        XCTAssertFalse(installation.update(VectorStyle(document: .url("https://example.test/s.json"))))
    }

    /**
     A map that reads styles but cannot be patched has only one way to show
     an adjustment: the adjusted document. Every rule change reloads, which
     is why the capability is worth implementing.
     */
    func testAMapThatCannotBePatchedIsGivenTheAdjustedDocument() throws {
        let host = Host(vector: true, mutations: false)
        let installation = VectorStyle(document: .text(style), rules: rules("#ffffff"))
            .install(host: host)
        defer { installation.dispose() }
        settle(host) { !host.shown.isEmpty }

        XCTAssertTrue(host.applied.isEmpty)
        let body = try XCTUnwrap(fetchServed(XCTUnwrap(host.shown[0])))
        XCTAssertTrue(body.contains("#ffffff"), "the original was served instead")

        let firstURL = try XCTUnwrap(host.shown[0])
        XCTAssertTrue(installation.update(VectorStyle(document: .text(style), rules: rules("#ff0000"))))
        settle(host) { host.shown.count == 2 }
        let updatedURL = try XCTUnwrap(host.shown[1])
        XCTAssertNotEqual(firstURL, updatedURL, "a URL-keyed provider would keep the previous style")
        let updatedBody = try XCTUnwrap(fetchServed(updatedURL))
        XCTAssertTrue(updatedBody.contains("#ff0000"), "the updated URL must serve the new rules")
    }

    func testAMapThatCannotReadStylesGoesThroughTheRasteriser() {
        let host = Host(vector: false, mutations: false)
        let rasteriser = Rasteriser()
        let installation = VectorStyle(
            document: .text(style), rules: rules("#ffffff"), rasteriser: rasteriser
        ).install(host: host)

        settle(host) { !rasteriser.installed.isEmpty }
        XCTAssertTrue(rasteriser.installed[0].contains("#ffffff"))
        XCTAssertTrue(host.shown.isEmpty, "the map was handed a style it cannot read")

        // A rule change re-rasterises; it does not install again.
        XCTAssertTrue(
            installation.update(
                VectorStyle(document: .text(style), rules: rules("#ff0000"), rasteriser: rasteriser)))
        settle(host) { !rasteriser.restyled.isEmpty }
        XCTAssertEqual(rasteriser.installed.count, 1)
        XCTAssertTrue(rasteriser.restyled[0].contains("#ff0000"))

        installation.dispose()
        XCTAssertEqual(rasteriser.disposals, 1)
    }

    /**
     A backend that can do neither is told so. Left to itself it would show
     an ordinary map and the adjustments would simply not be there, which is
     the failure this whole design is built against.
     */
    func testAMapWithNeitherIsToldSoRatherThanLeftBlank() {
        let host = Host(vector: false, mutations: false)
        let installation = VectorStyle(document: .text(style)).install(host: host)
        defer { installation.dispose() }
        settle(host) { host.diagnostics.contains { $0.contains("no rasteriser") } }
    }

    /// Adjusting "whatever is showing" needs something to be showing.
    func testAdjustingTheCurrentDesignNeedsAStyleToAdjust() {
        let host = Host(vector: true, mutations: true, vectorStyleUrl: nil)
        let installation = VectorStyle(rules: rules("#ffffff")).install(host: host)
        defer { installation.dispose() }
        settle(host) { host.diagnostics.contains { $0.contains("not drawing a vector style") } }
        XCTAssertTrue(host.applied.isEmpty)
    }

    // MARK: - what the map would not take

    func testWhatTheMapRefusesIsReportedAndTheRestStays() {
        let host = Host(vector: true, mutations: true)
        host.refuse = { _ in true }
        let installation = VectorStyle(document: .text(style), rules: rules("#ffffff"))
            .install(host: host)
        defer { installation.dispose() }
        settle(host) { host.diagnostics.contains { $0.contains("were not applied") } }
        // .report is the default, so the document was not re-served.
        XCTAssertEqual(host.shown.count, 1)
    }

    func testReloadPolicyHandsOverTheAdjustedDocumentInstead() throws {
        let host = Host(vector: true, mutations: true)
        host.refuse = { _ in true }
        let installation = VectorStyle(
            document: .text(style), rules: rules("#ffffff"), onUnsupported: .reload
        ).install(host: host)
        defer { installation.dispose() }
        settle(host) { host.shown.count >= 2 }
        let body = try XCTUnwrap(fetchServed(XCTUnwrap(host.shown.last!)))
        XCTAssertTrue(body.contains("#ffffff"), "the adjusted document was not served")
    }

    // MARK: - taking it off again

    func testDisposingLeavesTheMapAsItWasFound() throws {
        let host = Host(vector: true, mutations: true)
        let installation = VectorStyle(document: .text(style), rules: rules("#ffffff"))
            .install(host: host)
        settle(host) { !host.applied.isEmpty }
        let served = try XCTUnwrap(host.shown[0])

        installation.dispose()

        XCTAssertTrue(host.shown.contains(nil), "the style was not cleared")
        XCTAssertTrue(host.store.applied.isEmpty, "the adjustments were not taken off")
        XCTAssertNil(fetchServed(served), "the document is still being served")
        XCTAssertFalse(host.styleLoadedAttached, "the style-loaded hook is still attached")
    }

    /// Disposing twice is what a view does on a fast remount.
    func testDisposingTwiceIsHarmless() {
        let host = Host(vector: true, mutations: true)
        let installation = VectorStyle(document: .text(style), rules: rules("#ffffff"))
            .install(host: host)
        settle(host) { !host.applied.isEmpty }
        installation.dispose()
        installation.dispose()
        XCTAssertEqual(host.shown.filter { $0 == nil }.count, 1)
    }

    func testTheDiagnosticsAlwaysSayWhatTheRulesMatched() {
        let host = Host(vector: true, mutations: true)
        let heard = Heard()
        let installation = VectorStyle(
            document: .text(style), rules: rules("#ffffff"),
            onDiagnostics: { heard.add($0) }
        ).install(host: host)
        defer { installation.dispose() }
        settle(host) { heard.contains("matched 1 layers") }
    }

    private final class Heard: @unchecked Sendable {
        private let lock = NSLock()
        private var lines: [String] = []
        func add(_ more: [String]) {
            lock.lock()
            lines.append(contentsOf: more)
            lock.unlock()
        }

        func contains(_ text: String) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            return lines.contains { $0.contains(text) }
        }
    }

    // MARK: - helpers

    private func fetchServed(_ url: String) -> String? {
        guard let target = URL(string: url) else { return nil }
        var answer: String?
        let done = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: URLRequest(url: target, timeoutInterval: 5)) {
            data, response, _ in
            defer { done.signal() }
            guard
                let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status),
                let data
            else { return }
            answer = String(data: data, encoding: .utf8)
        }.resume()
        _ = done.wait(timeout: .now() + 10)
        return answer
    }
}
