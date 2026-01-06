import Foundation
import Network

public final class LocalTileServer {
    public private(set) var baseUrl: String

    private let listener: NWListener
    private let queue: DispatchQueue
    private let providersLock = NSLock()
    private var providers: [String: TileProvider] = [:]

    private init(listener: NWListener, queue: DispatchQueue, baseUrl: String) {
        self.listener = listener
        self.queue = queue
        self.baseUrl = baseUrl
    }

    public func register(routeId: String, provider: TileProvider) {
        providersLock.lock()
        providers[routeId] = provider
        providersLock.unlock()
    }

    public func unregister(routeId: String) {
        providersLock.lock()
        providers.removeValue(forKey: routeId)
        providersLock.unlock()
    }

    public func urlTemplate(routeId: String, version: Int64) -> String {
        "\(baseUrl)/tiles/\(routeId)/\(version)/{z}/{x}/{y}.png"
    }

    public func stop() {
        listener.cancel()
    }

    public static func startServer() -> LocalTileServer {
        let queue = DispatchQueue(label: "MapConductorTileServer", attributes: .concurrent)
        let listener: NWListener
        do {
            listener = try NWListener(using: .tcp)
        } catch {
            fatalError("Failed to create tile server listener: \(error)")
        }

        let server = LocalTileServer(listener: listener, queue: queue, baseUrl: "http://127.0.0.1:0")

        listener.newConnectionHandler = { [weak server] connection in
            server?.handleConnection(connection)
        }

        let readySemaphore = DispatchSemaphore(value: 0)
        var startError: NWError?
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready, .failed:
                if case let .failed(error) = state {
                    startError = error
                }
                readySemaphore.signal()
            default:
                break
            }
        }

        listener.start(queue: queue)
        readySemaphore.wait()

        if let startError {
            fatalError("Failed to start tile server: \(startError)")
        }

        guard let port = listener.port else {
            fatalError("Tile server failed to obtain a port.")
        }

        server.baseUrl = "http://127.0.0.1:\(port.rawValue)"
        return server
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveRequest(connection: connection, buffer: Data())
    }

    private func receiveRequest(connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var nextBuffer = buffer
            if let data {
                nextBuffer.append(data)
            }

            if let headerRange = nextBuffer.range(of: Data([13, 10, 13, 10])) {
                let headerData = nextBuffer.subdata(in: 0..<headerRange.lowerBound)
                self.handleRequest(headerData: headerData, connection: connection)
                return
            }

            if isComplete || error != nil {
                connection.cancel()
                return
            }

            self.receiveRequest(connection: connection, buffer: nextBuffer)
        }
    }

    private func handleRequest(headerData: Data, connection: NWConnection) {
        guard let headerString = String(data: headerData, encoding: .utf8) else {
            sendNotFound(connection: connection)
            return
        }

        let lines = headerString.split(whereSeparator: \.isNewline)
        guard let requestLine = lines.first else {
            sendNotFound(connection: connection)
            return
        }

        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else {
            sendNotFound(connection: connection)
            return
        }

        let method = parts[0]
        let path = parts[1].split(separator: "?")[0]

        guard method == "GET" else {
            sendResponse(
                connection: connection,
                status: 405,
                reason: "Method Not Allowed",
                contentType: "text/plain",
                body: Data("Method not allowed".utf8)
            )
            return
        }

        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let segments = trimmed.split(separator: "/")
        guard segments.count >= 6, segments[0] == "tiles" else {
            sendNotFound(connection: connection)
            return
        }

        let routeId = String(segments[1])
        let z = Int(segments[3])
        let x = Int(segments[4])
        let yPart = segments[5].split(separator: ".").first
        let y = yPart.flatMap { Int($0) }

        guard let z, let x, let y else {
            sendNotFound(connection: connection)
            return
        }

        let provider = getProvider(routeId: routeId)
        let bytes = provider?.renderTile(request: TileRequest(x: x, y: y, z: z))
        guard let bytes else {
            sendNotFound(connection: connection)
            return
        }

        sendResponse(
            connection: connection,
            status: 200,
            reason: "OK",
            contentType: "image/png",
            body: bytes
        )
    }

    private func getProvider(routeId: String) -> TileProvider? {
        providersLock.lock()
        defer { providersLock.unlock() }
        return providers[routeId]
    }

    private func sendNotFound(connection: NWConnection) {
        sendResponse(
            connection: connection,
            status: 404,
            reason: "Not Found",
            contentType: "text/plain",
            body: Data("Not found".utf8)
        )
    }

    private func sendResponse(
        connection: NWConnection,
        status: Int,
        reason: String,
        contentType: String,
        body: Data
    ) {
        var response = Data()
        response.append("HTTP/1.1 \(status) \(reason)\r\n".data(using: .utf8) ?? Data())
        response.append("Content-Type: \(contentType)\r\n".data(using: .utf8) ?? Data())
        response.append("Content-Length: \(body.count)\r\n".data(using: .utf8) ?? Data())
        response.append("Cache-Control: no-store\r\n".data(using: .utf8) ?? Data())
        response.append("Connection: close\r\n\r\n".data(using: .utf8) ?? Data())
        response.append(body)

        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
