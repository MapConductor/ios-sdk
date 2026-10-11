import XCTest
@testable import MapConductorVectorTile

final class TileMemoryCacheTests: XCTestCase {
    func testStrictBytesAndRecentHitsSurviveEviction() {
        let cache = TileMemoryCache<String>(byteLimit: 10)
        cache.insert("A", for: "a", cost: 4)
        cache.insert("B", for: "b", cost: 4)
        XCTAssertEqual(cache.value(for: "a"), "A")
        cache.insert("C", for: "c", cost: 4)
        XCTAssertNil(cache.value(for: "b"))
        XCTAssertEqual(cache.value(for: "a"), "A")
        XCTAssertEqual(cache.retainedCost, 8)
        cache.insert("large", for: "large", cost: 11)
        XCTAssertNil(cache.value(for: "large"))
        XCTAssertEqual(cache.retainedCost, 8)
    }

    func testReplacementCountAndIdleExpiry() {
        var now: TimeInterval = 0
        let cache = TileMemoryCache<Bool>(byteLimit: 100, countLimit: 2, ttl: 30, clock: { now })
        cache.insert(true, for: "a", cost: 10)
        cache.insert(true, for: "a", cost: 20)
        XCTAssertEqual(cache.retainedCost, 20)
        cache.insert(true, for: "b", cost: 10)
        cache.insert(true, for: "c", cost: 10)
        XCTAssertNil(cache.value(for: "a"))
        now = 20
        XCTAssertEqual(cache.value(for: "b"), true)
        now = 31
        XCTAssertNil(cache.value(for: "c"))
        XCTAssertEqual(cache.value(for: "b"), true)
        now = 62
        XCTAssertEqual(cache.retainedCost, 0)
    }

    func testConcurrentPanningStaysWithinBudgetAndCanBePurged() {
        let cache = TileMemoryCache<Data>(byteLimit: 4096, countLimit: 16)
        DispatchQueue.concurrentPerform(iterations: 1000) { index in
            let key = "tile-\(index)"
            cache.insert(Data(repeating: 1, count: 512), for: key, cost: 512)
            _ = cache.value(for: key)
            XCTAssertLessThanOrEqual(cache.retainedCost, 4096)
        }
        cache.removeAll()
        XCTAssertEqual(cache.retainedCost, 0)
    }
}
