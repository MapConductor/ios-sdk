import CoreGraphics
import UIKit

/// Image-fill variant of the default pin icon.
///
/// This mirrors Android's `ImageDefaultIcon`: the image is center-cropped and drawn while clipped
/// to the marker shape, then the marker stroke (and optional label) is applied on top.
public final class ImageDefaultIcon: MarkerIconProtocol {
    public static let defaultIconSize: CGFloat = DefaultMarkerIcon.defaultIconSize
    public static let defaultStrokeWidth: CGFloat = DefaultMarkerIcon.defaultStrokeWidth
    public static let defaultStrokeColor: UIColor = DefaultMarkerIcon.defaultStrokeColor
    public static let defaultLabelTextSize: CGFloat = DefaultMarkerIcon.defaultLabelTextSize
    public static let defaultLabelTextColor: UIColor = DefaultMarkerIcon.defaultLabelTextColor
    public static let defaultLabelStrokeColor: UIColor = DefaultMarkerIcon.defaultLabelStrokeColor
    public static let defaultLabelTypeFace: UIFont = DefaultMarkerIcon.defaultLabelTypeFace
    public static let defaultInfoAnchor: CGPoint = DefaultMarkerIcon.defaultInfoAnchor
    public static let defaultAnchor = CGPoint(x: 0.5, y: 1.0)

    public let scale: CGFloat
    public let anchor: CGPoint
    public let iconSize: CGFloat
    public let infoAnchor: CGPoint
    public let debug: Bool

    private let backgroundImage: UIImage
    public let strokeColor: UIColor
    public let strokeWidth: CGFloat
    public let label: String?
    public let labelTextColor: UIColor?
    public let labelTextSize: CGFloat
    public let labelTypeFace: UIFont
    public let labelStrokeColor: UIColor
    private let bitmapIcon: BitmapIcon

    public init(
        backgroundImage: UIImage,
        strokeColor: UIColor = defaultStrokeColor,
        strokeWidth: CGFloat = defaultStrokeWidth,
        scale: CGFloat = 1.0,
        label: String? = nil,
        labelTextColor: UIColor? = defaultLabelTextColor,
        labelTextSize: CGFloat = defaultLabelTextSize,
        labelTypeFace: UIFont = defaultLabelTypeFace,
        labelStrokeColor: UIColor = defaultLabelStrokeColor,
        infoAnchor: CGPoint = defaultInfoAnchor,
        iconSize: CGFloat = defaultIconSize,
        debug: Bool = false
    ) {
        self.backgroundImage = backgroundImage
        self.strokeColor = strokeColor
        self.strokeWidth = strokeWidth
        self.scale = scale
        self.label = label
        self.labelTextColor = labelTextColor
        self.labelTextSize = labelTextSize
        self.labelTypeFace = labelTypeFace
        self.labelStrokeColor = labelStrokeColor
        self.infoAnchor = infoAnchor
        self.iconSize = iconSize
        self.debug = debug
        self.anchor = Self.defaultAnchor
        self.bitmapIcon = Self.makeIcon(
            backgroundImage: backgroundImage,
            iconSize: iconSize,
            scale: scale,
            strokeColor: strokeColor,
            strokeWidth: strokeWidth,
            label: label,
            labelTextColor: labelTextColor,
            labelTextSize: labelTextSize,
            labelTypeFace: labelTypeFace,
            labelStrokeColor: labelStrokeColor,
            anchor: Self.defaultAnchor,
            infoAnchor: infoAnchor,
            debug: debug
        )
    }

    public func toBitmapIcon() -> BitmapIcon { bitmapIcon }

    public func copy(
        backgroundImage: UIImage? = nil,
        strokeColor: UIColor? = nil,
        strokeWidth: CGFloat? = nil,
        scale: CGFloat? = nil,
        label: String? = nil,
        labelTextColor: UIColor? = nil,
        labelTextSize: CGFloat? = nil,
        labelTypeFace: UIFont? = nil,
        labelStrokeColor: UIColor? = nil,
        iconSize: CGFloat? = nil,
        debug: Bool? = nil
    ) -> ImageDefaultIcon {
        ImageDefaultIcon(
            backgroundImage: backgroundImage ?? self.backgroundImage,
            strokeColor: strokeColor ?? self.strokeColor,
            strokeWidth: strokeWidth ?? self.strokeWidth,
            scale: scale ?? self.scale,
            label: label ?? self.label,
            labelTextColor: labelTextColor ?? self.labelTextColor,
            labelTextSize: labelTextSize ?? self.labelTextSize,
            labelTypeFace: labelTypeFace ?? self.labelTypeFace,
            labelStrokeColor: labelStrokeColor ?? self.labelStrokeColor,
            infoAnchor: self.infoAnchor,
            iconSize: iconSize ?? self.iconSize,
            debug: debug ?? self.debug
        )
    }

