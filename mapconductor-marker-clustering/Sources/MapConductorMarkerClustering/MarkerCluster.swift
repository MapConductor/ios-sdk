import MapConductorCore

public struct MarkerCluster: Equatable, Hashable {
    public let count: Int
    public let markerIds: [String]

    public init(
        count: Int,
        markerIds: [String]
    ) {
        self.count = count
        self.markerIds = markerIds
    }
}
