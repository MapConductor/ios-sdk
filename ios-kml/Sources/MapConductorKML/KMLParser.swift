import Foundation
import UIKit

/// ``KMLParser`` が投げるエラー。
public enum KMLParseError: LocalizedError {
    /// XML として読めなかった（壊れた文書など）。
    case invalidXML(underlying: Error?)
    /// KMZ アーカイブに `.kml` エントリが無い。
    case kmzWithoutKMLEntry

    public var errorDescription: String? {
        switch self {
        case .invalidXML(let underlying):
            return "KML document could not be parsed as XML"
                + (underlying.map { ": \($0.localizedDescription)" } ?? "")
        case .kmzWithoutKMLEntry:
            return "KMZ archive contains no .kml entry"
        }
    }
}

/// Parses OGC KML 2.2 documents — and KMZ archives — into ``KMLFeature`` models for rendering
/// through ``KMLLayer``.
///
/// The parser walks the whole document into memory with Foundation's event-driven `XMLParser`,
/// collecting shared `<Style>` / `<StyleMap>` definitions and `<Placemark>` geometries, then
/// resolves each placemark's `styleUrl` reference to a concrete style.
///
/// Supported geometries: `Point`, `LineString`, `LinearRing`, `Polygon`
/// (with `innerBoundaryIs` holes), and `MultiGeometry`.
/// Supported styling: `LineStyle` (color, width), `PolyStyle` (color, fill, outline),
/// and `IconStyle` (color). KML `aabbggrr` colors are converted to `UIColor`.
///
/// Nested `<Document>` and `<Folder>` containers and nested `<MultiGeometry>` are handled with
/// explicit context stacks in the parser delegate — never by call-stack recursion — so
/// arbitrarily deep hierarchies cannot overflow the call stack.
/// `<NetworkLink>` references are collected into ``KMLDocument/networkLinks`` (not fetched here);
/// use ``KMLLoader`` to fetch and merge them.
public enum KMLParser {
    /// Parses a KML string into a list of static features.
    public static func parse(_ kml: String) throws -> [KMLFeature] {
        try parseDocument(data: Data(kml.utf8)).features
    }

    /// Parses KML or KMZ bytes into a list of static features.
    public static func parse(data: Data) throws -> [KMLFeature] {
        try parseDocument(data: data).features
    }

    /// Parses KML or KMZ bytes into a ``KMLDocument``, keeping unresolved
    /// `<NetworkLink>` references alongside the parsed features.
    ///
    /// KMZ input is detected by the ZIP signature and the first `.kml` entry in the archive
    /// (conventionally `doc.kml`) is used as the document.
    public static func parseDocument(data: Data) throws -> KMLDocument {
        if KMZArchive.isZipArchive(data) {
            return try parseKml(extractKmz(data))
        }
        return try parseKml(data)
    }

    private static func extractKmz(_ data: Data) throws -> Data {
        do {
            return try KMZArchive.firstEntryData(archive: data, pathExtension: "kml")
        } catch KMZArchiveError.entryNotFound {
            throw KMLParseError.kmzWithoutKMLEntry
        }
    }

    private static func parseKml(_ data: Data) throws -> KMLDocument {
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = false
        let reader = KMLDocumentReader()
        parser.delegate = reader
        guard parser.parse() else {
            throw KMLParseError.invalidXML(underlying: parser.parserError)
        }
        return KMLDocument(
            features: reader.placemarks.compactMap { $0.toFeature(styles: reader.styles, styleMaps: reader.styleMaps) },
            networkLinks: reader.networkLinks
        )
    }
}

// MARK: - Style model

/// `<Style>` 1 つぶんの読み取り結果。normal / highlight の別は持たない
/// （``KMLDocumentReader`` が StyleMap の normal だけを採るため）。
final class KMLStyle {
    var lineColor: UIColor?
    var lineWidth: CGFloat?
    var polyColor: UIColor?
    var iconColor: UIColor?
    var fill: Bool = true
    var outline: Bool = true
}

/// `<Placemark>` の読み取り結果。スタイル参照が未解決のままの中間表現で、
/// 文書全体を読み終えてから ``toFeature(styles:styleMaps:)`` で解決する。
///
/// KML はスタイルを文書の別の場所で定義し、`styleUrl` で参照する。さらに
/// `<StyleMap>` は normal / highlight の 2 状態を持つ。ここでは normal だけを採り、
/// 「参照 → StyleMap → 実体」の 2 段の間接をここで辿る。
final class RawPlacemark {
    var geometry: KMLGeometry?
    var styleUrl: String?
    var inlineStyle: KMLStyle?
    var properties: [String: Any] = [:]
    var name: String?
    var placemarkDescription: String?

