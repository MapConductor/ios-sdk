import Foundation

public enum TileServerRegistry {
    private static let lock = NSLock()
    private static var server: LocalTileServer?

    public static func get() -> LocalTileServer {
        lock.lock()
        defer { lock.unlock() }
        if let server {
            return server
        }
        let newServer = LocalTileServer.startServer()
        server = newServer
        return newServer
    }
}
