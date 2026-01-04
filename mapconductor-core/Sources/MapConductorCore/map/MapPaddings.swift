import Foundation

public protocol MapPaddingsProtocol {
    var top: Double { get }
    var left: Double { get }
    var bottom: Double { get }
    var right: Double { get }
}

open class MapPaddings: MapPaddingsProtocol {
    public let top: Double
    public let left: Double
    public let bottom: Double
    public let right: Double

    public init(
        top: Double = 0.0,
        left: Double = 0.0,
        bottom: Double = 0.0,
        right: Double = 0.0
    ) {
        self.top = top
        self.left = left
        self.bottom = bottom
        self.right = right
    }

    public static let Zeros = MapPaddings()

    public static func from(paddings: MapPaddingsProtocol) -> MapPaddings {
        if let impl = paddings as? MapPaddings {
            return impl
        }
        return MapPaddings(
            top: paddings.top,
            left: paddings.left,
            bottom: paddings.bottom,
            right: paddings.right
        )
    }

    public func hashCode() -> Int {
        var result = top.hashValue
        result = 31 * result + left.hashValue
        result = 31 * result + bottom.hashValue
        result = 31 * result + right.hashValue
        return result
    }
}