    func toFeature(
        styles: [String: KMLStyle],
        styleMaps: [String: String]
    ) -> KMLFeature? {
        guard let geom = geometry else { return nil }
        let style = inlineStyle ?? resolveStyle(styleUrl, styles: styles, styleMaps: styleMaps)

        let strokeColor: UIColor?
        let fillColor: UIColor?
        if let style {
            strokeColor = style.outline ? style.lineColor : .clear
            fillColor = style.fill ? (style.polyColor ?? style.iconColor) : .clear
        } else {
            strokeColor = nil
            fillColor = nil
        }

        return KMLFeature(
            id: nil,
            geometry: geom,
            properties: properties,
            strokeColor: strokeColor,
            fillColor: fillColor,
            strokeWidth: style?.lineWidth
        )
    }

    private func resolveStyle(
        _ url: String?,
        styles: [String: KMLStyle],
        styleMaps: [String: String]
    ) -> KMLStyle? {
        guard let url else { return nil }
        if let style = styles[url] { return style }
        if let normal = styleMaps[url] { return styles[normal] }
        return nil
    }
}

// MARK: - XML reading

/// KML 文書 1 枚ぶんの走査。
///
/// `XMLParser` はイベント駆動（SAX）なので、「いまどの要素の中にいるか」を
/// 呼び出し側が持つ必要がある。ここでは開いた要素 1 つにつき ``Frame`` を 1 つ
/// 積む明示スタックで管理する。コールバックは再帰しないため、`<Document>` /
/// `<Folder>` / `<kml>` のコンテナ入れ子も `<MultiGeometry>` の入れ子も、どれだけ
/// 深くてもコールスタックを消費しない（android-kml の walkDocument /
/// readMultiGeometry のループ + 明示スタックに対応する）。
///
/// 認識しない要素は `skipDepth` でその閉じタグまで丸ごと読み飛ばす
/// （android-kml の `KMLXmlSupport.skip` に対応する）。
private final class KMLDocumentReader: NSObject, XMLParserDelegate {
    var styles: [String: KMLStyle] = [:]
    var styleMaps: [String: String] = [:]
    var placemarks: [RawPlacemark] = []
    var networkLinks: [KMLNetworkLink] = []

    /// スタイルの 3 区分（LineStyle / PolyStyle / IconStyle）。
    private enum StyleSection {
        case line, poly, icon
    }

    /// テキストを取り込む葉要素の種別。閉じタグでどこへ格納するかを決める。
    private enum TextKind {
        case placemarkName
        case placemarkDescription
        case placemarkStyleUrl
        case styleColor(StyleSection)
        case styleWidth
        case polyFill
        case polyOutline
        case pairKey
        case pairStyleUrl
        case leafCoordinates
        case ringCoordinates
        case networkLinkHref
        case networkLinkVisibility
        case dataValue
        case simpleData(name: String?)
    }

    /// 開いている要素 1 つぶんの文脈。didStartElement で必ず 1 つ積み、
    /// didEndElement で必ず 1 つ下ろす（skip 中を除く）ので常に釣り合う。
    private enum Frame {
        case container            // ルート要素 / Document / Folder / kml
        case style                // <Style>（共有・インライン共通）
        case styleSection(StyleSection)
        case styleMap
        case pair
        case placemark
        case leafGeometry(String) // Point / LineString / LinearRing
        case polygon
        case boundary(isOuter: Bool)
        case boundaryRing         // outer/innerBoundaryIs 配下の LinearRing
        case multiGeometry
        case extendedData
        case dataEntry
        case schemaData
        case networkLink
        case link                 // <Link>（KML 2.0 の旧名 <Url> も）
        case text(TextKind)
    }

    private var frames: [Frame] = []
    private var skipDepth = 0
    private var textBuffer = ""

    // Style / StyleMap の組み立て中の状態。これらの要素は入れ子にならないので 1 組で足りる。
    private var currentStyle: KMLStyle?
    private var currentStyleId: String?
    private var styleMapId: String?
    private var styleMapNormal: String?
    private var pairKey: String?
    private var pairUrl: String?

    // Placemark の組み立て中の状態。
    private var placemark: RawPlacemark?
    private var dataKey: String?
    private var dataValue: String?

