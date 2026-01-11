import CoreText
import UIKit

public final class DefaultMarkerIcon: MarkerIconProtocol {
    public static let defaultIconSize: CGFloat = 48.0
    public static let defaultStrokeWidth: CGFloat = 1.0
    public static let defaultFillColor: UIColor = .red
    public static let defaultStrokeColor: UIColor = .white
    public static let defaultLabelTextSize: CGFloat = 18.0
    public static let defaultLabelTextColor: UIColor = .black
    public static let defaultLabelStrokeColor: UIColor = .white
    public static let defaultLabelTypeFace: UIFont = .systemFont(ofSize: 18.0)
    public static let defaultInfoAnchor = CGPoint(x: 0.5, y: 0.0)

    private static let defaultAnchor = CGPoint(x: 0.5, y: 1.0)

    public let scale: CGFloat
    public let anchor: CGPoint
    public let iconSize: CGFloat
    public let infoAnchor: CGPoint
    public let debug: Bool

    private let fillColor: UIColor
    private let strokeColor: UIColor
    private let strokeWidth: CGFloat
    private let label: String?
    private let labelTextColor: UIColor?
    private let labelTextSize: CGFloat
    private let labelTypeFace: UIFont
    private let labelStrokeColor: UIColor
    private let bitmapIcon: BitmapIcon

    public init(
        fillColor: UIColor = defaultFillColor,
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
        self.fillColor = fillColor
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
        self.anchor = DefaultMarkerIcon.defaultAnchor
        self.bitmapIcon = DefaultMarkerIcon.makeIcon(
            iconSize: iconSize,
            scale: scale,
            fillColor: fillColor,
            strokeColor: strokeColor,
            strokeWidth: strokeWidth,
            label: label,
            labelTextColor: labelTextColor,
            labelTextSize: labelTextSize,
            labelTypeFace: labelTypeFace,
            labelStrokeColor: labelStrokeColor,
            anchor: DefaultMarkerIcon.defaultAnchor,
            infoAnchor: infoAnchor,
            debug: debug
        )
    }

    public func toBitmapIcon() -> BitmapIcon {
        bitmapIcon
    }

