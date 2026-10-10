import Foundation

#if canImport(UIKit)
    import UIKit
#endif

/**
 What to change about a style, and where.

 ```swift
 let rules = StyleRules.build {
     $0.all { $0.color = .black }
     $0.role(LayerRole.label) { $0.visible = false }
     $0.role(LayerRole.roadCasing) { $0.color = UIColor(white: 0.19, alpha: 1) }
     $0.role(LayerRole.road) { $0.color = .white; $0.widthScale = 1.3 }
 }
 ```

 Rules apply in order and override each other property by property, the way
 CSS does: the last rule to name a colour wins, and a rule that says nothing
 about width leaves the width alone. Reordering the two road rules above
 gives a different map, which is the point -- only the app knows whether the
 casings should keep their own colour.

 ## It is JSON underneath, on purpose

 ``json`` is the real definition, not a serialisation of the builder. The
 same text is what the compiler reads on Android, iOS and the web, so a rule
 set can be written by hand, stored, shipped from a server, or diffed between
 two versions of an app -- and ``parse(_:)`` takes it straight back. The
 builder is sugar over that, there so the common case is checked by the
 compiler rather than by a typo.

 Nothing is validated here. A rule set is checked when it is compiled against
 a style, which is the only place that can tell whether `role("road")` means
 anything.
 */
public struct StyleRules: Equatable, Sendable {
    /// The canonical form.
    public let json: String

    private init(json: String) {
        self.json = json
    }

    /// No adjustments: the style as its author wrote it.
    public static let none = StyleRules(json: #"{"schemaVersion":1,"rules":[]}"#)

    /**
     Takes a rules document as it stands.

     Not checked here -- a document is checked when it is compiled against a
     style, and ``VectorStyleRules/compile(styleJSON:rulesJSON:)`` throws then.
     */
    public static func parse(_ json: String) -> StyleRules { StyleRules(json: json) }

    /// Writes a rules document with the compiler checking the shape.
    public static func build(_ block: (StyleRulesBuilder) -> Void) -> StyleRules {
        let builder = StyleRulesBuilder()
        block(builder)
        return StyleRules(json: builder.toJSON())
    }
}

/**
 The roles the built-in schema profiles assign.

 Strings rather than an enum: a style cut to a schema nobody here has heard
 of can name its own roles through ``StyleRulesBuilder/customSchema(_:)``,
 and adding a role to the built-in tables must not be a breaking change on
 three platforms.
 */
public enum LayerRole {
    public static let background = "background"
    public static let water = "water"
    public static let waterway = "waterway"
    public static let land = "land"
    public static let landuse = "landuse"
    public static let park = "park"
    public static let building = "building"
    public static let road = "road"
    /**
     The wide dark line drawn under a road to give it an edge.

     A style draws every road twice, and "make roads white" applied to both
     halves gives a white slab rather than a road. Nothing in the tile
     distinguishes them -- only the layer's name does -- so this is the one
     role decided by a naming convention, and the compiler reports how many
     layers it found.
     */
    public static let roadCasing = "road-casing"
    public static let rail = "rail"
    public static let transit = "transit"
    public static let boundary = "boundary"
    public static let aeroway = "aeroway"
    public static let label = "label"
    public static let poi = "poi"
}

/// A style layer's `type`, for ``StyleSelector/kind(_:)``.
public enum StyleLayerKind: String, Sendable {
    case background
    case fill
    case line
    case circle
    case symbol
    /// Everything else: raster, hillshade, heatmap, fill-extrusion, sky.
    case other
}

/// Which layers a rule reaches.
public indirect enum StyleSelector: Sendable {
    /// Every layer in the style, including the background.
    case all
    /// What the layer *is*, across schemas that name their sources differently.
    case role(String)
    /// The layer's `id`, as a glob: `*` for any run, `?` for one character.
    case layerId(String)
    case sourceLayer(String)
    case kind(StyleLayerKind)
    case anyOf([StyleSelector])
    case allOf([StyleSelector])
    case not(StyleSelector)

    var json: String {
        switch self {
        case .all: return "\"all\""
        case let .role(name): return #"{"role":\#(quoteJSON(name))}"#
        case let .layerId(glob): return #"{"layerId":\#(quoteJSON(glob))}"#
        case let .sourceLayer(name): return #"{"sourceLayer":\#(quoteJSON(name))}"#
        case let .kind(kind): return #"{"kind":\#(quoteJSON(kind.rawValue))}"#
        case let .anyOf(of):
            return #"{"anyOf":[\#(of.map(\.json).joined(separator: ","))]}"#
        case let .allOf(of):
            return #"{"allOf":[\#(of.map(\.json).joined(separator: ","))]}"#
        case let .not(of): return #"{"not":\#(of.json)}"#
        }
    }
}

/// Builds the `rules` array.
public final class StyleRulesBuilder {
    /**
     Which tile schema the style's `source-layer` names come from.

     Left alone it is worked out from the style, which is right for
     OpenMapTiles, Shortbread and Mapbox Streets. Name one to be sure, or
     supply ``customSchema(_:)`` for a schema the compiler has never seen.
     */
    public var schema: String?