    // ジオメトリの組み立て中の状態。MultiGeometry だけが入れ子になるのでスタックを持つ。
    private var multiStack: [[KMLGeometry]] = []
    private var leafCoords: [LonLat] = []
    private var ringCoords: [LonLat] = []
    private var boundaryCoords: [LonLat]?
    private var polygonOuter: [LonLat]?
    private var polygonInners: [[LonLat]] = []

    // MARK: XMLParserDelegate

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes attributeDict: [String: String]
    ) {
        if skipDepth > 0 {
            skipDepth += 1
            return
        }
        guard let top = frames.last else {
            // 最初の開始タグ（普通は <kml>）。名前が何であってもコンテナとして中を歩く。
            frames.append(.container)
            return
        }
        switch top {
        case .container:
            startInContainer(elementName, attributes: attributeDict)
        case .style:
            switch elementName {
            case "LineStyle": frames.append(.styleSection(.line))
            case "PolyStyle": frames.append(.styleSection(.poly))
            case "IconStyle": frames.append(.styleSection(.icon))
            default: skip()
            }
        case .styleSection(let section):
            startInStyleSection(section, elementName)
        case .styleMap:
            if elementName == "Pair" {
                pairKey = nil
                pairUrl = nil
                frames.append(.pair)
            } else {
                skip()
            }
        case .pair:
            switch elementName {
            case "key": beginText(.pairKey)
            case "styleUrl": beginText(.pairStyleUrl)
            default: skip()
            }
        case .placemark, .multiGeometry:
            startGeometryOrPlacemarkChild(in: top, elementName)
        case .leafGeometry:
            if elementName == "coordinates" {
                beginText(.leafCoordinates)
            } else {
                skip()
            }
        case .polygon:
            switch elementName {
            case "outerBoundaryIs":
                boundaryCoords = nil
                frames.append(.boundary(isOuter: true))
            case "innerBoundaryIs":
                boundaryCoords = nil
                frames.append(.boundary(isOuter: false))
            default:
                skip()
            }
        case .boundary:
            if elementName == "LinearRing" {
                ringCoords = []
                frames.append(.boundaryRing)
            } else {
                skip()
            }
        case .boundaryRing:
            if elementName == "coordinates" {
                beginText(.ringCoordinates)
            } else {
                skip()
            }
        case .extendedData:
            switch elementName {
            case "Data":
                dataKey = attributeDict["name"]
                dataValue = nil
                frames.append(.dataEntry)
            case "SchemaData":
                frames.append(.schemaData)
            default:
                skip()
            }
        case .dataEntry:
            if elementName == "value" {
                beginText(.dataValue)
            } else {
                skip()
            }
        case .schemaData:
            if elementName == "SimpleData" {
                beginText(.simpleData(name: attributeDict["name"]))
            } else {
                skip()
            }
        case .networkLink:
            switch elementName {
            case "Link", "Url": frames.append(.link)
            case "visibility": beginText(.networkLinkVisibility)
            default: skip()
            }
        case .link:
            if elementName == "href" {
                beginText(.networkLinkHref)
            } else {
                skip()
            }
        case .text:
            // 葉要素の中の要素は読まない（android-kml の readText と同じ扱い）。
            skip()
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?
    ) {
        if skipDepth > 0 {
            skipDepth -= 1
            return
        }
        guard let top = frames.popLast() else { return }
        switch top {
        case .container, .styleSection, .extendedData, .schemaData, .link:
            break
        case .style:
            endStyle()
        case .styleMap:
            if let id = styleMapId, let normal = styleMapNormal {
                styleMaps[id] = normal
            }
            styleMapId = nil
            styleMapNormal = nil
        case .pair:
            if pairKey == "normal" {
                styleMapNormal = pairUrl
            }
        case .placemark:
            endPlacemark()
        case .leafGeometry(let type):
            deliverGeometry(finishLeafGeometry(type))
        case .polygon:
            deliverGeometry(finishPolygon())
        case .boundary(let isOuter):
            if isOuter {
                polygonOuter = boundaryCoords
            } else if let coords = boundaryCoords {
                polygonInners.append(coords)
            }
        case .boundaryRing:
            boundaryCoords = ringCoords
        case .multiGeometry:
            let closed = KMLGeometry.geometryCollection(geometries: multiStack.removeLast())
            deliverGeometry(closed)
        case .networkLink:
            if let href = networkLinkHref, !href.isEmpty {
                networkLinks.append(KMLNetworkLink(href: href, visibility: networkLinkVisibility))
            }
            networkLinkHref = nil
            networkLinkVisibility = true
        case .dataEntry:
            if let key = dataKey {
                placemark?.properties[key] = dataValue ?? NSNull()
            }
            dataKey = nil
            dataValue = nil
        case .text(let kind):
            endText(kind)
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if skipDepth == 0, case .text = frames.last {
            textBuffer += string
        }
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if skipDepth == 0, case .text = frames.last {
            textBuffer += String(data: CDATABlock, encoding: .utf8) ?? ""
        }
    }

    // MARK: Element starts

    private func startInContainer(_ elementName: String, attributes: [String: String]) {
        switch elementName {
        case "Document", "Folder", "kml":
            frames.append(.container)
        case "Style":
            currentStyle = KMLStyle()
            currentStyleId = attributes["id"]
            frames.append(.style)
        case "StyleMap":
            styleMapId = attributes["id"]
            styleMapNormal = nil
            frames.append(.styleMap)
        case "Placemark":
            placemark = RawPlacemark()
            frames.append(.placemark)
        case "NetworkLink":
            networkLinkHref = nil
            networkLinkVisibility = true
            frames.append(.networkLink)
        default:
            skip()
        }
    }

    private func startInStyleSection(_ section: StyleSection, _ elementName: String) {
        switch (section, elementName) {
        case (_, "color"):
            beginText(.styleColor(section))
        case (.line, "width"):
            beginText(.styleWidth)
        case (.poly, "fill"):
            beginText(.polyFill)
        case (.poly, "outline"):
            beginText(.polyOutline)
        default:
            skip()
        }
    }

    private func startGeometryOrPlacemarkChild(in top: Frame, _ elementName: String) {
        switch elementName {
        case "Point", "LineString", "LinearRing":
            leafCoords = []
            frames.append(.leafGeometry(elementName))
            return
        case "Polygon":
            polygonOuter = nil
            polygonInners = []
            frames.append(.polygon)
            return
        case "MultiGeometry":
            multiStack.append([])
            frames.append(.multiGeometry)
            return
        default:
            break
        }
        guard case .placemark = top else {
            skip()
            return
        }
        switch elementName {
        case "name": beginText(.placemarkName)
        case "description": beginText(.placemarkDescription)
        case "styleUrl": beginText(.placemarkStyleUrl)
        case "Style":
            currentStyle = KMLStyle()
            currentStyleId = nil
            frames.append(.style)
        case "ExtendedData":
            frames.append(.extendedData)
        default:
            skip()
        }
    }

    // MARK: Element ends

    private func endStyle() {
        guard let style = currentStyle else { return }
        if let placemark {
            // Placemark 直下の <Style> はそのプレースマーク専用のインラインスタイル。
            placemark.inlineStyle = style
        } else if let id = currentStyleId {
            styles[id] = style
        }
        currentStyle = nil
        currentStyleId = nil
    }

    private func endPlacemark() {
        guard let placemark else { return }
        // <name> / <description> は ExtendedData と衝突したとき ExtendedData を優先する
        // （android-kml の putIfAbsent と同じ。値なしの Data（NSNull）は不在扱いで置き換える）。
        func putIfAbsent(_ key: String, _ value: String?) {
            guard let value, !value.isEmpty else { return }
            let existing = placemark.properties[key]
            if existing == nil || existing is NSNull {
                placemark.properties[key] = value
            }
        }
        putIfAbsent("name", placemark.name)
        putIfAbsent("description", placemark.placemarkDescription)
        placemarks.append(placemark)
        self.placemark = nil
    }

    private func endText(_ kind: TextKind) {
        let raw = textBuffer
        textBuffer = ""
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        switch kind {
        case .placemarkName:
            placemark?.name = trimmed
        case .placemarkDescription:
            placemark?.placemarkDescription = trimmed
        case .placemarkStyleUrl:
            placemark?.styleUrl = Self.removeLeadingHash(trimmed)
        case .styleColor(let section):
            let color = Self.parseKmlColor(trimmed)
            switch section {
            case .line: currentStyle?.lineColor = color
            case .poly: currentStyle?.polyColor = color
            case .icon: currentStyle?.iconColor = color
            }
        case .styleWidth:
            currentStyle?.lineWidth = Double(trimmed).map { CGFloat($0) }
        case .polyFill:
            currentStyle?.fill = trimmed != "0"
        case .polyOutline:
            currentStyle?.outline = trimmed != "0"
        case .pairKey:
            pairKey = trimmed
        case .pairStyleUrl:
            pairUrl = Self.removeLeadingHash(trimmed)
        case .leafCoordinates:
            leafCoords = Self.parseCoordinates(raw)
        case .ringCoordinates:
            ringCoords = Self.parseCoordinates(raw)
        case .networkLinkHref:
            networkLinkHref = trimmed
        case .networkLinkVisibility:
            networkLinkVisibility = trimmed != "0"
        case .dataValue:
            dataValue = trimmed
        case .simpleData(let name):
            if let name {
                placemark?.properties[name] = trimmed
            }
        }
    }

    // MARK: Geometry assembly

    /// `<Point>` / `<LineString>` / `<LinearRing>` を閉じたときのジオメトリ。
    /// 座標が無いときは nil（android-kml の KMLGeometryReader.readGeometry と同じ）。
    private func finishLeafGeometry(_ type: String) -> KMLGeometry? {
        if type == "Point" {
            guard let first = leafCoords.first else { return nil }
            return .point(longitude: first.longitude, latitude: first.latitude)
        }
        // LineString / LinearRing
        guard !leafCoords.isEmpty else { return nil }
        return .lineString(coordinates: leafCoords)
    }

    /// `<Polygon>` を閉じたときのジオメトリ。外環が無い・空のときは nil。
    /// 環の順序は「最初が外環（outerBoundaryIs）、以降が穴（innerBoundaryIs）」。
    /// 描画側はその約束で扱うので、その順序をここで作る。
    private func finishPolygon() -> KMLGeometry? {
        guard let exterior = polygonOuter, !exterior.isEmpty else { return nil }
        var rings: [[LonLat]] = [exterior]
        rings.append(contentsOf: polygonInners)
        return .polygon(rings: rings)
    }

    /// 完成したジオメトリの届け先。MultiGeometry の中なら積み上げ中のコレクションへ、
    /// そうでなければプレースマークのジオメトリへ（後勝ち。android-kml の readPlacemark と同じ）。
    private func deliverGeometry(_ geometry: KMLGeometry?) {
        if !multiStack.isEmpty {
            if let geometry {
                multiStack[multiStack.count - 1].append(geometry)
            }
        } else {
            placemark?.geometry = geometry
        }
    }

    // MARK: NetworkLink state

    private var networkLinkHref: String?
    private var networkLinkVisibility = true

    // MARK: Helpers

    private func beginText(_ kind: TextKind) {
        textBuffer = ""
        frames.append(.text(kind))
    }

    /// 認識しない要素をその閉じタグまで丸ごと読み飛ばす。
    private func skip() {
        skipDepth = 1
    }

    private static func removeLeadingHash(_ value: String) -> String {
        value.hasPrefix("#") ? String(value.dropFirst()) : value
    }

    /// Parses whitespace-separated `lon,lat[,alt]` tuples.
    static func parseCoordinates(_ text: String) -> [LonLat] {
        var result: [LonLat] = []
        for token in text.split(whereSeparator: { $0.isWhitespace }) {
            let parts = token.split(separator: ",", omittingEmptySubsequences: false)
            guard parts.count >= 2,
                  let lon = Double(parts[0].trimmingCharacters(in: .whitespaces)),
                  let lat = Double(parts[1].trimmingCharacters(in: .whitespaces)) else { continue }
            result.append(LonLat(longitude: lon, latitude: lat))
        }
        return result
    }

    /// Converts a KML `aabbggrr` (or `bbggrr`) hex color to a `UIColor`.
    static func parseKmlColor(_ hex: String) -> UIColor? {
        let h = hex.trimmingCharacters(in: .whitespaces)
        func component(_ start: Int) -> CGFloat? {
            let lower = h.index(h.startIndex, offsetBy: start)
            let upper = h.index(lower, offsetBy: 2)
            guard let value = UInt8(h[lower..<upper], radix: 16) else { return nil }
            return CGFloat(value) / 255.0
        }
        switch h.count {
        case 8:
            guard let a = component(0), let b = component(2), let g = component(4), let r = component(6) else {
                return nil
            }
            return UIColor(red: r, green: g, blue: b, alpha: a)
        case 6:
            guard let b = component(0), let g = component(2), let r = component(4) else { return nil }
            return UIColor(red: r, green: g, blue: b, alpha: 1.0)
        default:
            return nil
        }
    }
}
