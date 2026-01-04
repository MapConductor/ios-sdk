public enum TileScheme: String, Hashable {
    case XYZ
    case TMS
}

public enum RasterSource: Hashable {
    case urlTemplate(
        template: String,
        tileSize: Int = RasterSource.defaultTileSize,
        minZoom: Int? = nil,
        maxZoom: Int? = nil,
        attribution: String? = nil,
        scheme: TileScheme = .XYZ
    )
    case tileJson(url: String)
    case arcGisService(serviceUrl: String)

    public static let defaultTileSize: Int = 256
}
