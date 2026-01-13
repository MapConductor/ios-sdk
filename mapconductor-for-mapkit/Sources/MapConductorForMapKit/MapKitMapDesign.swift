import MapKit
import MapConductorCore

public protocol MapKitMapDesignTypeProtocol: MapDesignTypeProtocol where Identifier == MKMapType {}

public typealias MapKitMapDesignType = any MapKitMapDesignTypeProtocol

public struct MapKitMapDesign: MapKitMapDesignTypeProtocol, Hashable {
    public let id: MKMapType

    public init(id: MKMapType) {
        self.id = id
    }

    public func getValue() -> MKMapType {
        id
    }

    public static let Standard = MapKitMapDesign(id: .standard)
    public static let Satellite = MapKitMapDesign(id: .satellite)
    public static let Hybrid = MapKitMapDesign(id: .hybrid)
    public static let SatelliteFlyover = MapKitMapDesign(id: .satelliteFlyover)
    public static let HybridFlyover = MapKitMapDesign(id: .hybridFlyover)
    public static let MutedStandard = MapKitMapDesign(id: .mutedStandard)

    public static func Create(id: MKMapType) -> MapKitMapDesign {
        switch id {
        case .standard:
            return Standard
        case .satellite:
            return Satellite
        case .hybrid:
            return Hybrid
        case .satelliteFlyover:
            return SatelliteFlyover
        case .hybridFlyover:
            return HybridFlyover
        case .mutedStandard:
            return MutedStandard
        @unknown default:
            return MapKitMapDesign(id: id)
        }
    }

    public static func toMapDesignType(id: MKMapType) -> MapKitMapDesignType {
        Create(id: id)
    }
}
