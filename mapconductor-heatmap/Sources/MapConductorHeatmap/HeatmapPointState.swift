import Combine
import MapConductorCore

public struct HeatmapPointFingerPrint: Equatable, Hashable {
    public let id: Int
    public let weight: Int
    public let latitude: Int
    public let longitude: Int
    public let altitude: Int
}

public final class HeatmapPointState: ObservableObject, Identifiable, Equatable, Hashable {
    public let id: String

    @Published public var position: GeoPoint
    @Published public var weight: Double

    public init(position: GeoPoint, weight: Double = 1.0, id: String? = nil) {
        let resolvedId = id ?? HeatmapPointState.makePointId(position: position, weight: weight)
        self.id = resolvedId
        self.position = position
        self.weight = weight
    }

    public func copy(
        id: String? = nil,
        position: GeoPoint? = nil,
        weight: Double? = nil
    ) -> HeatmapPointState {
        HeatmapPointState(
            position: position ?? self.position,
            weight: weight ?? self.weight,
            id: id ?? self.id
        )
    }

    public func fingerPrint() -> HeatmapPointFingerPrint {
        HeatmapPointFingerPrint(
            id: javaHash(id),
            weight: javaHash(weight),
            latitude: javaHash(position.latitude),
            longitude: javaHash(position.longitude),
            altitude: javaHash(position.altitude ?? 0.0)
        )
    }

    public func asFlow() -> AnyPublisher<HeatmapPointFingerPrint, Never> {
        Publishers.CombineLatest($position, $weight)
            .map { [id] position, weight in
                HeatmapPointFingerPrint(
                    id: javaHash(id),
                    weight: javaHash(weight),
                    latitude: javaHash(position.latitude),
                    longitude: javaHash(position.longitude),
                    altitude: javaHash(position.altitude ?? 0.0)
                )
            }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    public static func == (lhs: HeatmapPointState, rhs: HeatmapPointState) -> Bool {
        lhs.hashCode() == rhs.hashCode()
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(hashCode())
    }

    public func hashCode() -> Int {
        var result: Int32 = Int32(truncatingIfNeeded: javaHash(weight))
        result = result &* 31 &+ Int32(truncatingIfNeeded: javaHash(position.latitude))
        result = result &* 31 &+ Int32(truncatingIfNeeded: javaHash(position.longitude))
        result = result &* 31 &+ Int32(truncatingIfNeeded: javaHash(position.altitude ?? 0.0))
        return Int(result)
    }

    private static func makePointId(position: GeoPoint, weight: Double) -> String {
        let hashCodes = [
            javaHash(position.latitude),
            javaHash(position.longitude),
            javaHash(position.altitude ?? 0.0),
            javaHash(weight)
        ]
        return pointId(hashCodes: hashCodes)
    }
}

private func pointId(hashCodes: [Int]) -> String {
    var result: Int32 = 0
    for hash in hashCodes {
        result = result &* 31 &+ Int32(truncatingIfNeeded: hash)
    }
    return String(result)
}

private func javaHash(_ value: Double) -> Int {
    let bits = value.bitPattern
    let combined = bits ^ (bits >> 32)
    return Int(Int32(truncatingIfNeeded: combined))
}

private func javaHash(_ value: String) -> Int {
    var result: Int32 = 0
    for scalar in value.unicodeScalars {
        result = result &* 31 &+ Int32(truncatingIfNeeded: scalar.value)
    }
    return Int(result)
}
