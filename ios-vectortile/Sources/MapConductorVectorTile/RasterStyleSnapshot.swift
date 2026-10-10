import Foundation
import MapConductorVectorStyle

/// Compare the documents actually displayed, rather than adjustments against
/// the author's base style. Recolouring roads must not invalidate unchanged
/// labels, and removing every adjustment still needs to restore both halves.
struct RasterStyleSnapshot {
    private let ground: Data
    private let labels: Data
    let hasVisibleSymbols: Bool

    init(styleJSON: String) throws {
        guard var root = try JSONSerialization.jsonObject(with: Data(styleJSON.utf8))
            as? [String: Any]
        else { throw VectorTileError.styleRejected("expected a style object") }
        let layers = root.removeValue(forKey: "layers") as? [[String: Any]] ?? []
        hasVisibleSymbols = layers.contains {
            ($0["type"] as? String) == "symbol"
                && (($0["layout"] as? [String: Any])?["visibility"] as? String) != "none"
        }
        var groundDocument = root
        var labelDocument = root
        groundDocument["layers"] = layers.filter { ($0["type"] as? String) != "symbol" }
        labelDocument["layers"] = layers.filter { ($0["type"] as? String) == "symbol" }
        ground = try JSONSerialization.data(withJSONObject: groundDocument, options: .sortedKeys)
        labels = try JSONSerialization.data(withJSONObject: labelDocument, options: .sortedKeys)
    }

    func changes(from previous: RasterStyleSnapshot) -> StyleAffects {
        switch (ground != previous.ground, labels != previous.labels) {
        case (false, false): return .none
        case (true, false): return .ground
        case (false, true): return .labels
        case (true, true): return .both
        }
    }
}
