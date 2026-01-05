import GoogleMaps
import MapConductorCore

@MainActor
final class GoogleMapRasterLayerOverlayRenderer: AbstractRasterLayerOverlayRenderer<GMSTileLayer> {
    private weak var mapView: GMSMapView?

    init(mapView: GMSMapView?) {
        self.mapView = mapView
        super.init()
    }

    override func createLayer(state: RasterLayerState) async -> GMSTileLayer? {
        guard let mapView else { return nil }
        let layer = makeTileLayer(from: state.source)
        applyVisibility(layer: layer, state: state, mapView: mapView)
        layer.opacity = Float(state.opacity)
        layer.zIndex = Int32(0)
        return layer
    }

    override func updateLayerProperties(
        layer: GMSTileLayer,
        current: RasterLayerEntity<GMSTileLayer>,
        prev: RasterLayerEntity<GMSTileLayer>
    ) async -> GMSTileLayer? {
        let finger = current.fingerPrint
        let prevFinger = prev.fingerPrint

        if finger.source != prevFinger.source {
            layer.map = nil
            guard let mapView else { return nil }
            let newLayer = makeTileLayer(from: current.state.source)
            applyVisibility(layer: newLayer, state: current.state, mapView: mapView)
            newLayer.opacity = Float(current.state.opacity)
            newLayer.zIndex = Int32(0)
            return newLayer
        }

        if finger.opacity != prevFinger.opacity {
            layer.opacity = Float(current.state.opacity)
        }

        if finger.visible != prevFinger.visible {
            guard let mapView else { return layer }
            applyVisibility(layer: layer, state: current.state, mapView: mapView)
        }

        return layer
    }

    override func removeLayer(entity: RasterLayerEntity<GMSTileLayer>) async {
        entity.layer?.map = nil
    }

    private func applyVisibility(layer: GMSTileLayer, state: RasterLayerState, mapView: GMSMapView) {
        layer.map = state.visible ? mapView : nil
    }

    private func makeTileLayer(from source: RasterSource) -> GMSTileLayer {
        switch source {
            /*
             *   GMSTileURLConstructor constructor = ^(NSUInteger x, NSUInteger y, NSUInteger zoom) {
             *     NSString *URLStr =
             *         [NSString stringWithFormat:@"https://example.com/%d/%d/%d.png", x, y, zoom];
             *     return [NSURL URLWithString:URLStr];
             *   };
             *   GMSTileLayer *layer =
             *       [GMSURLTileLayer tileLayerWithURLConstructor:constructor];
             *   layer.userAgent = @"SDK user agent";
             *   layer.map = map;
             */
        case let .urlTemplate(template, tileSize, minZoom, maxZoom, _, _):
            let urls: GMSTileURLConstructor = { (x, y, zoom) in
                let zoomInt = Int(zoom)
                if let minZoom {
                    if zoomInt < minZoom {
                        return nil
                    }
                }
                if let maxZoom {
                    if zoomInt > maxZoom {
                        return nil
                    }
                }
                
                let url = template
                    .replacingOccurrences(of: "{z}", with: String(zoomInt))
                    .replacingOccurrences(of: "{y}", with: String(y))
                    .replacingOccurrences(of: "{x}", with: String(x))
                return URL(string: url)
            }
            
            // Do not change the below line
            let layer = GMSURLTileLayer(urlConstructor: urls)
            layer.tileSize = Int(max(1, tileSize))
            return layer
        case .tileJson:
            fatalError("RasterSource.tileJson is not implemented for Google Maps yet.")
        case .arcGisService:
            fatalError("RasterSource.arcGisService is not implemented for Google Maps yet.")
        }
    }
}
