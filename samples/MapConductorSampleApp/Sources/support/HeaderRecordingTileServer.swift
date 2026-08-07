import Foundation
import Network
import UIKit

/// タイル要求に**実際に載っていたヘッダ**を記録する計測用サーバ。
///
/// `RasterLayerState` の `userAgent` / `extraHeaders` が本当に送信されているかは、
/// 送り出す側のコードを読んでも分からない（プロバイダのネイティブ SDK が握っている）。
/// 受け取る側を自分で立てて、届いたヘッダをそのまま読むのが唯一の確実な確認方法。
///
/// アプリ内 127.0.0.1 に立てるので、シミュレータでも実機でも外部依存なしに動く。
/// docker やプロキシを用意すると実機から到達できず、実機固有の挙動を取り逃す。
///
/// 作りは `MapConductorCore.LocalTileServer` に合わせてあるが、こちらは計測専用なので
/// keep-alive も同時接続制限も持たない（1 リクエスト応答して閉じる）。
final class HeaderRecordingTileServer {
    /// 記録した 1 リクエスト分。ヘッダ名は小文字で正規化して入れる。
    struct Record {
        let path: String
        let headers: [String: String]
    }

    private let listener: NWListener
    private let queue: DispatchQueue
    private let lock = NSLock()

    private var records: [Record] = []
    private(set) var baseUrl: String

    /// 応答する PNG。毎回生成すると重いので 1 回だけ作る。
    private let tilePng: Data

    private init(listener: NWListener, queue: DispatchQueue, baseUrl: String, tilePng: Data) {
        self.listener = listener
        self.queue = queue
        self.baseUrl = baseUrl
        self.tilePng = tilePng
    }

    // MARK: - 読み出し

    var requestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return records.count
    }

    /// 直近のリクエストに載っていたヘッダ値。`name` は大文字小文字を問わない。
    func lastHeader(_ name: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return records.last?.headers[name.lowercased()]
    }

    /// これまでに一度でも観測したヘッダ値。
    ///
    /// 直近だけを見ると取りこぼす: ベースマップのスタイル要求とラスタタイル要求が
    /// 混ざって飛ぶので、「最後の 1 本」がこちらの狙ったタイルとは限らない。
    func anyHeader(_ name: String) -> String? {
        let key = name.lowercased()
        lock.lock()
        defer { lock.unlock() }
        for record in records.reversed() {
            if let value = record.headers[key] { return value }
        }
        return nil
    }

    func reset() {
        lock.lock()
        records.removeAll()
        lock.unlock()
    }

    func urlTemplate() -> String {
        "\(baseUrl)/tiles/{z}/{x}/{y}.png"
    }

    func stop() {
        listener.cancel()
    }

    // MARK: - 起動

    static func start() -> HeaderRecordingTileServer {
        let queue = DispatchQueue(label: "MapConductorSampleApp.HeaderRecordingTileServer", attributes: .concurrent)

        let listener: NWListener
        do {
            listener = try NWListener(using: .tcp)
        } catch {
            fatalError("計測サーバの listener を作れませんでした: \(error)")
        }

        let server = HeaderRecordingTileServer(
            listener: listener,
            queue: queue,
            baseUrl: "http://127.0.0.1:0",
            tilePng: makeTilePng()
        )
        listener.newConnectionHandler = { [weak server] connection in
            server?.handleConnection(connection)
        }

        let ready = DispatchSemaphore(value: 0)
        var startError: NWError?
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready, .failed:
                if case let .failed(error) = state { startError = error }
                ready.signal()
            default:
                break
            }
        }

        listener.start(queue: queue)
        ready.wait()

        if let startError {
            fatalError("計測サーバを起動できませんでした: \(startError)")
        }
        guard let port = listener.port else {
            fatalError("計測サーバがポートを取得できませんでした。")
        }

        server.baseUrl = "http://127.0.0.1:\(port.rawValue)"
        return server
    }

    /// 目視でも「敷かれている」と分かるよう、半透明のマゼンタで塗った 256px タイルを返す。
    private static func makeTilePng() -> Data {
        let size = CGSize(width: 256, height: 256)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            UIColor.magenta.withAlphaComponent(0.35).setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        return image.pngData() ?? Data()
    }

    // MARK: - 受信

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(connection: connection, buffer: Data())
    }

    private func receive(connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            var next = buffer
            if let data { next.append(data) }

            if next.count > 64 * 1024 {
                connection.cancel()
                return
            }

            if let headerRange = next.range(of: Data([13, 10, 13, 10])) {
                let headerData = next.subdata(in: 0..<headerRange.lowerBound)
                self.handleRequest(headerData: headerData, connection: connection)
                return
            }

            if isComplete || error != nil {
                connection.cancel()
                return
            }

            self.receive(connection: connection, buffer: next)
        }
    }

    private func handleRequest(headerData: Data, connection: NWConnection) {
        guard let text = String(data: headerData, encoding: .utf8) else {
            connection.cancel()
            return
        }

        // Swift では "\r\n" が 1 つの Character なので、CRLF 区切りの文字列を
        // `split(separator: "\n")` しても**行が分かれない**（全体が 1 要素になる）。
        // 先に LF へ正規化する。
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false)
        guard let requestLine = lines.first?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            connection.cancel()
            return
        }
        let path = requestLine.split(separator: " ").dropFirst().first.map(String.init) ?? ""

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            guard let index = trimmed.firstIndex(of: ":") else { continue }
            let key = trimmed[..<index].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = trimmed[trimmed.index(after: index)...].trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty, !value.isEmpty { headers[key] = value }
        }

        lock.lock()
        records.append(Record(path: path, headers: headers))
        lock.unlock()

        send(connection: connection)
    }

    private func send(connection: NWConnection) {
        var head = "HTTP/1.1 200 OK\r\n"
        head += "Content-Type: image/png\r\n"
        head += "Content-Length: \(tilePng.count)\r\n"
        // 計測なので毎回ネットワークまで来てほしい。キャッシュされるとヘッダが観測できない。
        head += "Cache-Control: no-store\r\n"
        head += "Connection: close\r\n\r\n"

        var payload = Data(head.utf8)
        payload.append(tilePng)

        connection.send(content: payload, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
