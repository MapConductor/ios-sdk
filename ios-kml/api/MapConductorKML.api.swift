import Combine
import CoreGraphics
import Foundation
import MapConductorCore
import Swift
import SwiftUI
import UIKit
import _Concurrency
import _StringProcessing
import _SwiftConcurrencyShims
import zlib
public enum KMLDefaults {
  public static let defaultTileSize: Swift.Int
  public static let defaultMaxZoom: Swift.Int
  public static let defaultOpacity: Swift.Double
  public static let defaultStrokeColor: UIKit.UIColor
  public static let defaultFillColor: UIKit.UIColor
  public static let defaultStrokeWidth: CoreFoundation.CGFloat
  public static let defaultPointRadius: CoreFoundation.CGFloat
}
public struct KMLNetworkLink {
  public let href: Swift.String
  public let visibility: Swift.Bool
  public init(href: Swift.String, visibility: Swift.Bool = true)
}
public struct KMLDocument {
  public let features: [MapConductorKML.KMLFeature]
  public let networkLinks: [MapConductorKML.KMLNetworkLink]
  public init(features: [MapConductorKML.KMLFeature], networkLinks: [MapConductorKML.KMLNetworkLink] = [])
}
public struct KMLFeature : Swift.Identifiable {
  public let id: Swift.String?
  public let geometry: MapConductorKML.KMLGeometry
  public let properties: [Swift.String : Any]
  public var strokeColor: UIKit.UIColor?
  public var fillColor: UIKit.UIColor?
  public var strokeWidth: CoreFoundation.CGFloat?
  public var pointRadius: CoreFoundation.CGFloat?
  public var visible: Swift.Bool
  public init(id: Swift.String? = nil, geometry: MapConductorKML.KMLGeometry, properties: [Swift.String : Any] = [:], strokeColor: UIKit.UIColor? = nil, fillColor: UIKit.UIColor? = nil, strokeWidth: CoreFoundation.CGFloat? = nil, pointRadius: CoreFoundation.CGFloat? = nil, visible: Swift.Bool = true)
  public typealias ID = Swift.String?
}
final public class KMLFeatureState : Combine.ObservableObject {
  final public let id: Swift.String
  @Combine.Published<MapConductorKML.KMLGeometry> @_projectedValueProperty($geometry) final public var geometry: MapConductorKML.KMLGeometry {
    get
    @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 10.15, *)
    set
    @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 10.15, *)
    _modify
  }
  final public var $geometry: Combine.Published<MapConductorKML.KMLGeometry>.Publisher {
    get
    @available(iOS 14.0, tvOS 14.0, watchOS 7.0, macOS 11.0, *)
    set
  }
  @Combine.Published<[Swift.String : Any]> @_projectedValueProperty($properties) final public var properties: [Swift.String : Any] {
    get
    @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 10.15, *)
    set
    @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 10.15, *)
    _modify
  }
  final public var $properties: Combine.Published<[Swift.String : Any]>.Publisher {
    get
    @available(iOS 14.0, tvOS 14.0, watchOS 7.0, macOS 11.0, *)
    set
  }
  @Combine.Published<UIKit.UIColor?> @_projectedValueProperty($strokeColor) final public var strokeColor: UIKit.UIColor? {
    get
    @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 10.15, *)
    set
    @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 10.15, *)
    _modify
  }
  final public var $strokeColor: Combine.Published<UIKit.UIColor?>.Publisher {
    get
    @available(iOS 14.0, tvOS 14.0, watchOS 7.0, macOS 11.0, *)
    set
  }
  @Combine.Published<UIKit.UIColor?> @_projectedValueProperty($fillColor) final public var fillColor: UIKit.UIColor? {
    get
    @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 10.15, *)
    set
    @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 10.15, *)
    _modify
  }
  final public var $fillColor: Combine.Published<UIKit.UIColor?>.Publisher {
    get
    @available(iOS 14.0, tvOS 14.0, watchOS 7.0, macOS 11.0, *)
    set
  }
  @Combine.Published<CoreFoundation.CGFloat?> @_projectedValueProperty($strokeWidth) final public var strokeWidth: CoreFoundation.CGFloat? {
    get
    @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 10.15, *)
    set
    @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 10.15, *)
    _modify
  }
  final public var $strokeWidth: Combine.Published<CoreFoundation.CGFloat?>.Publisher {
    get
    @available(iOS 14.0, tvOS 14.0, watchOS 7.0, macOS 11.0, *)
    set
  }
  @Combine.Published<CoreFoundation.CGFloat?> @_projectedValueProperty($pointRadius) final public var pointRadius: CoreFoundation.CGFloat? {
    get
    @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 10.15, *)
    set
    @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 10.15, *)
    _modify
  }
  final public var $pointRadius: Combine.Published<CoreFoundation.CGFloat?>.Publisher {
    get
    @available(iOS 14.0, tvOS 14.0, watchOS 7.0, macOS 11.0, *)
    set
  }
  @Combine.Published<Swift.Bool> @_projectedValueProperty($visible) final public var visible: Swift.Bool {
    get
    @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 10.15, *)
    set
    @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 10.15, *)
    _modify
  }
  final public var $visible: Combine.Published<Swift.Bool>.Publisher {
    get
    @available(iOS 14.0, tvOS 14.0, watchOS 7.0, macOS 11.0, *)
    set
  }
  public init(featureId: Swift.String? = nil, geometry: MapConductorKML.KMLGeometry, properties: [Swift.String : Any] = [:], strokeColor: UIKit.UIColor? = nil, fillColor: UIKit.UIColor? = nil, strokeWidth: CoreFoundation.CGFloat? = nil, pointRadius: CoreFoundation.CGFloat? = nil, visible: Swift.Bool = true)
  final public func fingerPrint() -> MapConductorKML.KMLFeatureFingerPrint
  final public func asPublisher() -> Combine.AnyPublisher<MapConductorKML.KMLFeatureFingerPrint, Swift.Never>
  final public func toFeature() -> MapConductorKML.KMLFeature
  public typealias ObjectWillChangePublisher = Combine.ObservableObjectPublisher
  @objc deinit
}
public struct KMLFeatureFingerPrint : Swift.Equatable {
  public let id: Swift.Int
  public let geometry: Swift.Int
  public let properties: Swift.Int
  public let style: Swift.Int
  public let visible: Swift.Int
  public static func == (a: MapConductorKML.KMLFeatureFingerPrint, b: MapConductorKML.KMLFeatureFingerPrint) -> Swift.Bool
}
public struct LonLat : Swift.Equatable, Swift.Hashable {
  public let longitude: Swift.Double
  public let latitude: Swift.Double
  public init(longitude: Swift.Double, latitude: Swift.Double)
  public static func == (a: MapConductorKML.LonLat, b: MapConductorKML.LonLat) -> Swift.Bool
  public func hash(into hasher: inout Swift.Hasher)
  public var hashValue: Swift.Int {
    get
  }
}
indirect public enum KMLGeometry : Swift.Equatable, Swift.Hashable {
  case point(longitude: Swift.Double, latitude: Swift.Double)
  case multiPoint(points: [MapConductorKML.LonLat])
  case lineString(coordinates: [MapConductorKML.LonLat])
  case multiLineString(lines: [[MapConductorKML.LonLat]])
  case polygon(rings: [[MapConductorKML.LonLat]])
  case multiPolygon(polygons: [[[MapConductorKML.LonLat]]])
  case geometryCollection(geometries: [MapConductorKML.KMLGeometry])
  case empty
  public static func == (a: MapConductorKML.KMLGeometry, b: MapConductorKML.KMLGeometry) -> Swift.Bool
  public func hash(into hasher: inout Swift.Hasher)
  public var hashValue: Swift.Int {
    get
  }
}
@_Concurrency.MainActor @preconcurrency public struct KMLLayer : MapConductorCore.ViewBasedMapOverlay, Swift.Identifiable {
  @_Concurrency.MainActor @preconcurrency public let id: Swift.String
  @_Concurrency.MainActor @preconcurrency public init(_ state: MapConductorKML.KMLLayerState, features: [MapConductorKML.KMLFeature] = [])
  @_Concurrency.MainActor @preconcurrency public init(state: MapConductorKML.KMLLayerState, features: [MapConductorKML.KMLFeature] = [])
  @_Concurrency.MainActor @preconcurrency public init(features: [MapConductorKML.KMLFeature] = [], tileSize: Swift.Int = KMLDefaults.defaultTileSize, opacity: Swift.Double = KMLDefaults.defaultOpacity, layerStyle: MapConductorKML.KMLTileRenderer.LayerStyle = KMLTileRenderer.LayerStyle(), styleProvider: any MapConductorKML.KMLStyleProvider = DefaultKMLStyleProvider.shared)
  @_Concurrency.MainActor @preconcurrency public var body: some SwiftUICore.View {
    get
  }
  @_Concurrency.MainActor @preconcurrency public func append(to content: inout MapConductorCore.MapViewContent)
  public typealias Body = @_opaqueReturnTypeOf("$s15MapConductorKML8KMLLayerV4bodyQrvp", 0) __
  public typealias ID = Swift.String
}
final public class KMLLayerState : Combine.ObservableObject {
  final public var onClick: ((MapConductorKML.KMLFeature, MapConductorCore.GeoPoint) -> Swift.Void)?
  final public var onLoadStart: (() -> Swift.Void)?
  final public var onLoadComplete: (((any Swift.Error)?) -> Swift.Void)?
  final public var opacity: Swift.Double {
    get
    set
  }
  final public var minZoom: Swift.Int {
    get
    set
  }
  final public var maxZoom: Swift.Int {
    get
    set
  }
  final public var layerStyle: MapConductorKML.KMLTileRenderer.LayerStyle {
    get
    set
  }
  final public var styleProvider: any MapConductorKML.KMLStyleProvider {
    get
    set
  }
  public init(tileSize: Swift.Int = KMLDefaults.defaultTileSize, opacity: Swift.Double = KMLDefaults.defaultOpacity, minZoom: Swift.Int = 0, maxZoom: Swift.Int = KMLDefaults.defaultMaxZoom, layerStyle: MapConductorKML.KMLTileRenderer.LayerStyle = KMLTileRenderer.LayerStyle(), styleProvider: any MapConductorKML.KMLStyleProvider = DefaultKMLStyleProvider.shared, onLoadStart: (() -> Swift.Void)? = nil, onLoadComplete: (((any Swift.Error)?) -> Swift.Void)? = nil, onClick: ((MapConductorKML.KMLFeature, MapConductorCore.GeoPoint) -> Swift.Void)? = nil)
  @objc deinit
  final public func setFeatures(_ features: [MapConductorKML.KMLFeature])
  final public func beginLoading()
  final public func completeLoading(error: (any Swift.Error)? = nil)
  final public func setFeatures(_ states: [MapConductorKML.KMLFeatureState])
  final public func processClick(geoPoint: MapConductorCore.GeoPoint, pixelTolerance: Swift.Double? = nil, zoom: Swift.Double? = nil)
  public typealias ObjectWillChangePublisher = Combine.ObservableObjectPublisher
}
final public class KMLLoader {
  public static let defaultMaxDocuments: Swift.Int
  public typealias Fetch = (Swift.String) async throws -> Foundation.Data
  public init(maxDocuments: Swift.Int = KMLLoader.defaultMaxDocuments, onDocumentError: ((Swift.String, any Swift.Error) -> Swift.Void)? = nil, fetch: MapConductorKML.KMLLoader.Fetch? = nil)
  final public func load(url: Swift.String) async throws -> [MapConductorKML.KMLFeature]
  final public func load(data: Foundation.Data, baseURL: Swift.String? = nil) async throws -> [MapConductorKML.KMLFeature]
  @objc deinit
}
public enum KMLParseError : Foundation.LocalizedError {
  case invalidXML(underlying: (any Swift.Error)?)
  case kmzWithoutKMLEntry
  public var errorDescription: Swift.String? {
    get
  }
}
public enum KMLParser {
  public static func parse(_ kml: Swift.String) throws -> [MapConductorKML.KMLFeature]
  public static func parse(data: Foundation.Data) throws -> [MapConductorKML.KMLFeature]
  public static func parseDocument(data: Foundation.Data) throws -> MapConductorKML.KMLDocument
}
public protocol KMLStyleProvider : AnyObject {
  func style(for feature: MapConductorKML.KMLFeature, defaultStyle: MapConductorKML.KMLTileRenderer.LayerStyle) -> MapConductorKML.KMLTileRenderer.LayerStyle
}
@_hasMissingDesignatedInitializers final public class DefaultKMLStyleProvider : MapConductorKML.KMLStyleProvider {
  public static let shared: MapConductorKML.DefaultKMLStyleProvider
  final public func style(for feature: MapConductorKML.KMLFeature, defaultStyle: MapConductorKML.KMLTileRenderer.LayerStyle) -> MapConductorKML.KMLTileRenderer.LayerStyle
  @objc deinit
}
final public class KMLTileRenderer : MapConductorCore.TileProvider {
  final public let tileSize: Swift.Int
  public struct LayerStyle {
    public let strokeColor: UIKit.UIColor
    public let fillColor: UIKit.UIColor
    public let strokeWidth: CoreFoundation.CGFloat
    public let pointRadius: CoreFoundation.CGFloat
    public init(strokeColor: UIKit.UIColor = KMLDefaults.defaultStrokeColor, fillColor: UIKit.UIColor = KMLDefaults.defaultFillColor, strokeWidth: CoreFoundation.CGFloat = KMLDefaults.defaultStrokeWidth, pointRadius: CoreFoundation.CGFloat = KMLDefaults.defaultPointRadius)
  }
  public struct KMLHitTestResult {
    public let feature: MapConductorKML.KMLFeature
    public let position: MapConductorCore.GeoPoint
  }
  public init(tileSize: Swift.Int = KMLDefaults.defaultTileSize)
  final public func update(features: [MapConductorKML.KMLFeature], layerStyle: MapConductorKML.KMLTileRenderer.LayerStyle, styleProvider: any MapConductorKML.KMLStyleProvider = DefaultKMLStyleProvider.shared)
  final public func renderTile(request: MapConductorCore.TileRequest) -> Foundation.Data?
  final public func hitTest(longitude: Swift.Double, latitude: Swift.Double, lineTolSq: Swift.Double? = nil, pointTolSq: Swift.Double? = nil) -> MapConductorKML.KMLTileRenderer.KMLHitTestResult?
  final public func hitTestFeature(longitude: Swift.Double, latitude: Swift.Double, lineTolSq: Swift.Double? = nil, pointTolSq: Swift.Double? = nil) -> MapConductorKML.KMLFeature?
  @objc deinit
}
extension MapConductorKML.KMLLayer : Swift.Sendable {}
