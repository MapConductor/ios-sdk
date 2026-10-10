import CMvtRender
import Foundation
import MapConductorCore
import MapConductorVectorStyle
import Metal
import Swift
import UIKit
import _Concurrency
import _StringProcessing
import _SwiftConcurrencyShims
final public class MetalTileRasterizer {
  public static func createOrNull(tileSize: Swift::Int) -> MapConductorVectorTile::MetalTileRasterizer?
  public init(tileSize: Swift::Int) throws
  final public func renderPng(_ tile: MapConductorVectorTile::TessellatedTile, decorate: ((Swift::UnsafeMutableRawBufferPointer) -> Swift::Void)? = nil) -> Foundation::Data?
  @objc deinit
}
@_hasMissingDesignatedInitializers final public class OfflinePackage : @unchecked Swift::Sendable {
  public struct Bounds : Swift::Codable, Swift::Equatable, Swift::Sendable {
    public var south: Swift::Double
    public var west: Swift::Double
    public var north: Swift::Double
    public var east: Swift::Double
    public init(south: Swift::Double, west: Swift::Double, north: Swift::Double, east: Swift::Double)
    public static func == (a: MapConductorVectorTile::OfflinePackage.MapConductorVectorTile::Bounds, b: MapConductorVectorTile::OfflinePackage.MapConductorVectorTile::Bounds) -> Swift::Bool
    public func encode(to encoder: any Swift::Encoder) throws
    public init(from decoder: any Swift::Decoder) throws
  }
  public struct Manifest : Swift::Codable, Swift::Sendable {
    public var version: Swift::Int
    public var bounds: MapConductorVectorTile::OfflinePackage.MapConductorVectorTile::Bounds
    public var minZoom: Swift::Int
    public var maxZoom: Swift::Int
    public var styleDigest: Swift::String
    public var createdAt: Swift::Int64
    public var tiles: Swift::Int
    public var glyphs: Swift::Int
    public var sprites: Swift::Int
    public var bytes: Swift::Int64
    public var sources: [Swift::String : Swift::String]
    public var glyphsTemplate: Swift::String?
    public var spriteBase: Swift::String?
    public func encode(to encoder: any Swift::Encoder) throws
    public init(from decoder: any Swift::Decoder) throws
  }
  final public let directory: Foundation::URL
  final public let manifest: MapConductorVectorTile::OfflinePackage.MapConductorVectorTile::Manifest
  public static let formatVersion: Swift::Int
  public static func open(_ directory: Foundation::URL) -> MapConductorVectorTile::OfflinePackage?
  public static func delete(_ directory: Foundation::URL)
  final public var styleJSON: Swift::String {
    get
  }
  final public func bytes(for url: Swift::String) -> Foundation::Data?
  final public func contains(_ url: Swift::String) -> Swift::Bool
  final public func upstreamURL(forRelativePath relativePath: Swift::String) -> Swift::String?
  final public func styleServed(by baseUrl: Swift::String) -> Swift::String
  public struct Stats : Swift::Equatable, Swift::Sendable, Swift::CustomStringConvertible {
    public var packageHits: Swift::Int
    public var networkFetches: Swift::Int
    public var blocked: Swift::Int
    public var description: Swift::String {
      get
    }
    public static func == (a: MapConductorVectorTile::OfflinePackage.MapConductorVectorTile::Stats, b: MapConductorVectorTile::OfflinePackage.MapConductorVectorTile::Stats) -> Swift::Bool
  }
  final public class Fetcher : @unchecked Swift::Sendable {
    final public var online: Swift::Bool {
      get
      set
    }
    final public var stats: MapConductorVectorTile::OfflinePackage.MapConductorVectorTile::Stats {
      get
    }
    public init(package: MapConductorVectorTile::OfflinePackage, online: Swift::Bool = true, headers: [Swift::String : Swift::String] = [:], upstream: ((Foundation::URL) -> Foundation::Data?)? = nil, onStats: ((MapConductorVectorTile::OfflinePackage.MapConductorVectorTile::Stats) -> Swift::Void)? = nil)
    final public func fetch(_ url: Foundation::URL) throws -> Foundation::Data?
    @objc deinit
  }
  @objc deinit
}
public struct OfflineUnavailableError : Swift::Error, Swift::CustomStringConvertible {
  public let url: Swift::String
  public init(url: Swift::String)
  public var description: Swift::String {
    get
  }
}
public enum OfflinePackageDownloader {
  public enum Phase : Swift::String, Swift::Sendable {
    case planning, tiles, glyphs, sprite, done
    public init?(rawValue: Swift::String)
    public typealias RawValue = Swift::String
    public var rawValue: Swift::String {
      get
    }
  }
  public struct Progress : Swift::Equatable, Swift::Sendable, Swift::CustomStringConvertible {
    public let phase: MapConductorVectorTile::OfflinePackageDownloader.MapConductorVectorTile::Phase
    public let done: Swift::Int
    public let total: Swift::Int
    public var description: Swift::String {
      get
    }
    public static func == (a: MapConductorVectorTile::OfflinePackageDownloader.MapConductorVectorTile::Progress, b: MapConductorVectorTile::OfflinePackageDownloader.MapConductorVectorTile::Progress) -> Swift::Bool
  }
  public static let maxTiles: Swift::Int
  public enum DownloadError : Swift::Error, Swift::CustomStringConvertible {
    case zoomRange(Swift::Int, Swift::Int)
    case tooManyTiles(Swift::Int)
    case glyphTemplate(Swift::String)
    case fetchFailed(Foundation::URL, Swift::Int?)
    case tileJSON(Foundation::URL, Swift::String)
    public var description: Swift::String {
      get
    }
  }
  public static func download(styleJSON: Swift::String, bounds: MapConductorVectorTile::OfflinePackage.MapConductorVectorTile::Bounds, minZoom: Swift::Int = 0, maxZoom: Swift::Int = 14, directory: Foundation::URL, headers: [Swift::String : Swift::String] = [:], parallelism: Swift::Int = 8, fetch: ((Foundation::URL) -> Foundation::Data?)? = nil, onProgress: @escaping @Sendable (MapConductorVectorTile::OfflinePackageDownloader.MapConductorVectorTile::Progress) -> Swift::Void = { _ in }) async throws -> MapConductorVectorTile::OfflinePackage
}
final public class StyleAssetCache {
  public init?(directory: Foundation::URL)
  final public func get(_ key: Swift::String) -> Foundation::Data?
  final public func put(_ key: Swift::String, _ value: Foundation::Data)
  @objc deinit
}
final public class VectorStyleHandoff {
  final public let documentId: Swift::String
  final public let url: Swift::String
  final public let attributions: [Swift::String]
  final public let support: any MapConductorCore::VectorStyleSupport
  final public let filesRoute: Swift::String?
  public init(styleJSON: Swift::String, support: any MapConductorCore::VectorStyleSupport, server: MapConductorCore::LocalTileServer = TileServerRegistry.get(), offlinePackage: MapConductorVectorTile::OfflinePackage? = nil, online: Swift::Bool = true, headers: [Swift::String : Swift::String] = [:])
  final public func dispose()
  public static func attributions(ofStyle json: Swift::String) -> [Swift::String]
  @objc deinit
}
final public class VectorTileProvider : MapConductorCore::TileProvider {
  public static let defaultTileSize: Swift::Int
  public static let labelResolution: Swift::Int
  public enum Content {
    case full
    case ground
    case labels
    public static func == (a: MapConductorVectorTile::VectorTileProvider.MapConductorVectorTile::Content, b: MapConductorVectorTile::VectorTileProvider.MapConductorVectorTile::Content) -> Swift::Bool
    public func hash(into hasher: inout Swift::Hasher)
    public var hashValue: Swift::Int {
      get
    }
  }
  final public var onGlyphsLoaded: (() -> Swift::Void)?
  public enum RenderMode {
    case cpu
    case gpu
    case auto
    public static func == (a: MapConductorVectorTile::VectorTileProvider.MapConductorVectorTile::RenderMode, b: MapConductorVectorTile::VectorTileProvider.MapConductorVectorTile::RenderMode) -> Swift::Bool
    public func hash(into hasher: inout Swift::Hasher)
    public var hashValue: Swift::Int {
      get
    }
  }
  final public var renderMode: MapConductorVectorTile::VectorTileProvider.MapConductorVectorTile::RenderMode {
    get
  }
  final public var gpuRenders: Swift::Int {
    get
  }
  final public var gpuFallbacks: Swift::Int {
    get
  }
  public init(styleJSON: Swift::String, tileSize: Swift::Int = VectorTileProvider.defaultTileSize, headers: [Swift::String : Swift::String] = [:], cacheBytes: Swift::Int = 16 * 1024 * 1024, renderMode: MapConductorVectorTile::VectorTileProvider.MapConductorVectorTile::RenderMode = .auto, assetCacheDirectory: Foundation::URL? = nil, renderedCacheBytes: Swift::Int = 48 * 1024 * 1024, sourceCacheBytes: Swift::Int = 128 * 1024 * 1024, renderScale: Swift::Int? = nil, fetchTile: ((Foundation::URL) throws -> Foundation::Data?)? = nil) throws
  @objc deinit
  final public func closeAsync()
  final public func close()
  final public func attributions() -> [Swift::String]
  final public func diagnostics() -> [Swift::String]
  final public func setStyle(_ styleJSON: Swift::String) throws
  final public var glyphGenerationValue: Swift::Int {
    get
  }
  final public var groundTiles: any MapConductorCore::TileProvider {
    get
  }
  final public var labelTiles: any MapConductorCore::TileProvider {
    get
  }
  final public func renderTile(request: MapConductorCore::TileRequest) -> Foundation::Data?
  final public func renderTile(request: MapConductorCore::TileRequest, isCancelled: () -> Swift::Bool) -> Foundation::Data?
  final public func renderTile(request: MapConductorCore::TileRequest, content: MapConductorVectorTile::VectorTileProvider.MapConductorVectorTile::Content = .full, isCancelled: () -> Swift::Bool = { false }) -> Foundation::Data?
}
final public class VectorTileRasteriser : MapConductorVectorStyle::VectorStyleRasteriser {
  public init(tileSize: Swift::Int? = nil, headers: [Swift::String : Swift::String] = [:], assetCacheDirectory: Foundation::URL? = nil, renderMode: MapConductorVectorTile::VectorTileProvider.MapConductorVectorTile::RenderMode = .auto, renderScale: Swift::Int? = nil)
  final public func install(host: any MapConductorCore::MapStyleHost, styleJSON: Swift::String, affects _: MapConductorVectorStyle::StyleAffects) -> any MapConductorVectorStyle::VectorStyleRasterisation
  @objc deinit
}
public enum VectorTileError : Swift::Error, Swift::CustomStringConvertible {
  case styleRejected(Swift::String)
  case renderFailed(Swift::Int32)
  case closed
  public var description: Swift::String {
    get
  }
}
public struct LabelTile {
  public let pixels: Foundation::Data
  public let placed: Swift::Int
}
final public class VectorTileRenderer {
  public static let defaultTileSize: Swift::UInt32
  public static let outputVersion: Swift::Int
  public init(styleJSON: Swift::String, displayTileSize: Swift::Int = 512) throws
  @objc deinit
  final public func close()
  final public func plan(z: Swift::UInt8, x: Swift::UInt32, y: Swift::UInt32) throws -> Swift::String
  final public func setStyle(_ styleJSON: Swift::String) throws
  final public func unsupportedLayerTypes() throws -> [Swift::String]
  final public func diagnostics() throws -> [Swift::String]
  final public func render(z: Swift::UInt8, x: Swift::UInt32, y: Swift::UInt32, tileSize: Swift::UInt32 = defaultTileSize, tiles: [Foundation::Data?]) throws -> Foundation::Data
  final public func tessellate(z: Swift::UInt8, x: Swift::UInt32, y: Swift::UInt32, tileSize: Swift::UInt32 = defaultTileSize, tiles: [Foundation::Data?]) throws -> MapConductorVectorTile::TessellatedTile
  final public func attributions() throws -> [Swift::String]
  final public func glyphsURLTemplate() throws -> Swift::String?
  final public func neededGlyphs(z: Swift::UInt8, x: Swift::UInt32, y: Swift::UInt32, tiles: [Foundation::Data?]) throws -> [Swift::String]
  @discardableResult
  final public func addGlyphs(_ pbf: Foundation::Data) throws -> Swift::Int
  final public func hasGlyphs() throws -> Swift::Bool
  final public func spriteURLs(pixelRatio: Swift::UInt32 = 2) throws -> (json: Swift::String, png: Swift::String)?
  @discardableResult
  final public func addSprite(json: Swift::String, png: Foundation::Data) throws -> Swift::Int
  final public func needsSprite() throws -> Swift::Bool
  final public func needsCPU(z: Swift::UInt8, tiles: [Foundation::Data?]) throws -> Swift::Bool
  final public func renderGeometry(z: Swift::UInt8, x: Swift::UInt32, y: Swift::UInt32, tileSize: Swift::UInt32 = defaultTileSize, tiles: [Foundation::Data?]) throws -> Foundation::Data
  final public func renderLabels(z: Swift::UInt8, x: Swift::UInt32, y: Swift::UInt32, tileSize: Swift::UInt32 = defaultTileSize, tiles: [Foundation::Data?]) throws -> MapConductorVectorTile::LabelTile
  @discardableResult
  final public func drawLabels(z: Swift::UInt8, x: Swift::UInt32, y: Swift::UInt32, tileSize: Swift::UInt32 = defaultTileSize, rgba: inout Foundation::Data, tiles: [Foundation::Data?]) throws -> Swift::Int
  @discardableResult
  final public func drawLabels(z: Swift::UInt8, x: Swift::UInt32, y: Swift::UInt32, tileSize: Swift::UInt32 = defaultTileSize, rgba: Swift::UnsafeMutableRawBufferPointer, tiles: [Foundation::Data?]) throws -> Swift::Int
}
public struct TessellatedTile {
  public let packed: [Swift::Float]
  public init(packed: [Swift::Float])
  public var extent: Swift::Float {
    get
  }
  public var background: (r: Swift::Float, g: Swift::Float, b: Swift::Float, a: Swift::Float)? {
    get
  }
  public var batchCount: Swift::Int {
    get
  }
  public var timings: (decode: Swift::Float, tessellate: Swift::Float, filterCompile: Swift::Float, fill: Swift::Float, line: Swift::Float) {
    get
  }
  public func batch(_ index: Swift::Int) -> (firstVertex: Swift::Int, vertexCount: Swift::Int)
  public var vertexOffset: Swift::Int {
    get
  }
  public static let vertexStride: Swift::Int
  public var vertexFloatCount: Swift::Int {
    get
  }
  public func withVertices<R>(_ body: (Swift::UnsafeBufferPointer<Swift::Float>) -> R) -> R
}
public enum MvtStatus {
  public static let ok: Swift::Int32
  public static let nullHandle: Swift::Int32
  public static let badArgument: Swift::Int32
  public static let renderFailed: Swift::Int32
  public static let panic: Swift::Int32
}
extension MapConductorVectorTile::OfflinePackageDownloader.MapConductorVectorTile::Phase : Swift::Equatable {}
extension MapConductorVectorTile::OfflinePackageDownloader.MapConductorVectorTile::Phase : Swift::Hashable {}
extension MapConductorVectorTile::OfflinePackageDownloader.MapConductorVectorTile::Phase : Swift::RawRepresentable {}
extension MapConductorVectorTile::VectorTileProvider.MapConductorVectorTile::Content : Swift::Equatable {}
extension MapConductorVectorTile::VectorTileProvider.MapConductorVectorTile::Content : Swift::Hashable {}
extension MapConductorVectorTile::VectorTileProvider.MapConductorVectorTile::RenderMode : Swift::Equatable {}
extension MapConductorVectorTile::VectorTileProvider.MapConductorVectorTile::RenderMode : Swift::Hashable {}
