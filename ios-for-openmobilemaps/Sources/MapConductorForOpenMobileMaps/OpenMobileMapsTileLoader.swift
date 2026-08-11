import DjinniSupport
import Foundation
import MapCore
import UIKit

/// タイルの読み込み。**ローカルタイルサーバの 404 を「透明なタイル」に読み替える**。
///
/// ## なぜ要るのか
///
/// マーカーをラスタータイルとして焼く経路（``OpenMobileMapsMarkerController``）では、
/// ローカルのタイルサーバが**マーカーが 1 つも無いタイルに 404 を返す**。MapLibre などは
/// それを「空タイル」として扱うので問題にならないが、Open Mobile Maps は 404 を
/// **エラー**として扱い、そのタイルを「存在しない」と記録する。
///
/// 子タイルが存在しない領域はステンシルマスクに穴が開き、**保持されている粗い親タイルが
/// そこだけ透けて見え続ける**。android では「マーカーの無い領域だけ巨大な矩形が残る」という
/// 形で出た。
///
/// ## 空データではなく本物の透明 PNG を返すこと
///
/// `MCLoaderStatus.OK` にデータ無しで返しても、SDK 側はデコード失敗として扱う。
/// 1x1 の透明 PNG から作ったテクスチャを渡せば通常の読み込み経路をそのまま通り、
/// タイル全面に引き伸ばされるだけで見た目には何も出ない。
///
/// android-for-openmobilemaps の `emptyLocalTileInterceptor` と同じ役割。あちらは okhttp の
/// インターセプタで 404 を 200 に書き換えているが、iOS の `MCTextureLoader` は
/// `URLSession` を内部で握っていて差し込み口が無いので、**結果の側**で読み替える。
final class OpenMobileMapsTileLoader: MCTextureLoader {
    override func loadTexture(_ url: String, etag: String?) -> MCTextureLoaderResult {
        Self.substituteEmptyTile(for: url, result: super.loadTexture(url, etag: etag))
    }

    override func loadTextureAsync(_ url: String, etag: String?) -> DJFuture<MCTextureLoaderResult> {
        let promise = DJPromise<MCTextureLoaderResult>()
        super.loadTextureAsync(url, etag: etag).then { future in
            guard let result = future.get() else { return nil }
            promise.setValue(Self.substituteEmptyTile(for: url, result: result))
            return nil
        }
        return promise.getFuture()
    }

    /// ローカルサーバからのエラーだけを透明タイルへ読み替える。
    ///
    /// **ローカル判定を外さないこと。** 外すと本物のタイルサーバの障害まで透明タイルで
    /// 覆い隠すことになり、地図が白いまま「読み込み中にも失敗にも見えない」状態になる。
    private static func substituteEmptyTile(
        for url: String,
        result: MCTextureLoaderResult
    ) -> MCTextureLoaderResult {
        guard result.status != .OK, isLocalTileServer(url), let texture = transparentTexture else {
            return result
        }
        return MCTextureLoaderResult(data: texture, etag: nil, status: .OK, errorCode: nil)
    }

    private static func isLocalTileServer(_ url: String) -> Bool {
        guard let host = URL(string: url)?.host else { return false }
        return host == "127.0.0.1" || host == "localhost" || host == "::1"
    }

    /// 空タイルとして返す 1x1 の透明テクスチャ。1 枚作れば使い回せる。
    private static let transparentTexture: TextureHolder? = {
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1), format: format).image { _ in }
        guard let cgImage = image.cgImage else { return nil }
        return try? TextureHolder(cgImage)
    }()
}