    private var custom: [(String, [String])]?
    private var rules: [String] = []

    fileprivate init() {}

    /**
     Teaches the compiler a schema of your own: role name to the
     `source-layer` names that carry it.
     */
    public func customSchema(_ roles: [String: [String]]) {
        custom = roles.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    public func all(_ patch: (StylePatchBuilder) -> Void) { self.where(.all, patch) }

    public func role(_ role: String, _ patch: (StylePatchBuilder) -> Void) {
        self.where(.role(role), patch)
    }

    public func layerId(_ glob: String, _ patch: (StylePatchBuilder) -> Void) {
        self.where(.layerId(glob), patch)
    }

    public func sourceLayer(_ name: String, _ patch: (StylePatchBuilder) -> Void) {
        self.where(.sourceLayer(name), patch)
    }

    public func kind(_ kind: StyleLayerKind, _ patch: (StylePatchBuilder) -> Void) {
        self.where(.kind(kind), patch)
    }

    /// For a selector built by hand: ``StyleSelector/allOf(_:)``, ``StyleSelector/not(_:)`` and friends.
    public func `where`(_ selector: StyleSelector, _ patch: (StylePatchBuilder) -> Void) {
        let builder = StylePatchBuilder()
        patch(builder)
        rules.append(#"{"selector":\#(selector.json),"patch":\#(builder.toJSON())}"#)
    }

    func toJSON() -> String {
        var out = #"{"schemaVersion":1"#
        if let custom {
            let roles = custom.map { role, layers in
                #"\#(quoteJSON(role)):[\#(layers.map(quoteJSON).joined(separator: ","))]"#
            }
            out += #","schema":{"roles":{\#(roles.joined(separator: ","))}}"#
        } else if let schema {
            out += #","schema":\#(quoteJSON(schema))"#
        }
        out += #","rules":[\#(rules.joined(separator: ","))]}"#
        return out
    }
}

/// Builds one rule's `patch`.
public final class StylePatchBuilder {
    private var fields: [String] = []
    private var properties: [String] = []

    fileprivate init() {}

    /// `layout.visibility`.
    public var visible: Bool? {
        didSet { visible.map { fields.append(#""visible":\#($0)"#) } }
    }

    #if canImport(UIKit)
        /**
         The layer's colour, whichever property that is for its type:
         `fill-color` on a fill, `line-color` on a line, `text-color` and
         `icon-color` on a symbol, `background-color` on the background.
         */
        public var color: UIColor? {
            didSet { color.map { fields.append(#""color":\#(quoteJSON($0.styleText))"#) } }
        }
    #endif

    /// `*-opacity`, 0 to 1.
    public var opacity: Double? {
        didSet { opacity.map { fields.append(#""opacity":\#(trimmed($0))"#) } }
    }

    /**
     Multiplies how fat the layer is drawn: `line-width` on a line,
     `circle-radius` on a circle.

     A multiplier rather than a value because the width is almost always an
     expression over zoom, and replacing it with a number would throw that
     curve away.
     */
    public var widthScale: Double? {
        didSet { widthScale.map { fields.append(#""widthScale":\#(trimmed($0))"#) } }
    }

    public var minZoom: Double? {
        didSet { minZoom.map { fields.append(#""minZoom":\#(trimmed($0))"#) } }
    }

    public var maxZoom: Double? {
        didSet { maxZoom.map { fields.append(#""maxZoom":\#(trimmed($0))"#) } }
    }

    /// Drains the colour the style chose, 0 to 1.
    public func desaturate(_ amount: Double) {
        fields.append(#""colorFilter":{"desaturate":\#(trimmed(amount))}"#)
    }

    public func darken(_ amount: Double) {
        fields.append(#""colorFilter":{"darken":\#(trimmed(amount))}"#)
    }

    public func lighten(_ amount: Double) {
        fields.append(#""colorFilter":{"lighten":\#(trimmed(amount))}"#)
    }

    /**
     Flips how light each colour is and keeps its hue: the cheapest way to
     get a dark basemap out of a light one without naming a single colour.
     */
    public func invertLightness() {
        fields.append(#""colorFilter":{"invertLightness":true}"#)
    }

    #if canImport(UIKit)
        /// Blends what is there towards `target`.
        public func mix(_ target: UIColor, amount: Double = 0.5) {
            fields.append(
                #""colorFilter":{"mix":{"color":\#(quoteJSON(target.styleText)),"amount":\#(trimmed(amount))}}"#
            )
        }
    #endif

    /// Replaces the layer's filter, as a MapLibre filter expression in JSON.
    public func filter(_ json: String) {
        fields.append(#""filter":\#(json)"#)
    }

    /**
     Any style-spec property by name, as JSON. The last word: applied after
     everything above, including over a `color` in the same rule.

     The escape hatch for what the fields above do not name -- `text-field`,
     `fill-pattern`, `line-dasharray`, a `fill-extrusion` height. Note that a
     property the SDK's own rasteriser cannot draw will show only on a map
     that renders the style itself; the compiler says so in its diagnostics.
     */
    public func property(_ key: String, _ valueJSON: String) {
        properties.append(#"\#(quoteJSON(key)):\#(valueJSON)"#)
    }

    /// ``property(_:_:)`` for a plain text value, quoted for you.
    public func propertyText(_ key: String, _ value: String) {
        property(key, quoteJSON(value))
    }

    func toJSON() -> String {
        var all = fields
        if !properties.isEmpty {
            all.append(#""properties":{\#(properties.joined(separator: ","))}"#)
        }
        return "{\(all.joined(separator: ","))}"
    }
}

/// `1.3` rather than `1.3000000000000003`, and `2` rather than `2.0`.
private func trimmed(_ value: Double) -> String {
    if value == value.rounded() && abs(value) < 1e15 {
        return String(Int64(value))
    }
    var text = String(format: "%.3f", value)
    while text.hasSuffix("0") { text.removeLast() }
    if text.hasSuffix(".") { text.removeLast() }
    return text
}

#if canImport(UIKit)
    extension UIColor {
        /// `#rrggbb`, or `rgba(...)` when it is not fully opaque.
        var styleText: String {
            var r: CGFloat = 0
            var g: CGFloat = 0
            var b: CGFloat = 0
            var a: CGFloat = 0
            guard getRed(&r, green: &g, blue: &b, alpha: &a) else { return "#000000" }
            let to255 = { (v: CGFloat) in Int((v * 255).rounded()).clamped(to: 0...255) }
            if a >= 1 {
                return String(format: "#%02x%02x%02x", to255(r), to255(g), to255(b))
            }
            return "rgba(\(to255(r)),\(to255(g)),\(to255(b)),\(trimmed(Double(a))))"
        }
    }

    extension Int {
        fileprivate func clamped(to range: ClosedRange<Int>) -> Int {
            Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
        }
    }
#endif

/**
 A JSON string literal.

 Written here rather than through `JSONSerialization`, which refuses a bare
 string as a top-level value and would need a wrapper object unpicked again.
 */
func quoteJSON(_ text: String) -> String {
    var out = "\""
    for character in text.unicodeScalars {
        switch character {
        case "\"": out += "\\\""
        case "\\": out += "\\\\"
        case "\n": out += "\\n"
        case "\r": out += "\\r"
        case "\t": out += "\\t"
        default:
            if character.value < 0x20 {
                out += String(format: "\\u%04x", character.value)
            } else {
                out.unicodeScalars.append(character)
            }
        }
    }
    return out + "\""
}
