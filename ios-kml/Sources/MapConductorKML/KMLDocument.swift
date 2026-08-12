import Foundation

/// `<NetworkLink>` が参照する外部 KML/KMZ ドキュメント。
///
/// ``href`` は `<Link>`（KML 2.0 の旧名 `<Url>`）配下の `<href>` の値そのままで、
/// 相対参照の解決は行っていない。``KMLLoader`` が読み込み元 URL に対して解決する。
public struct KMLNetworkLink {
    public let href: String
    public let visibility: Bool

    public init(href: String, visibility: Bool = true) {
        self.href = href
        self.visibility = visibility
    }
}

/// ``KMLParser/parseDocument(data:)`` の結果。描画可能な ``features`` に加えて、
/// まだ取得していない外部参照 ``networkLinks`` を保持する。
///
/// ``KMLParser/parse(data:)`` は ``features`` だけを返す従来 API。リンク先まで合流させた
/// リストが欲しい場合は ``KMLLoader`` を使う。
public struct KMLDocument {
    public let features: [KMLFeature]
    public let networkLinks: [KMLNetworkLink]

    public init(features: [KMLFeature], networkLinks: [KMLNetworkLink] = []) {
        self.features = features
        self.networkLinks = networkLinks
    }
}
