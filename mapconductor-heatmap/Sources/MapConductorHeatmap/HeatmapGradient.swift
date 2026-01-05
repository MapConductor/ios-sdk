import UIKit

public struct HeatmapGradientStop: Hashable {
    public let position: Double
    public let color: UInt32

    public init(position: Double, color: UInt32) {
        self.position = position
        self.color = color
    }
}

public final class HeatmapGradient: Hashable {
    public let stops: [HeatmapGradientStop]

    public init(stops: [HeatmapGradientStop]) {
        let sorted = stops.sorted { $0.position < $1.position }
        precondition(!sorted.isEmpty, "HeatmapGradient requires at least one stop.")
        for stop in sorted {
            precondition((0.0...1.0).contains(stop.position), "HeatmapGradient stop position must be in [0, 1].")
        }
        self.stops = sorted
    }

    public func colors() -> [UInt32] {
        stops.map { $0.color }
    }

    public func startPoints() -> [Float] {
        stops.map { Float($0.position) }
    }

    public func colorAt(position: Double) -> UInt32 {
        let clamped = max(0.0, min(1.0, position))
        if stops.count == 1 {
            return stops[0].color
        }
        let lower = stops.last { $0.position <= clamped } ?? stops[0]
        let upper = stops.first { $0.position >= clamped } ?? stops[stops.count - 1]
        if lower.position == upper.position {
            return lower.color
        }
        let ratio = (clamped - lower.position) / (upper.position - lower.position)
        return HeatmapColor.lerpColor(start: lower.color, end: upper.color, ratio: ratio)
    }

    public static func == (lhs: HeatmapGradient, rhs: HeatmapGradient) -> Bool {
        lhs.stops == rhs.stops
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(stops)
    }

    public static let `default` = HeatmapGradient(
        stops: [
            HeatmapGradientStop(position: 0.2, color: HeatmapColor.rgb(102, 225, 0)),
            HeatmapGradientStop(position: 1.0, color: HeatmapColor.rgb(255, 0, 0))
        ]
    )
}

public enum HeatmapDefaults {
    public static let defaultRadiusPx: Int = 20
    public static let defaultOpacity: Double = 0.7
}

enum HeatmapColor {
    static func argb(_ a: Int, _ r: Int, _ g: Int, _ b: Int) -> UInt32 {
        let ai = UInt32(max(0, min(255, a)))
        let ri = UInt32(max(0, min(255, r)))
        let gi = UInt32(max(0, min(255, g)))
        let bi = UInt32(max(0, min(255, b)))
        return (ai << 24) | (ri << 16) | (gi << 8) | bi
    }

    static func rgb(_ r: Int, _ g: Int, _ b: Int) -> UInt32 {
        argb(255, r, g, b)
    }

    static func alpha(_ color: UInt32) -> Int {
        Int((color >> 24) & 0xFF)
    }

    static func red(_ color: UInt32) -> Int {
        Int((color >> 16) & 0xFF)
    }

    static func green(_ color: UInt32) -> Int {
        Int((color >> 8) & 0xFF)
    }

    static func blue(_ color: UInt32) -> Int {
        Int(color & 0xFF)
    }

    static func lerpColor(start: UInt32, end: UInt32, ratio: Double) -> UInt32 {
        let clamped = max(0.0, min(1.0, ratio))
        let a = Int(Double(alpha(start)) + (Double(alpha(end)) - Double(alpha(start))) * clamped)
        let r = Int(Double(red(start)) + (Double(red(end)) - Double(red(start))) * clamped)
        let g = Int(Double(green(start)) + (Double(green(end)) - Double(green(start))) * clamped)
        let b = Int(Double(blue(start)) + (Double(blue(end)) - Double(blue(start))) * clamped)
        return argb(a, r, g, b)
    }

    static func hsvComponents(_ color: UInt32) -> (h: Double, s: Double, v: Double) {
        let r = CGFloat(red(color)) / 255.0
        let g = CGFloat(green(color)) / 255.0
        let b = CGFloat(blue(color)) / 255.0
        let uiColor = UIColor(red: r, green: g, blue: b, alpha: 1.0)
        var h: CGFloat = 0
        var s: CGFloat = 0
        var v: CGFloat = 0
        uiColor.getHue(&h, saturation: &s, brightness: &v, alpha: nil)
        return (Double(h * 360.0), Double(s), Double(v))
    }

    static func colorFromHSV(alpha: Int, h: Double, s: Double, v: Double) -> UInt32 {
        let hue = CGFloat(h / 360.0)
        let saturation = CGFloat(s)
        let brightness = CGFloat(v)
        let alphaValue = CGFloat(max(0, min(255, alpha))) / 255.0
        let uiColor = UIColor(hue: hue, saturation: saturation, brightness: brightness, alpha: alphaValue)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        return argb(Int(a * 255.0), Int(r * 255.0), Int(g * 255.0), Int(b * 255.0))
    }
}
