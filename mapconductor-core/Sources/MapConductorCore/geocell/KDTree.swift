import CoreGraphics
import Foundation

/// K-D tree for spatial queries on `HexCell.centerXY` (projected meters).
public final class KDTree: Sendable {
    private final class Node: @unchecked Sendable {
        let cell: HexCell
        let left: Node?
        let right: Node?
        let axis: Int // 0 = x, 1 = y

        init(cell: HexCell, left: Node?, right: Node?, axis: Int) {
            self.cell = cell
            self.left = left
            self.right = right
            self.axis = axis
        }
    }

    private let root: Node?

    public init(points: [HexCell]) {
        self.root = points.isEmpty ? nil : Self.build(items: points, depth: 0)
    }

    private static func build(items: [HexCell], depth: Int) -> Node? {
        if items.isEmpty { return nil }

        let axis = depth % 2
        let sorted = items.sorted { lhs, rhs in
            if axis == 0 { lhs.centerXY.x < rhs.centerXY.x }
            else { lhs.centerXY.y < rhs.centerXY.y }
        }
        let mid = sorted.count / 2

        return Node(
            cell: sorted[mid],
            left: build(items: Array(sorted[..<mid]), depth: depth + 1),
            right: build(items: mid + 1 < sorted.count ? Array(sorted[(mid + 1)...]) : [], depth: depth + 1),
            axis: axis
        )
    }

    public func nearest(query: CGPoint) -> HexCell? {
        guard let root else { return nil }
        return nearest(node: root, query: query, best: nil, bestDistSq: .greatestFiniteMagnitude)
    }

    private func nearest(node: Node, query: CGPoint, best: HexCell?, bestDistSq: Double) -> HexCell? {
        let axis = node.axis
        let queryVal = axis == 0 ? query.x : query.y
        let nodeVal = axis == 0 ? node.cell.centerXY.x : node.cell.centerXY.y

        let distSq = squaredDistance(query, node.cell.centerXY)
        var currentBest = best
        var currentBestDistSq = bestDistSq

        if distSq < currentBestDistSq {
            currentBest = node.cell
            currentBestDistSq = distSq
        }

        let nearChild: Node?
        let farChild: Node?
        if queryVal < nodeVal {
            nearChild = node.left
            farChild = node.right
        } else {
            nearChild = node.right
            farChild = node.left
        }

        if let nearChild {
            currentBest = nearest(node: nearChild, query: query, best: currentBest, bestDistSq: currentBestDistSq)
            if let currentBest {
                currentBestDistSq = squaredDistance(query, currentBest.centerXY)
            }
        }

        if let farChild {
            let axisDist = (queryVal - nodeVal) * (queryVal - nodeVal)
            if axisDist < currentBestDistSq {
                currentBest = nearest(node: farChild, query: query, best: currentBest, bestDistSq: currentBestDistSq)
            }
        }

        return currentBest
    }

    public func nearestWithDistance(query: CGPoint) -> HexCellWithDistance? {
        guard let cell = nearest(query: query) else { return nil }
        return HexCellWithDistance(cell: cell, distanceMeters: sqrt(squaredDistance(query, cell.centerXY)))
    }

    public func nearestKWithDistance(query: CGPoint, k: Int) -> [HexCellWithDistance] {
        precondition(k > 0, "k must be positive")
        guard let root else { return [] }

        var heap = MaxCellHeap(capacity: k)
        nearestK(node: root, query: query, k: k, heap: &heap)

        return heap
            .elements
            .map { HexCellWithDistance(cell: $0.cell, distanceMeters: sqrt($0.distSq)) }
            .sorted { $0.distanceMeters < $1.distanceMeters }
    }

