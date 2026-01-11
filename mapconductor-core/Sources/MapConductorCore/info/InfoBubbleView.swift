import CoreGraphics
import SwiftUI

public struct InfoBubbleStyle {
    public let bubbleColor: Color
    public let borderColor: Color
    public let contentPadding: CGFloat
    public let cornerRadius: CGFloat
    public let tailSize: CGFloat

    public init(
        bubbleColor: Color = .white,
        borderColor: Color = .black,
        contentPadding: CGFloat = 8.0,
        cornerRadius: CGFloat = 4.0,
        tailSize: CGFloat = 8.0
    ) {
        self.bubbleColor = bubbleColor
        self.borderColor = borderColor
        self.contentPadding = contentPadding
        self.cornerRadius = cornerRadius
        self.tailSize = tailSize
    }

    public static let Default = InfoBubbleStyle()
}

public struct DefaultInfoBubbleView: View {
    private let style: InfoBubbleStyle
    private let content: AnyView

    public init(style: InfoBubbleStyle, content: AnyView) {
        self.style = style
        self.content = content
    }

    public var body: some View {
        ZStack {
            InfoBubbleShape(
                cornerRadius: style.cornerRadius,
                tailSize: style.tailSize
            )
            .fill(style.bubbleColor)
            .overlay(
                InfoBubbleShape(
                    cornerRadius: style.cornerRadius,
                    tailSize: style.tailSize
                )
                .stroke(style.borderColor, lineWidth: 2.0)
            )

            content
                .padding(.init(
                    top: style.contentPadding,
                    leading: style.contentPadding,
                    bottom: style.contentPadding + style.tailSize,
                    trailing: style.contentPadding
                ))
                .clipShape(RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous))
        }
        .fixedSize()
    }
}

private struct InfoBubbleShape: Shape {
    let cornerRadius: CGFloat
    let tailSize: CGFloat

    func path(in rect: CGRect) -> Path {
        let width = rect.width
        let height = rect.height
        let corner = cornerRadius
        let tail = tailSize

        var path = Path()
        path.move(to: CGPoint(x: 2 * corner, y: 0))
        path.addLine(to: CGPoint(x: width - 2 * corner, y: 0))
        path.addArc(
            center: CGPoint(x: width - corner, y: corner),
            radius: corner,
            startAngle: .degrees(-90),
            endAngle: .degrees(0),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: width, y: height - tail - 2 * corner))
        path.addArc(
            center: CGPoint(x: width - corner, y: height - tail - corner),
            radius: corner,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: width / 2 + tail / 2, y: height - tail))
        path.addLine(to: CGPoint(x: width / 2, y: height))
        path.addLine(to: CGPoint(x: width / 2 - tail / 2, y: height - tail))
        path.addLine(to: CGPoint(x: 2 * corner, y: height - tail))
        path.addArc(
            center: CGPoint(x: corner, y: height - tail - corner),
            radius: corner,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: 0, y: 2 * corner))
        path.addArc(
            center: CGPoint(x: corner, y: corner),
            radius: corner,
            startAngle: .degrees(180),
            endAngle: .degrees(270),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}
