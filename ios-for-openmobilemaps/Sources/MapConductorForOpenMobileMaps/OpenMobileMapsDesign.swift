import Foundation
import MapConductorCore

/// 地図デザイン。
///
/// ## この SDK は「素の地図」を持たない
///
/// MapLibre や Mapbox と違い、Open Mobile Maps には既定の地図が無い。地図の中身は
/// すべてアプリが載せるレイヤであり、地図デザイン ＝ **どのタイルを一番下に敷くか** になる。
///
/// 現状はラスタータイル（XYZ）のみを扱う。ベクタータイルにも対応できるが、ラベルの描画に
/// 距離場フォントのアセットをモジュールへ同梱する必要があり、デザインの差し替えとは別の
/// 作業になるのでここには含めていない。
///
/// android-for-openmobilemaps の `OpenMobileMapsDesign.kt` と同じ内容・同じ既定値。
public protocol OpenMobileMapsMapDesignTypeProtocol: MapDesignTypeProtocol where Identifier == String {
    /// `{z}` `{x}` `{y}` を含むタイル URL。
    var tileUrlTemplate: String { get }

    /// タイル画像の一辺（px）。OSM 系は 256、@2x 系は 512。
    var tileSize: Int { get }
}

public extension OpenMobileMapsMapDesignTypeProtocol {
    var tileSize: Int { 256 }
}

public struct OpenMobileMapsDesign: OpenMobileMapsMapDesignTypeProtocol, Equatable {
    public let id: String
    public let tileUrlTemplate: String
    public let tileSize: Int
    public let attributionRules: [AttributionRule]

    public init(
        id: String,
        tileUrlTemplate: String,
        tileSize: Int = 256,
        attributionRules: [AttributionRule] = []
    ) {
        self.id = id
        self.tileUrlTemplate = tileUrlTemplate
        self.tileSize = tileSize
        self.attributionRules = attributionRules
    }

    public func getValue() -> String { "mapDesign_id=\(id),tiles=\(tileUrlTemplate)" }

    public static func == (lhs: OpenMobileMapsDesign, rhs: OpenMobileMapsDesign) -> Bool {
        lhs.getValue() == rhs.getValue() && lhs.tileSize == rhs.tileSize
    }

    /// OpenStreetMap の出典表示。
    ///
    /// **この SDK は出典表示を自前で出さない。** MapLibre や Google のように地図ビューの
    /// 中へロゴを描くものは、こちらが何もしなくても表示される。Open Mobile Maps は
    /// 地図の中身をすべてアプリが載せる作りなので、出典表示もアプリ側の責任になる。
    /// ここを空にするとコアの `MapAttributionOverlay` が何も描かず、
    /// **タイルの利用条件を満たさない状態**で表示される。
    private static let osmAttribution = "© OpenStreetMap contributors"

    public static let openStreetMap = OpenMobileMapsDesign(
        id: "osm",
        tileUrlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
        attributionRules: [AttributionRule(attribution: osmAttribution)]
    )

    public static let openStreetMapJapan = OpenMobileMapsDesign(
        id: "osm-japan",
        tileUrlTemplate: "https://tile.openstreetmap.jp/{z}/{x}/{y}.png",
        attributionRules: [AttributionRule(attribution: osmAttribution)]
    )

    public static let openTopoMap = OpenMobileMapsDesign(
        id: "opentopomap",
        tileUrlTemplate: "https://a.tile.opentopomap.org/{z}/{x}/{y}.png",
        // OpenTopoMap は地図データと地図スタイルの両方の表示を求めている。
        attributionRules: [
            AttributionRule(
                attribution: "map data: © OpenStreetMap contributors, SRTM | "
                    + "map style: © OpenTopoMap (CC-BY-SA)"
            ),
        ]
    )
}