    public func copy(
        fillColor: UIColor? = nil,
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
    ) -> DefaultMarkerIcon {
        DefaultMarkerIcon(
            fillColor: fillColor ?? self.fillColor,
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
        iconSize: CGFloat,
        scale: CGFloat,
        fillColor: UIColor,
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
            labelSize = measureLabel(label, font: resolvedFont, strokeWidth: outlineStrokeWidth)
        }

        let padding = canvasSize * 0.1
        let bitmapWidth = max(canvasSize, labelSize.width + padding)
        let bitmapHeight = canvasSize
        let markerOffsetX = (bitmapWidth - canvasSize) / 2.0

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = UIScreen.main.scale
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: bitmapWidth, height: bitmapHeight), format: format)
        let image = renderer.image { context in
            if debug {
                context.cgContext.setStrokeColor(UIColor.black.cgColor)
                context.cgContext.setLineWidth(1.0)
                context.cgContext.stroke(CGRect(x: 0, y: 0, width: bitmapWidth, height: bitmapHeight))
            }

            let path = createMarkerPath(
                canvasSize: canvasSize,
                iconScale: scale,
                strokeWidth: strokeWidth,
                horizontalOffset: markerOffsetX
            )

            context.cgContext.setFillColor(fillColor.cgColor)
            context.cgContext.addPath(path.cgPath)
            context.cgContext.fillPath()

            context.cgContext.setStrokeColor(strokeColor.cgColor)
            context.cgContext.setLineWidth(strokeWidth * scale)
            context.cgContext.setLineJoin(.round)
            context.cgContext.setLineCap(.round)
            context.cgContext.addPath(path.cgPath)
            context.cgContext.strokePath()

            if let label, labelSize != .zero {
                drawLabel(
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
            infoAnchor: infoAnchor
        )
    }

    internal static func measureLabel(_ label: String, font: UIFont, strokeWidth: CGFloat) -> CGSize {
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: label, attributes: attributes))
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
        let height = ascent + descent
        let padding = strokeWidth * 2.0
        return CGSize(width: width + padding, height: height + padding)
    }

    internal static func drawLabel(
        context: CGContext,
        labelText: String,
        labelFont: UIFont,
        labelTextColor: UIColor,
        labelStrokeColor: UIColor,
        canvasSize: CGFloat,
        offsetX: CGFloat,
        outlineStrokeWidth: CGFloat,
        pixelScale: CGFloat
    ) {
        let markerCenterX = canvasSize / 2.0 + offsetX
        let markerCenterY = canvasSize * 0.35

        let baseAttributes: [NSAttributedString.Key: Any] = [.font: labelFont]
        let baseLine = CTLineCreateWithAttributedString(NSAttributedString(string: labelText, attributes: baseAttributes))
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let lineWidth = CGFloat(CTLineGetTypographicBounds(baseLine, &ascent, &descent, &leading))
        let baselineY = markerCenterY + (ascent - descent) / 2.0

        let drawX = alignToPixel(markerCenterX - lineWidth / 2.0, scale: pixelScale)
        let drawBaselineY = alignToPixel(baselineY, scale: pixelScale)
        let strokePercent = (outlineStrokeWidth / max(labelFont.pointSize, 1.0)) * 100.0

        context.saveGState()
        context.textMatrix = .identity
        context.setLineJoin(.round)
        context.setLineCap(.round)
        context.setShouldAntialias(true)
        context.setAllowsFontSmoothing(true)
        context.setShouldSmoothFonts(true)
        context.setAllowsFontSubpixelPositioning(false)
        context.setShouldSubpixelPositionFonts(false)

        context.translateBy(x: 0, y: canvasSize)
        context.scaleBy(x: 1.0, y: -1.0)

        let flippedBaselineY = canvasSize - drawBaselineY
        context.textPosition = CGPoint(x: drawX, y: flippedBaselineY)

        let strokeAttributes: [NSAttributedString.Key: Any] = [
            .font: labelFont,
            .strokeColor: labelStrokeColor,
            .strokeWidth: strokePercent,
            .foregroundColor: labelStrokeColor
        ]
        let fillAttributes: [NSAttributedString.Key: Any] = [
            .font: labelFont,
            .foregroundColor: labelTextColor
        ]

        let strokeLine = CTLineCreateWithAttributedString(
            NSAttributedString(string: labelText, attributes: strokeAttributes)
        )
        CTLineDraw(strokeLine, context)

        context.textPosition = CGPoint(x: drawX, y: flippedBaselineY)
        let fillLine = CTLineCreateWithAttributedString(
            NSAttributedString(string: labelText, attributes: fillAttributes)
        )
        CTLineDraw(fillLine, context)

        context.restoreGState()
    }

    internal static func alignToPixel(_ value: CGFloat, scale: CGFloat) -> CGFloat {
        guard scale > 0 else { return value }
        return (value * scale).rounded() / scale
    }

    static func createMarkerPath(
        canvasSize: CGFloat,
        iconScale: CGFloat,
        strokeWidth: CGFloat,
        horizontalOffset: CGFloat = 0.0
    ) -> UIBezierPath {
        let originalSize = CGSize(width: 23.5, height: 25.6)

        let scaledStrokeWidth = strokeWidth * iconScale
        let epsilon: CGFloat = 0.75
        let padding = max((scaledStrokeWidth / 2.0) - epsilon, 0.0)
        let availableWidth = canvasSize - (padding * 2.0)
        let availableHeight = canvasSize - padding

        let markerScale = min(
            availableWidth / originalSize.width,
            availableHeight / originalSize.height
        )

        let scaledWidth = originalSize.width * markerScale
        let scaledHeight = originalSize.height * markerScale
        let offsetX = (canvasSize - scaledWidth) / 2.0 + horizontalOffset
        let offsetY = (canvasSize - scaledHeight + (strokeWidth * markerScale)) / 2.0

        let path = UIBezierPath()
        var current = CGPoint(
            x: 12.0 * markerScale + offsetX,
            y: 0.0 * markerScale + offsetY
        )
        path.move(to: current)

        func rCubicTo(_ dx1: CGFloat, _ dy1: CGFloat, _ dx2: CGFloat, _ dy2: CGFloat, _ dx: CGFloat, _ dy: CGFloat) {
            let control1 = CGPoint(x: current.x + dx1, y: current.y + dy1)
            let control2 = CGPoint(x: current.x + dx2, y: current.y + dy2)
            let end = CGPoint(x: current.x + dx, y: current.y + dy)
            path.addCurve(to: end, controlPoint1: control1, controlPoint2: control2)
            current = end
        }

        func rLineTo(_ dx: CGFloat, _ dy: CGFloat) {
            let end = CGPoint(x: current.x + dx, y: current.y + dy)
            path.addLine(to: end)
            current = end
        }

        rCubicTo(
            -4.4183 * markerScale,
            2.3685e-15 * markerScale,
            -8.0 * markerScale,
            3.5817 * markerScale,
            -8.0 * markerScale,
            8.0 * markerScale
        )

        rCubicTo(
            0.0 * markerScale,
            1.421 * markerScale,
            0.3816 * markerScale,
            2.75 * markerScale,
            1.0312 * markerScale,
            3.906 * markerScale
        )

        rCubicTo(
            0.1079 * markerScale,
            0.192 * markerScale,
            0.221 * markerScale,
            0.381 * markerScale,
            0.3438 * markerScale,
            0.563 * markerScale
        )

        rLineTo(6.625 * markerScale, 11.531 * markerScale)
        rLineTo(6.625 * markerScale, -11.531 * markerScale)

        rCubicTo(
            0.102 * markerScale,
            -0.151 * markerScale,
            0.19 * markerScale,
            -0.311 * markerScale,
            0.281 * markerScale,
            -0.469 * markerScale
        )

        rLineTo(0.063 * markerScale, -0.094 * markerScale)

        rCubicTo(
            0.649 * markerScale,
            -1.156 * markerScale,
            1.031 * markerScale,
            -2.485 * markerScale,
            1.031 * markerScale,
            -3.906 * markerScale
        )

        rCubicTo(
            0.0 * markerScale,
            -4.4183 * markerScale,
            -3.582 * markerScale,
            -8.0 * markerScale,
            -8.0 * markerScale,
            -8.0 * markerScale
        )

        path.close()
        return path
    }
}
