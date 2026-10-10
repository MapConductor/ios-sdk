import CMvtStyle
import Foundation
import MapConductorCore
import Swift
import UIKit
import _Concurrency
import _StringProcessing
import _SwiftConcurrencyShims
public struct StyleRules : Swift::Equatable, Swift::Sendable {
  public let json: Swift::String
  public static let none: MapConductorVectorStyle::StyleRules
  public static func parse(_ json: Swift::String) -> MapConductorVectorStyle::StyleRules
  public static func build(_ block: (MapConductorVectorStyle::StyleRulesBuilder) -> Swift::Void) -> MapConductorVectorStyle::StyleRules
  public static func == (a: MapConductorVectorStyle::StyleRules, b: MapConductorVectorStyle::StyleRules) -> Swift::Bool
}
public enum LayerRole {
  public static let background: Swift::String
  public static let water: Swift::String
  public static let waterway: Swift::String
  public static let land: Swift::String
  public static let landuse: Swift::String
  public static let park: Swift::String
  public static let building: Swift::String
  public static let road: Swift::String
  public static let roadCasing: Swift::String
  public static let rail: Swift::String
  public static let transit: Swift::String
  public static let boundary: Swift::String
  public static let aeroway: Swift::String
  public static let label: Swift::String
  public static let poi: Swift::String
}
public enum StyleLayerKind : Swift::String, Swift::Sendable {
  case background
  case fill
  case line
  case circle
  case symbol
  case other
  public init?(rawValue: Swift::String)
  public typealias RawValue = Swift::String
  public var rawValue: Swift::String {
    get
  }
}
indirect public enum StyleSelector : Swift::Sendable {
  case all
  case role(Swift::String)
  case layerId(Swift::String)
  case sourceLayer(Swift::String)
  case kind(MapConductorVectorStyle::StyleLayerKind)
  case anyOf([MapConductorVectorStyle::StyleSelector])
  case allOf([MapConductorVectorStyle::StyleSelector])
  case not(MapConductorVectorStyle::StyleSelector)
}
@_hasMissingDesignatedInitializers final public class StyleRulesBuilder {
  final public var schema: Swift::String?
  final public func customSchema(_ roles: [Swift::String : [Swift::String]])
  final public func all(_ patch: (MapConductorVectorStyle::StylePatchBuilder) -> Swift::Void)
  final public func role(_ role: Swift::String, _ patch: (MapConductorVectorStyle::StylePatchBuilder) -> Swift::Void)
  final public func layerId(_ glob: Swift::String, _ patch: (MapConductorVectorStyle::StylePatchBuilder) -> Swift::Void)
  final public func sourceLayer(_ name: Swift::String, _ patch: (MapConductorVectorStyle::StylePatchBuilder) -> Swift::Void)
  final public func kind(_ kind: MapConductorVectorStyle::StyleLayerKind, _ patch: (MapConductorVectorStyle::StylePatchBuilder) -> Swift::Void)
  final public func `where`(_ selector: MapConductorVectorStyle::StyleSelector, _ patch: (MapConductorVectorStyle::StylePatchBuilder) -> Swift::Void)
  @objc deinit
}
@_hasMissingDesignatedInitializers final public class StylePatchBuilder {
  final public var visible: Swift::Bool? {
    get
    set
  }
  final public var color: UIKit::UIColor? {
    get
    set
  }
  final public var opacity: Swift::Double? {
    get
    set
  }
  final public var widthScale: Swift::Double? {
    get
    set
  }
  final public var minZoom: Swift::Double? {
    get
    set
  }
  final public var maxZoom: Swift::Double? {
    get
    set
  }
  final public func desaturate(_ amount: Swift::Double)
  final public func darken(_ amount: Swift::Double)
  final public func lighten(_ amount: Swift::Double)
  final public func invertLightness()
  final public func mix(_ target: UIKit::UIColor, amount: Swift::Double = 0.5)
  final public func filter(_ json: Swift::String)
  final public func property(_ key: Swift::String, _ valueJSON: Swift::String)
  final public func propertyText(_ key: Swift::String, _ value: Swift::String)
  @objc deinit
}
public struct VectorStyle : MapConductorCore::MapViewStyle {
  public let document: MapConductorVectorStyle::VectorStyleSource
  public let rules: MapConductorVectorStyle::StyleRules
  public let rasteriser: (any MapConductorVectorStyle::VectorStyleRasteriser)?
  public let onUnsupported: MapConductorVectorStyle::UnsupportedPolicy
  public let onDiagnostics: (([Swift::String]) -> Swift::Void)?
  public init(document: MapConductorVectorStyle::VectorStyleSource = .currentDesign, rules: MapConductorVectorStyle::StyleRules = .none, rasteriser: (any MapConductorVectorStyle::VectorStyleRasteriser)? = nil, onUnsupported: MapConductorVectorStyle::UnsupportedPolicy = .report, onDiagnostics: (([Swift::String]) -> Swift::Void)? = nil)
  public var key: Swift::String {
    get
  }
  public func install(host: any MapConductorCore::MapStyleHost) -> MapConductorCore::MapStyleInstallation
}
extension MapConductorVectorStyle::UnsupportedPolicy : Swift::Equatable {
  public static func == (a: MapConductorVectorStyle::UnsupportedPolicy, b: MapConductorVectorStyle::UnsupportedPolicy) -> Swift::Bool
}
public enum VectorStyleRules {
  public static var schemaVersion: Swift::Int {
    get
  }
  public static func compile(styleJSON: Swift::String, rulesJSON: Swift::String) throws -> MapConductorVectorStyle::CompiledStyle
  public static func describe(styleJSON: Swift::String) throws -> [MapConductorVectorStyle::StyleLayerInfo]
}
public struct CompiledStyle : Swift::Sendable {
  public let styleJSON: Swift::String
  public let mutations: [MapConductorCore::StyleMutation]
  public let affects: MapConductorVectorStyle::StyleAffects
  public let patchable: Swift::Bool
  public let diagnostics: [Swift::String]
}
public enum StyleAffects : Swift::String, Swift::Sendable {
  case none
  case ground
  case labels
  case both
  public init?(rawValue: Swift::String)
  public typealias RawValue = Swift::String
  public var rawValue: Swift::String {
    get
  }
}
public struct StyleLayerInfo : Swift::Sendable, Swift::Equatable {
  public let id: Swift::String
  public let kind: Swift::String
  public let sourceLayer: Swift::String?
  public let roles: [Swift::String]
  public let evidence: [Swift::String]
  public static func == (a: MapConductorVectorStyle::StyleLayerInfo, b: MapConductorVectorStyle::StyleLayerInfo) -> Swift::Bool
}
public enum VectorStyleError : Swift::Error, Swift::Equatable {
  case unreadable(Swift::String)
  public var message: Swift::String {
    get
  }
  public static func == (a: MapConductorVectorStyle::VectorStyleError, b: MapConductorVectorStyle::VectorStyleError) -> Swift::Bool
}
public enum VectorStyleSource : Swift::Equatable, Swift::Sendable {
  case text(Swift::String)
  case url(Swift::String, headers: [Swift::String : Swift::String] = [:])
  case currentDesign
  public var key: Swift::String {
    get
  }
  public static func == (a: MapConductorVectorStyle::VectorStyleSource, b: MapConductorVectorStyle::VectorStyleSource) -> Swift::Bool
}
public enum UnsupportedPolicy : Swift::Sendable {
  case report
  case reload
  public func hash(into hasher: inout Swift::Hasher)
  public var hashValue: Swift::Int {
    get
  }
}
public protocol VectorStyleRasteriser : AnyObject {
  func install(host: any MapConductorCore::MapStyleHost, styleJSON: Swift::String, affects: MapConductorVectorStyle::StyleAffects) -> any MapConductorVectorStyle::VectorStyleRasterisation
}
public protocol VectorStyleRasterisation : AnyObject {
  func restyle(styleJSON: Swift::String, affects: MapConductorVectorStyle::StyleAffects)
  func dispose()
}
extension MapConductorVectorStyle::StyleLayerKind : Swift::Equatable {}
extension MapConductorVectorStyle::StyleLayerKind : Swift::Hashable {}
extension MapConductorVectorStyle::StyleLayerKind : Swift::RawRepresentable {}
extension MapConductorVectorStyle::UnsupportedPolicy : Swift::Hashable {}
extension MapConductorVectorStyle::StyleAffects : Swift::Equatable {}
extension MapConductorVectorStyle::StyleAffects : Swift::Hashable {}
extension MapConductorVectorStyle::StyleAffects : Swift::RawRepresentable {}