    private static func makeIcon(
        backgroundImage: UIImage,
        iconSize: CGFloat,
        scale: CGFloat,
        strokeColor: UIColor,
        strokeWidth: CGFloat,
        label: String?,
        labelTextColor: UIColor?,
        labelTextSize: CGFloat,
        labelTypeFace: UIFont,
        labelStrokeColor: UIColor,
        anchor: CGPoint,
        infoAnchor: CGPoint,
        debug: Bool
    ) -> BitmapIcon {
        let canvasSize = iconSize * scale
        let resolvedFont = labelTypeFace.withSize(labelTextSize)
        let outlineStrokeWidth = max(1.0 * scale, 2.0)

        var labelSize: CGSize = .zero
        if let label {
            labelSize = DefaultMarkerIcon.measureLabel(label, font: resolvedFont, strokeWidth: outlineStrokeWidth)
        }

        let padding = canvasSize * 0.1
        let bitmapWidth = max(canvasSize, labelSize.width + padding)
        let bitmapHeight = canvasSize
        let markerOffsetX = (bitmapWidth - canvasSize) / 2.0
        let markerRect = CGRect(x: markerOffsetX, y: 0, width: canvasSize, height: canvasSize)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = UIScreen.main.scale
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: bitmapWidth, height: bitmapHeight), format: format)
        let image = renderer.image { context in
            context.cgContext.setAllowsAntialiasing(true)
            context.cgContext.setShouldAntialias(true)
            context.cgContext.interpolationQuality = .high
            if debug {
                context.cgContext.setStrokeColor(UIColor.black.cgColor)
                context.cgContext.setLineWidth(1.0)
                context.cgContext.stroke(CGRect(x: 0, y: 0, width: bitmapWidth, height: bitmapHeight))
            }

            let path = DefaultMarkerIcon.createMarkerPath(
                canvasSize: canvasSize,
                iconScale: scale,
                strokeWidth: strokeWidth,
                horizontalOffset: markerOffsetX
            )

            context.cgContext.saveGState()
            context.cgContext.addPath(path.cgPath)
            context.cgContext.clip()

            // Center-crop into a square canvas, like Android's `ImageDefaultIcon`.
            let imageSize = backgroundImage.size
            if imageSize.width > 0, imageSize.height > 0 {
                let drawableRatio = imageSize.width / imageSize.height
                let canvasRatio: CGFloat = 1.0

                let drawRect: CGRect
                if drawableRatio > canvasRatio {
                    let scaledWidth = canvasSize * drawableRatio
                    let offsetX = (canvasSize - scaledWidth) / 2.0
                    drawRect = CGRect(x: markerRect.minX + offsetX, y: markerRect.minY, width: scaledWidth, height: canvasSize)
                } else {
                    let scaledHeight = canvasSize / drawableRatio
                    let offsetY = (canvasSize - scaledHeight) / 2.0
                    drawRect = CGRect(x: markerRect.minX, y: markerRect.minY + offsetY, width: canvasSize, height: scaledHeight)
                }
                backgroundImage.draw(in: drawRect)
            } else {
                backgroundImage.draw(in: markerRect)
            }

            context.cgContext.restoreGState()

            context.cgContext.setStrokeColor(strokeColor.cgColor)
            context.cgContext.setLineWidth(strokeWidth * scale)
            context.cgContext.setLineJoin(.round)
            context.cgContext.setLineCap(.round)
            context.cgContext.addPath(path.cgPath)
            context.cgContext.strokePath()

            if let label, labelSize != .zero {
                DefaultMarkerIcon.drawLabel(
                    context: context.cgContext,
                    labelText: label,
                    labelFont: resolvedFont,
                    labelTextColor: labelTextColor ?? defaultLabelTextColor,
                    labelStrokeColor: labelStrokeColor,
                    canvasSize: canvasSize,
                    offsetX: markerOffsetX,
                    outlineStrokeWidth: outlineStrokeWidth,
                    pixelScale: format.scale
                )
            }
        }

        return BitmapIcon(
            bitmap: image,
            anchor: anchor,
            size: CGSize(width: bitmapWidth, height: bitmapHeight),
            scale: scale,
            iconSize: iconSize,
            infoAnchor: infoAnchor,
            debug: debug
        )
    }
}