    private func nearestK(node: Node, query: CGPoint, k: Int, heap: inout MaxCellHeap) {
        let distSq = squaredDistance(query, node.cell.centerXY)
        heap.push(distSq: distSq, cell: node.cell)

        let axis = node.axis
        let queryVal = axis == 0 ? query.x : query.y
        let nodeVal = axis == 0 ? node.cell.centerXY.x : node.cell.centerXY.y

        let nearChild: Node?
        let farChild: Node?
        if queryVal < nodeVal {
            nearChild = node.left
            farChild = node.right
        } else {
            nearChild = node.right
            farChild = node.left
        }

        if let nearChild { nearestK(node: nearChild, query: query, k: k, heap: &heap) }

        if let farChild {
            let axisDist = (queryVal - nodeVal) * (queryVal - nodeVal)
            if heap.elements.count < k || axisDist < heap.maxDistSq {
                nearestK(node: farChild, query: query, k: k, heap: &heap)
            }
        }
    }

    public func withinRadiusWithDistance(query: CGPoint, radius: Double) -> [HexCellWithDistance] {
        precondition(radius >= 0, "Radius must be non-negative")
        guard let root else { return [] }

        var results: [HexCellWithDistance] = []
        withinRadius(node: root, query: query, radiusSq: radius * radius, results: &results)
        results.sort { $0.distanceMeters < $1.distanceMeters }
        return results
    }

    private func withinRadius(node: Node, query: CGPoint, radiusSq: Double, results: inout [HexCellWithDistance]) {
        let distSq = squaredDistance(query, node.cell.centerXY)
        if distSq <= radiusSq {
            results.append(HexCellWithDistance(cell: node.cell, distanceMeters: sqrt(distSq)))
        }

        let axis = node.axis
        let queryVal = axis == 0 ? query.x : query.y
        let nodeVal = axis == 0 ? node.cell.centerXY.x : node.cell.centerXY.y

        let nearChild: Node?
        let farChild: Node?
        if queryVal < nodeVal {
            nearChild = node.left
            farChild = node.right
        } else {
            nearChild = node.right
            farChild = node.left
        }

        if let nearChild { withinRadius(node: nearChild, query: query, radiusSq: radiusSq, results: &results) }

        if let farChild {
            let axisDist = (queryVal - nodeVal) * (queryVal - nodeVal)
            if axisDist <= radiusSq {
                withinRadius(node: farChild, query: query, radiusSq: radiusSq, results: &results)
            }
        }
    }

    private func squaredDistance(_ a: CGPoint, _ b: CGPoint) -> Double {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return dx * dx + dy * dy
    }
}

/// Fixed-size max heap of (distance^2, cell) for k-NN.
private struct MaxCellHeap {
    struct Entry {
        let distSq: Double
        let cell: HexCell
    }

    private(set) var elements: [Entry] = []
    private let capacity: Int

    init(capacity: Int) {
        self.capacity = max(0, capacity)
        self.elements.reserveCapacity(capacity)
    }

    var maxDistSq: Double { elements.first?.distSq ?? .greatestFiniteMagnitude }

    mutating func push(distSq: Double, cell: HexCell) {
        guard capacity > 0 else { return }

        if elements.count < capacity {
            elements.append(Entry(distSq: distSq, cell: cell))
            siftUp(from: elements.count - 1)
            return
        }

        if let max = elements.first, distSq >= max.distSq { return }

        elements[0] = Entry(distSq: distSq, cell: cell)
        siftDown(from: 0)
    }

    private mutating func siftUp(from index: Int) {
        var child = index
        while child > 0 {
            let parent = (child - 1) / 2
            if elements[child].distSq <= elements[parent].distSq { break }
            elements.swapAt(child, parent)
            child = parent
        }
    }

    private mutating func siftDown(from index: Int) {
        var parent = index
        while true {
            let left = parent * 2 + 1
            let right = left + 1
            var candidate = parent

            if left < elements.count, elements[left].distSq > elements[candidate].distSq {
                candidate = left
            }
            if right < elements.count, elements[right].distSq > elements[candidate].distSq {
                candidate = right
            }
            if candidate == parent { break }

            elements.swapAt(parent, candidate)
            parent = candidate
        }
    }
}
