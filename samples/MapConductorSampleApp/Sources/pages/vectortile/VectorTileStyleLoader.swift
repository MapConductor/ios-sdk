import Foundation

/**
 Fetches a Shortbread-schema style and repoints it at the OSMF tile service.

 The style and the tiles come from different hosts on purpose: Shortbread is an
 open schema, so any style written against it works with any server that serves
 it. Neither needs an API key.
 */
enum VectorTileStyleLoader {
    private static let styleURL = URL(
        string: "https://tiles.versatiles.org/assets/styles/colorful/style.json"
    )!
    private static let osmTiles =
        "https://vector.openstreetmap.org/shortbread_v1/{z}/{x}/{y}.mvt"

    /**
     What the tiles this points at are owed.

     Kept here rather than taken on trust from the upstream style: the sources
     are being repointed at the OSMF service, so the credit that matters is the
     one *those* tiles require, whatever the original style happened to say.
     The style's own wording is preferred when it has one — it is the same
     licence, in the publisher's own phrasing.
     */
    private static let osmAttribution =
        "&copy; <a href=\"https://www.openstreetmap.org/copyright\">OpenStreetMap</a> contributors"

    static func load() async throws -> String {
        let (data, response) = try await URLSession.shared.data(from: styleURL)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw VectorTileStyleError.fetchFailed
        }
        guard var style = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sources = style["sources"] as? [String: Any]
        else { throw VectorTileStyleError.notAStyle }

        var repointed: [String: Any] = [:]
        for (id, value) in sources {
            // Carried across rather than dropped. Rewriting a source is not a
            // reason to stop crediting the data.
            let attribution = (value as? [String: Any])?["attribution"] as? String
            repointed[id] = [
                "type": "vector",
                "tiles": [osmTiles],
                "minzoom": 0,
                "maxzoom": 14,
                "attribution": attribution?.isEmpty == false ? attribution! : osmAttribution,
            ]
        }
        style["sources"] = repointed

        let encoded = try JSONSerialization.data(withJSONObject: style)
        guard let text = String(data: encoded, encoding: .utf8) else {
            throw VectorTileStyleError.notAStyle
        }
        return text
    }
}

enum VectorTileStyleError: Error {
    case fetchFailed
    case notAStyle
}
