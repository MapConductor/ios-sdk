import Foundation

/// KML/KMZ を URL から取得し、`<NetworkLink>` が参照する外部ドキュメントまで
/// たどって 1 枚のフィーチャリストへ平坦化するローダ。
///
/// KML はインターネット上の別の KML/KMZ を参照できる（NetworkLink）ため、取得は
/// キュー + 訪問済みセットのループで回す。参照がどれだけ連鎖しても呼び出しスタックを
/// 消費せず、循環参照があっても各 URL を 1 回しか取得しない。
///
/// - 取得数は `maxDocuments` 枚まで（ルート含む）。超過分のリンクは読まない。
/// - `visibility` が 0 の NetworkLink は追跡しない。
/// - リンク先の取得・解析失敗はそのリンクだけをスキップし `onDocumentError` へ通知する。
///   ルート自身の失敗は ``load(url:)`` がそのまま投げる。
/// - `refreshInterval` などの再読込モードは扱わない（一度だけ読む）。
///
/// `fetch` を差し替えると取得手段（テスト用スタブや独自 HTTP スタック）を注入できる。
/// 既定は `URLSession`（async/await。リダイレクトは http → https のプロトコル跨ぎも
/// 含めて自動で追う）。
public final class KMLLoader {
    public static let defaultMaxDocuments = 20

    public typealias Fetch = (String) async throws -> Data

    private let maxDocuments: Int
    private let onDocumentError: ((String, Error) -> Void)?
    private let fetch: Fetch

    public init(
        maxDocuments: Int = KMLLoader.defaultMaxDocuments,
        onDocumentError: ((String, Error) -> Void)? = nil,
        fetch: Fetch? = nil
    ) {
        self.maxDocuments = maxDocuments
        self.onDocumentError = onDocumentError
        self.fetch = fetch ?? Self.defaultFetch
    }

    /// `url`（http / https / file）の KML/KMZ を読み、NetworkLink の参照先も合流させる。
    public func load(url: String) async throws -> [KMLFeature] {
        try await collect(rootData: nil, rootUrl: url)
    }

    /// アプリ側で読み込んだ `data`（バンドル資産など）を読み、NetworkLink の参照先も合流させる。
    /// 相対 href は `baseURL` に対して解決する。nil のときは絶対 URL のリンクだけ追跡する。
    public func load(data: Data, baseURL: String? = nil) async throws -> [KMLFeature] {
        try await collect(rootData: data, rootUrl: baseURL)
    }

    private func collect(rootData: Data?, rootUrl: String?) async throws -> [KMLFeature] {
        var features: [KMLFeature] = []
        var queue: [String] = []
        var queueHead = 0
        var visited = Set<String>()
        var loaded = 0

        func merge(_ document: KMLDocument, baseUrl: String?) {
            loaded += 1
            features.append(contentsOf: document.features)
            for link in document.networkLinks {
                guard link.visibility else { continue }
                guard let resolved = Self.resolveHref(base: baseUrl, href: link.href) else { continue }
                if visited.insert(resolved).inserted {
                    queue.append(resolved)
                }
            }
        }

        // ルートは呼び出し側の指定そのものなので、失敗はスキップせず投げる。
        if let rootUrl {
            visited.insert(rootUrl)
        }
        let rootDocument: KMLDocument
        if let rootData {
            rootDocument = try KMLParser.parseDocument(data: rootData)
        } else {
            rootDocument = try KMLParser.parseDocument(data: await fetch(rootUrl!))
        }
        merge(rootDocument, baseUrl: rootUrl)

        while queueHead < queue.count, loaded < maxDocuments {
            let url = queue[queueHead]
            queueHead += 1
            let document: KMLDocument
            do {
                document = try KMLParser.parseDocument(data: await fetch(url))
            } catch {
                onDocumentError?(url, error)
                continue
            }
            merge(document, baseUrl: url)
        }
        return features
    }

    /// 相対 `href` を `base` に対して解決する。base 不明の相対参照は追跡できず nil。
    static func resolveHref(base: String?, href: String) -> String? {
        if href.contains("://") { return href }
        guard let base else { return nil }
        guard let baseUrl = URL(string: base), let resolved = URL(string: href, relativeTo: baseUrl) else {
            return nil
        }
        return resolved.absoluteString
    }

    /// 既定の取得手段。file URL はローカル読み込み、それ以外は `URLSession` に委ねる
    /// （`URLSession` はリダイレクトを自動で追い、http → https のプロトコル跨ぎも許す）。
    private static let defaultFetch: Fetch = { urlString in
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        if url.isFileURL {
            return try Data(contentsOf: url)
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return data
    }
}
