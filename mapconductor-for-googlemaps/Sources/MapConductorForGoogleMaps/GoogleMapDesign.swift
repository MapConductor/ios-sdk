import GoogleMaps
import MapConductorCore

public protocol GoogleMapDesignTypeProtocol: MapDesignTypeProtocol where Identifier == GMSMapViewType {}

public typealias GoogleMapDesignType = any GoogleMapDesignTypeProtocol

public struct GoogleMapDesign: GoogleMapDesignTypeProtocol, Hashable {
    public let id: GMSMapViewType

    public init(id: GMSMapViewType) {
        self.id = id
    }

    public func getValue() -> GMSMapViewType {
        id
    }

    public static let Normal = GoogleMapDesign(id: .normal)
    public static let Satellite = GoogleMapDesign(id: .satellite)
    public static let Hybrid = GoogleMapDesign(id: .hybrid)
    public static let Terrain = GoogleMapDesign(id: .terrain)
    public static let None = GoogleMapDesign(id: .none)

    public static func Create(id: GMSMapViewType) -> GoogleMapDesign {
        switch id {
        case .normal:
            return Normal
        case .satellite:
            return Satellite
        case .hybrid:
            return Hybrid
        case .terrain:
            return Terrain
        case .none:
            return None
        @unknown default:
            return GoogleMapDesign(id: id)
        }
    }

    public static func toMapDesignType(id: GMSMapViewType) -> GoogleMapDesignType {
        Create(id: id)
    }
}
