import Combine
import MapConductorCore
import UIKit

public final class KMLFeatureState: ObservableObject {
    public let id: String

    @Published public var geometry: KMLGeometry
    @Published public var properties: [String: Any]
    @Published public var strokeColor: UIColor?
    @Published public var fillColor: UIColor?
    @Published public var strokeWidth: CGFloat?
    @Published public var pointRadius: CGFloat?
    @Published public var visible: Bool

    public init(
        featureId: String? = nil,
        geometry: KMLGeometry,
        properties: [String: Any] = [:],
        strokeColor: UIColor? = nil,
        fillColor: UIColor? = nil,
        strokeWidth: CGFloat? = nil,
        pointRadius: CGFloat? = nil,
        visible: Bool = true
    ) {
        self.id = featureId ?? Self.buildDefaultId(geometry: geometry, properties: properties)
        self.geometry = geometry
        self.properties = properties
        self.strokeColor = strokeColor
        self.fillColor = fillColor
        self.strokeWidth = strokeWidth
        self.pointRadius = pointRadius
        self.visible = visible
    }

    public func fingerPrint() -> KMLFeatureFingerPrint {
        KMLFeatureFingerPrint(
            id: id.hashValue,
            geometry: geometry.hashValue,
            properties: (properties as NSDictionary).hash,
            style: styleHashCode(),
            visible: visible.hashValue
        )
    }

    public func asPublisher() -> AnyPublisher<KMLFeatureFingerPrint, Never> {
        Publishers.CombineLatest4($geometry, $strokeColor, $fillColor, $strokeWidth)
            .combineLatest($pointRadius)
            .combineLatest($visible)
            .map { [weak self] _ -> KMLFeatureFingerPrint in
                self?.fingerPrint() ?? KMLFeatureFingerPrint(id: 0, geometry: 0, properties: 0, style: 0, visible: 0)
            }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    public func toFeature() -> KMLFeature {
        KMLFeature(
            id: id,
            geometry: geometry,
            properties: properties,
            strokeColor: strokeColor,
            fillColor: fillColor,
            strokeWidth: strokeWidth,
            pointRadius: pointRadius,
            visible: visible
        )
    }

    private func styleHashCode() -> Int {
        var h = strokeColor.hashValue
        h = 31 &* h &+ fillColor.hashValue
        h = 31 &* h &+ strokeWidth.hashValue
        h = 31 &* h &+ pointRadius.hashValue
        return h
    }

    private static func buildDefaultId(geometry: KMLGeometry, properties: [String: Any]) -> String {
        var h = geometry.hashValue
        h = 31 &* h &+ (properties as NSDictionary).hash
        return String(h)
    }
}

public struct KMLFeatureFingerPrint: Equatable {
    public let id: Int
    public let geometry: Int
    public let properties: Int
    public let style: Int
    public let visible: Int
}
