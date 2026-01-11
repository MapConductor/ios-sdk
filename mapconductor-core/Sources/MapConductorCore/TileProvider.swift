import Foundation

public protocol TileProvider: AnyObject {
    func renderTile(request: TileRequest) -> Data?
}
