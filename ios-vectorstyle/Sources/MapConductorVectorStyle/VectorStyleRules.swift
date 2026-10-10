import CMvtStyle
import Foundation
import MapConductorCore

/**
 Declarative adjustments to a MapLibre style.

 A map in this SDK is drawn one of two ways: by a renderer that takes a
 vector style directly (MapLibre, Mapbox, MapTiler), or by rasterising the
 style to PNG tiles on the device and handing those to a backend that cannot
 read a style at all (Google Maps, MapKit, HERE, ArcGIS...). Both start from
 the same `style.json`, so adjusting the style belongs *before* that fork
 rather than on either side of it.

 ``compile(styleJSON:rulesJSON:)`` is that step. From one pass over one style
 it produces both the adjusted document -- for a renderer to read, or for the
 rasteriser to draw -- and the per-layer deltas a live renderer can be told
 about without reloading anything. The two cannot disagree, because they come
 from the same evaluation.

 ```swift
 let compiled = try VectorStyleRules.compile(styleJSON: style, rulesJSON: rules)
 compiled.diagnostics.forEach { print($0) }   // what matched, and what did not
 ```

 The rules themselves are JSON. That is the definition rather than a
 serialisation of something else: a rule set can be written by hand, stored,
 shipped from a server or diffed, and it is exactly what the compiler reads
 on all three platforms.
 */
public enum VectorStyleRules {
    /**
     The rules document version this build understands.

     A document claiming another version is refused rather than partly
     applied -- a rule that silently does nothing is the failure this whole
     design exists to avoid.
     */
    public static var schemaVersion: Int {
        Int(mvt_style_schema_version())
    }

    /**
     Applies `rulesJSON` to `styleJSON`.

     - Throws: ``VectorStyleError`` when either document cannot be read: a
       style that is not JSON, a rules document from a newer build, a
       selector this version does not know.
     */
    public static func compile(styleJSON: String, rulesJSON: String) throws -> CompiledStyle {
        let answer = try call { style in
            try rulesJSON.withCString { rules in
                try take(mvt_style_compile(style, rules))
            }
        }(styleJSON)

        guard let root = try JSONSerialization.jsonObject(with: Data(answer.utf8)) as? [String: Any]
        else { throw VectorStyleError.unreadable("the compiler answered with nothing") }
        if let message = root["error"] as? String { throw VectorStyleError.unreadable(message) }
        guard
            let style = root["style"],
            let styleData = try? JSONSerialization.data(withJSONObject: style),
            let styleText = String(data: styleData, encoding: .utf8)
        else { throw VectorStyleError.unreadable("the adjusted style could not be written") }

        let mutations = root["mutations"] ?? []
        let mutationsText =
            (try? JSONSerialization.data(withJSONObject: mutations))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"

        return CompiledStyle(
            styleJSON: styleText,
            mutations: StyleMutation.parseList(mutationsText),
            affects: StyleAffects(name: root["affects"] as? String),
            patchable: root["patchable"] as? Bool ?? true,
            diagnostics: root["diagnostics"] as? [String] ?? []
        )
    }

    /**
     Every layer in the style, with the role this would give it.

     Rules are written against someone else's style, so being able to ask
     what is in it -- and on what evidence a layer counts as a road -- is not
     a debugging aid, it is how the rules get written in the first place.
     */
    public static func describe(styleJSON: String) throws -> [StyleLayerInfo] {
        let answer = try styleJSON.withCString { style in
            try take(mvt_style_describe(style))
        }
        let parsed = try JSONSerialization.jsonObject(with: Data(answer.utf8))
        if let failure = parsed as? [String: Any] {
            throw VectorStyleError.unreadable(
                failure["error"] as? String ?? "the style could not be read")
        }
        guard let listed = parsed as? [[String: Any]] else {
            throw VectorStyleError.unreadable("the compiler answered with nothing")
        }
        return listed.map { entry in
            StyleLayerInfo(
                id: entry["id"] as? String ?? "",
                kind: entry["kind"] as? String ?? "",
                sourceLayer: entry["sourceLayer"] as? String,
                roles: entry["roles"] as? [String] ?? [],
                evidence: entry["evidence"] as? [String] ?? []
            )
        }
    }

    /// Reads a string the compiler returned and releases it.
    private static func take(_ raw: UnsafeMutablePointer<CChar>?) throws -> String {
        guard let raw else {
            // Null means an argument was not valid UTF-8 or the compiler
            // panicked. Everything else arrives inside the JSON.
            throw VectorStyleError.unreadable("the style compiler could not be called")
        }
        defer { mvt_style_string_free(raw) }
        return String(cString: raw)
    }

    /// `withCString` on the outer argument, so both strings stay alive for the call.
    private static func call(
        _ body: @escaping (UnsafePointer<CChar>) throws -> String
    ) -> (String) throws -> String {
        { text in try text.withCString(body) }
    }
}

/// What came out of ``VectorStyleRules/compile(styleJSON:rulesJSON:)``.
public struct CompiledStyle: Sendable {
    /// The adjusted document, to hand to a renderer or to rasterise.
    public let styleJSON: String
    /**
     The per-layer deltas, for a map that can change a loaded style in place
     rather than reading the document again.
     */
    public let mutations: [StyleMutation]
    /**
     Which half of a split raster layer has to be redrawn. A rule that only
     recolours text need not invalidate every tile on screen.
     */
    public let affects: StyleAffects
    /**
     False when the mutations alone cannot reproduce the document -- a rule
     added a layer -- so a live map has to be given the document instead of
     being patched.
     */
    public let patchable: Bool
    /**
     What the app should know: how many layers each rule matched, a rule that
     matched none, a change the rasteriser will not draw, an expression it
     cannot evaluate.

     Worth surfacing rather than keeping internal. A rule written against the
     wrong tile schema produces a perfectly good map with nothing changed on
     it, and nothing else says so.
     */
    public let diagnostics: [String]
}

/// Which half of a split raster layer a change reaches.
public enum StyleAffects: String, Sendable {
    case none
    case ground
    case labels
    case both

    init(name: String?) {
        self = name.flatMap(StyleAffects.init(rawValue:)) ?? .none
    }
}

/// One layer of a style, and the role the compiler would give it.
public struct StyleLayerInfo: Sendable, Equatable {
    public let id: String
    /// The layer's `type`: `background`, `fill`, `line`, `circle`, `symbol`, or another.
    public let kind: String
    public let sourceLayer: String?
    /// Most specific last: a road casing is both `road` and `road-casing`.
    public let roles: [String]
    /**
     How each role was decided, in the same order as `roles`:
     `shortbread:streets` from the schema's table, `id~*-casing` from the
     layer's name, `kind:symbol` from its type.

     The id heuristics are the part most likely to be wrong on a style nobody
     has tried yet, so what they decided is said out loud.
     */
    public let evidence: [String]
}

/// A style or a rules document that could not be read.
public enum VectorStyleError: Error, Equatable {
    case unreadable(String)

    public var message: String {
        switch self {
        case let .unreadable(message): return message
        }
    }
}
