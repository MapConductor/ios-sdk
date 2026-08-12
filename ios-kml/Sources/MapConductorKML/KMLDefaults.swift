import UIKit

public enum KMLDefaults {
    public static let defaultTileSize: Int = 512
    public static let defaultMaxZoom: Int = 22
    public static let defaultOpacity: Double = 1.0
    public static let defaultStrokeColor: UIColor = UIColor(red: 30/255, green: 136/255, blue: 229/255, alpha: 1.0)
    public static let defaultFillColor: UIColor = UIColor(red: 30/255, green: 136/255, blue: 229/255, alpha: 0.5)
    public static let defaultStrokeWidth: CGFloat = 2.0
    public static let defaultPointRadius: CGFloat = 8.0

    // World-coordinate hit tolerances (~0.0002 ≈ 72m at equator, ~3-5px at zoom 14)
    static let hitLineTolerance: Double = 0.0002
    static let hitLineSq: Double = hitLineTolerance * hitLineTolerance
    static let hitPointTolerance: Double = 0.0004
    static let hitPointSq: Double = hitPointTolerance * hitPointTolerance
}
