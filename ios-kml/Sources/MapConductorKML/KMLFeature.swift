import UIKit

/// Lightweight, non-reactive data model for static/bulk KML features.
/// Use this (instead of ``KMLFeatureState``) when loading large KML files
/// that don't need per-feature reactive state — e.g. via ``KMLParser``.
public struct KMLFeature: Identifiable {
    public let id: String?
    public let geometry: KMLGeometry
    public let properties: [String: Any]
    public var strokeColor: UIColor?
    public var fillColor: UIColor?
    public var strokeWidth: CGFloat?
    public var pointRadius: CGFloat?
    public var visible: Bool

    public init(
        id: String? = nil,
        geometry: KMLGeometry,
        properties: [String: Any] = [:],
        strokeColor: UIColor? = nil,
        fillColor: UIColor? = nil,
        strokeWidth: CGFloat? = nil,
        pointRadius: CGFloat? = nil,
        visible: Bool = true
    ) {
        self.id = id
        self.geometry = geometry
        self.properties = properties
        self.strokeColor = strokeColor
        self.fillColor = fillColor
        self.strokeWidth = strokeWidth
        self.pointRadius = pointRadius
        self.visible = visible
    }
}
