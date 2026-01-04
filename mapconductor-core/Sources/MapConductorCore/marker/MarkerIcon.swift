import CoreGraphics
import UIKit

public protocol MarkerIconProtocol {
    var scale: CGFloat { get }
    var anchor: CGPoint { get }
    var iconSize: CGFloat { get }
    var infoAnchor: CGPoint { get }
    var debug: Bool { get }

    func toBitmapIcon() -> BitmapIcon
}

public struct BitmapIcon: MarkerIconProtocol, Equatable, Hashable {
    public let bitmap: UIImage
    public let anchor: CGPoint
    public let size: CGSize
    public let scale: CGFloat
    public let iconSize: CGFloat
    public let infoAnchor: CGPoint
    public let debug: Bool

    public init(
        bitmap: UIImage,
        anchor: CGPoint = CGPoint(x: 0.5, y: 1.0),
        size: CGSize? = nil,
        scale: CGFloat = 1.0,
        iconSize: CGFloat? = nil,
        infoAnchor: CGPoint = CGPoint(x: 0.5, y: 0.0),
        debug: Bool = false
    ) {
        let resolvedSize = size ?? bitmap.size
        self.bitmap = bitmap
        self.anchor = anchor
        self.size = resolvedSize
        self.scale = scale
        self.iconSize = iconSize ?? max(resolvedSize.width, resolvedSize.height)
        self.infoAnchor = infoAnchor
        self.debug = debug
    }

    public func toBitmapIcon() -> BitmapIcon {
        self
    }

    public func toByteArray() -> [UInt8] {
        guard let data = bitmap.pngData() else { return [] }
        return [UInt8](data)
    }
}
