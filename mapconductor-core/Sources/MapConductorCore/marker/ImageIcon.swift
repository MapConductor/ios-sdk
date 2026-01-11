import CoreGraphics
import UIKit

/// iOS counterpart of Android's `ImageIcon`.
///
/// This icon uses the provided image as-is (scaled to the requested size) without applying the
/// default marker/pin shape.
public final class ImageIcon: MarkerIconProtocol {
    public static let defaultIconSize: CGFloat = DefaultMarkerIcon.defaultIconSize
    public static let defaultAnchor: CGPoint = CGPoint(x: 0.5, y: 0.5)
    public static let defaultInfoAnchor: CGPoint = CGPoint(x: 0.5, y: 0.5)

    public let iconSize: CGFloat
    public let scale: CGFloat
    public let anchor: CGPoint
    public let infoAnchor: CGPoint
    public let debug: Bool

    private let image: UIImage
    private let bitmapIcon: BitmapIcon

    public init(
        image: UIImage,
        iconSize: CGFloat = defaultIconSize,
        scale: CGFloat = 1.0,
        anchor: CGPoint = defaultAnchor,
        infoAnchor: CGPoint = defaultInfoAnchor,
        debug: Bool = false
    ) {
        self.image = image
        self.iconSize = iconSize
        self.scale = scale
        self.anchor = anchor
        self.infoAnchor = infoAnchor
        self.debug = debug
        self.bitmapIcon = Self.makeIcon(
            image: image,
            iconSize: iconSize,
            scale: scale,
            anchor: anchor,
            infoAnchor: infoAnchor,
            debug: debug
        )
    }

    public func toBitmapIcon() -> BitmapIcon { bitmapIcon }

    public func copy(
        image: UIImage? = nil,
        iconSize: CGFloat? = nil,
        scale: CGFloat? = nil,
        anchor: CGPoint? = nil,
        infoAnchor: CGPoint? = nil,
        debug: Bool? = nil
    ) -> ImageIcon {
        ImageIcon(
            image: image ?? self.image,
            iconSize: iconSize ?? self.iconSize,
            scale: scale ?? self.scale,
            anchor: anchor ?? self.anchor,
            infoAnchor: infoAnchor ?? self.infoAnchor,
            debug: debug ?? self.debug
        )
    }

    private static func makeIcon(
        image: UIImage,
        iconSize: CGFloat,
        scale: CGFloat,
        anchor: CGPoint,
        infoAnchor: CGPoint,
        debug: Bool
    ) -> BitmapIcon {
        let canvasSize = iconSize * scale
        let size = CGSize(width: canvasSize, height: canvasSize)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = UIScreen.main.scale
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let rendered = renderer.image { context in
            if debug {
                context.cgContext.setStrokeColor(UIColor.black.cgColor)
                context.cgContext.setLineWidth(1.0)
                context.cgContext.stroke(CGRect(origin: .zero, size: size))
            }
            image.draw(in: CGRect(origin: .zero, size: size))
        }

        return BitmapIcon(
            bitmap: rendered,
            anchor: anchor,
            size: size,
            scale: scale,
            iconSize: iconSize,
            infoAnchor: infoAnchor,
            debug: debug
        )
    }
}
