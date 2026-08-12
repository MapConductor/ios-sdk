import XCTest
@testable import MapConductorKML

final class KMLLoaderTests: XCTestCase {
    private final class FetchLog {
        var urls: [String] = []
    }

    private struct StubError: Error {
        let url: String
    }

    private func kmlWithPoint(_ name: String, links: [String] = []) -> String {
        let linkTags = links
            .map { "<NetworkLink><Link><href>\($0)</href></Link></NetworkLink>" }
            .joined()
        return """
            <?xml version="1.0"?><kml><Document>
            \(linkTags)
            <Placemark><name>\(name)</name><Point><coordinates>1,2</coordinates></Point></Placemark>
            </Document></kml>
            """
    }

    private func loaderFor(
        documents: [String: String],
        maxDocuments: Int = KMLLoader.defaultMaxDocuments,
        onDocumentError: ((String, Error) -> Void)? = nil
    ) -> (KMLLoader, FetchLog) {
        let log = FetchLog()
        let loader = KMLLoader(
            maxDocuments: maxDocuments,
            onDocumentError: onDocumentError,
            fetch: { url in
                log.urls.append(url)
                guard let document = documents[url] else { throw StubError(url: url) }
                return Data(document.utf8)
            }
        )
        return (loader, log)
    }

    private func names(_ features: [KMLFeature]) -> [String] {
        features.map { $0.properties["name"] as? String ?? "" }
    }

    func testFollowsAbsoluteAndRelativeNetworkLinks() async throws {
        let (loader, _) = loaderFor(
            documents: [
                "https://example.com/maps/root.kml":
                    kmlWithPoint("root", links: ["sub/child.kml", "https://other.com/abs.kml"]),
                "https://example.com/maps/sub/child.kml": kmlWithPoint("child"),
                "https://other.com/abs.kml": kmlWithPoint("abs"),
            ]
        )

        let features = try await loader.load(url: "https://example.com/maps/root.kml")

        XCTAssertEqual(["root", "child", "abs"], names(features))
    }

    func testCyclicLinksAreFetchedOnlyOnce() async throws {
        let (loader, fetchLog) = loaderFor(
            documents: [
                "https://example.com/a.kml":
                    kmlWithPoint("a", links: ["https://example.com/b.kml"]),
                "https://example.com/b.kml":
                    kmlWithPoint("b", links: ["https://example.com/a.kml"]),
            ]
        )

        let features = try await loader.load(url: "https://example.com/a.kml")

        XCTAssertEqual(["a", "b"], names(features))
        XCTAssertEqual(2, fetchLog.urls.count)
    }

    func testMaxDocumentsCapsTheChain() async throws {
        var chain: [String: String] = [:]
        for i in 0..<10 {
            chain["https://example.com/\(i).kml"] =
                kmlWithPoint("doc\(i)", links: ["https://example.com/\(i + 1).kml"])
        }
        let (loader, _) = loaderFor(documents: chain, maxDocuments: 3)

        let features = try await loader.load(url: "https://example.com/0.kml")

        XCTAssertEqual(["doc0", "doc1", "doc2"], names(features))
    }

    func testFailedLinkIsSkippedAndReported() async throws {
        var errors: [String] = []
        let (loader, _) = loaderFor(
            documents: [
                "https://example.com/root.kml":
                    kmlWithPoint(
                        "root",
                        links: ["https://example.com/missing.kml", "https://example.com/ok.kml"]
                    ),
                "https://example.com/ok.kml": kmlWithPoint("ok"),
            ],
            onDocumentError: { url, _ in errors.append(url) }
        )

        let features = try await loader.load(url: "https://example.com/root.kml")

        XCTAssertEqual(["root", "ok"], names(features))
        XCTAssertEqual(["https://example.com/missing.kml"], errors)
    }

    func testDataOverloadResolvesRelativeLinksAgainstBaseURL() async throws {
        let (loader, fetchLog) = loaderFor(
            documents: ["https://example.com/data/child.kml": kmlWithPoint("child")]
        )
        let root = Data(kmlWithPoint("root", links: ["child.kml"]).utf8)

        let features = try await loader.load(data: root, baseURL: "https://example.com/data/root.kml")

        XCTAssertEqual(["root", "child"], names(features))
        XCTAssertEqual(["https://example.com/data/child.kml"], fetchLog.urls)
    }

    func testDataOverloadWithoutBaseURLSkipsRelativeLinks() async throws {
        let (loader, fetchLog) = loaderFor(
            documents: ["https://other.com/abs.kml": kmlWithPoint("abs")]
        )
        let root = Data(
            kmlWithPoint("root", links: ["child.kml", "https://other.com/abs.kml"]).utf8
        )

        let features = try await loader.load(data: root)

        XCTAssertEqual(["root", "abs"], names(features))
        XCTAssertEqual(["https://other.com/abs.kml"], fetchLog.urls)
    }

    func testResolveHrefHandlesAbsoluteRelativeAndMissingBase() {
        XCTAssertEqual(
            "https://a.com/x.kml",
            KMLLoader.resolveHref(base: "https://b.com/base.kml", href: "https://a.com/x.kml")
        )
        XCTAssertEqual(
            "https://b.com/dir/x.kml",
            KMLLoader.resolveHref(base: "https://b.com/dir/base.kml", href: "x.kml")
        )
        XCTAssertEqual(
            "https://b.com/x.kml",
            KMLLoader.resolveHref(base: "https://b.com/dir/base.kml", href: "/x.kml")
        )
        XCTAssertNil(KMLLoader.resolveHref(base: nil, href: "x.kml"))
    }
}
