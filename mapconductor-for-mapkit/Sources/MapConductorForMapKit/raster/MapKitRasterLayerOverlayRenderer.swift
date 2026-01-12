import MapKit
import MapConductorCore
@MainActor
final class MapKitRasterLayerOverlayRenderer: AbstractRasterLayerOverlayRenderer<MKTileOverlay> {
    private weak var mapView: MKMapView?
    private var renderersByLayerId: [String: MKTileOverlayRenderer] = [:]
    private var overlayStates: [MKTileOverlay: RasterLayerState] = [:]

    init(mapView: MKMapView?) {
        self.mapView = mapView
        super.init()
    }

    override func createLayer(state: RasterLayerState) async -> MKTileOverlay? {
        guard let mapView else { return nil }
        let overlay = makeTileOverlay(from: state.source)
        overlayStates[overlay] = state

        let renderer = MKTileOverlayRenderer(tileOverlay: overlay)
        renderer.alpha = CGFloat(state.opacity)
        renderersByLayerId[state.id] = renderer

        // Important: MapKit may request a renderer immediately as part of addOverlay().
        // Ensure we have the renderer registered before adding the overlay to the map.
        if state.visible {
            mapView.addOverlay(overlay, level: .aboveLabels)
        }

        return overlay
    }

    override func updateLayerProperties(
        layer: MKTileOverlay,
        current: RasterLayerEntity<MKTileOverlay>,
        prev: RasterLayerEntity<MKTileOverlay>
    ) async -> MKTileOverlay? {
        guard let mapView else { return layer }
        let finger = current.fingerPrint
        let prevFinger = prev.fingerPrint

        if finger.source != prevFinger.source {
            mapView.removeOverlay(layer)
            renderersByLayerId.removeValue(forKey: prev.state.id)
            overlayStates.removeValue(forKey: layer)
            return await createLayer(state: current.state)
        }

        if finger.opacity != prevFinger.opacity {
            if let renderer = renderersByLayerId[current.state.id] {
                renderer.alpha = CGFloat(current.state.opacity)
                renderer.setNeedsDisplay()
            }
        }

        if finger.visible != prevFinger.visible {
            if current.state.visible {
                if layer.isKind(of: MKTileOverlay.self) && !mapView.overlays.contains(where: { $0 === layer }) {
                    mapView.addOverlay(layer, level: .aboveLabels)
                }
            } else {
                mapView.removeOverlay(layer)
            }
        }

        overlayStates[layer] = current.state

        return layer
    }

    override func removeLayer(entity: RasterLayerEntity<MKTileOverlay>) async {
        guard let mapView, let layer = entity.layer else { return }
        mapView.removeOverlay(layer)
        renderersByLayerId.removeValue(forKey: entity.state.id)
        overlayStates.removeValue(forKey: layer)
    }

    func renderer(for overlay: MKOverlay) -> MKOverlayRenderer? {
        guard let tileOverlay = overlay as? MKTileOverlay,
              let state = overlayStates[tileOverlay],
              let renderer = renderersByLayerId[state.id] ?? {
                  // Fallback: if MapKit asked for the renderer before we registered it (or after eviction),
                  // create one on demand so the overlay can still render.
                  let created = MKTileOverlayRenderer(tileOverlay: tileOverlay)
                  created.alpha = CGFloat(state.opacity)
                  renderersByLayerId[state.id] = created
                  return created
              }() else {
            return nil
        }
        return renderer
    }

    func unbind() {
        renderersByLayerId.removeAll()
        overlayStates.removeAll()
        mapView = nil
    }

    private func makeTileOverlay(from source: RasterSource) -> MKTileOverlay {
        switch source {
        case let .urlTemplate(template, tileSize, minZoom, maxZoom, _, scheme):
            let overlay = CustomURLTileOverlay(
                urlTemplate: template,
                tileSize: tileSize,
                minZoom: minZoom,
                maxZoom: maxZoom,
                scheme: scheme
            )
            // MapKit can fail to render external raster tiles when used as a normal overlay.
            // Replacing map content yields reliable rendering.
            overlay.canReplaceMapContent = true
            return overlay
        case .tileJson:
            fatalError("RasterSource.tileJson is not implemented for MapKit yet.")
        case .arcGisService:
            fatalError("RasterSource.arcGisService is not implemented for MapKit yet.")
        }
    }
}

// Custom MKTileOverlay to support URL template pattern
private class CustomURLTileOverlay: MKTileOverlay {
    private let templateString: String
    private let minZoom: Int?
    private let maxZoom: Int?
    private let scheme: TileScheme
    private let session: URLSession

    init(urlTemplate: String, tileSize: Int, minZoom: Int?, maxZoom: Int?, scheme: TileScheme) {
        self.templateString = urlTemplate
        self.minZoom = minZoom
        self.maxZoom = maxZoom
        self.scheme = scheme
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .useProtocolCachePolicy
        config.httpMaximumConnectionsPerHost = 4
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
        super.init(urlTemplate: urlTemplate)
        self.tileSize = CGSize(width: max(1, tileSize), height: max(1, tileSize))

        // MKTileOverlay will not request tiles outside this range. If left unset, MapKit can end up
        // requesting only z=0 in some cases, making the layer appear blank at normal zooms.
        self.minimumZ = minZoom ?? 0
        self.maximumZ = maxZoom ?? 22
    }

    override var boundingMapRect: MKMapRect { MKMapRect.world }

    override func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, (any Error)?) -> Void) {
        let url = url(forTilePath: path)
        if url.scheme == "about" {
            result(nil, nil)
            return
        }

        var request = URLRequest(url: url)
        // Some public tile servers require a clear User-Agent.
        request.setValue("MapConductorSampleApp/1.0 (iOS; MKTileOverlay)", forHTTPHeaderField: "User-Agent")

        session.dataTask(with: request) { [tileSize] data, response, error in
            if let error {
                result(nil, error)
                return
            }
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                let err = NSError(
                    domain: "MapConductorForMapKit.MKTileOverlay",
                    code: http.statusCode,
                    userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode) for \(url.absoluteString)"]
                )
                result(nil, err)
                return
            }
            // Always return the original tile bytes. Most public raster tile servers (e.g. OSM)
            // provide 256px tiles; MapKit will scale as needed.
            result(data, nil)
        }.resume()
    }

    override func url(forTilePath path: MKTileOverlayPath) -> URL {
        // Check zoom level bounds
        if let minZoom, path.z < minZoom {
            return URL(string: "about:blank")!
        }
        if let maxZoom, path.z > maxZoom {
            return URL(string: "about:blank")!
        }

        let y: Int
        switch scheme {
        case .XYZ:
            y = path.y
        case .TMS:
            // Flip Y for TMS.
            let maxIndex = (1 << path.z) - 1
            y = maxIndex - path.y
        }

        let urlString = templateString
            .replacingOccurrences(of: "{z}", with: String(path.z))
            .replacingOccurrences(of: "{x}", with: String(path.x))
            .replacingOccurrences(of: "{y}", with: String(y))

        return URL(string: urlString) ?? URL(string: "about:blank")!
    }
}
