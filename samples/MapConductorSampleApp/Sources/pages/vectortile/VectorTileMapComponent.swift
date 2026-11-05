import MapConductorCore
import MapConductorForArcGIS
import MapConductorForGoogleMaps
import MapConductorForHERE
import MapConductorForLongdo
import MapConductorForMapKit
import MapConductorForMapLibre
import MapConductorForMapTiler
import MapConductorForMapbox
import MapConductorForMappls
import MapConductorForOpenMobileMaps
import MapConductorForTomTom
import SwiftUI

/**
 Mounts the two halves of the vector style as stacked raster layers.

 The backend only ever sees ordinary raster layers, which is what makes this
 work on MapKit, Google Maps, HERE, ArcGIS and the rest — none of which can
 render a vector style themselves.
 */
struct VectorTileMapComponent: View {
    @Binding var provider: MapProvider
    @ObservedObject var googleState: GoogleMapViewState
    @ObservedObject var mapLibreState: MapLibreViewState
    @ObservedObject var mapKitState: MapKitViewState
    @ObservedObject var mapboxState: MapboxViewState
    @ObservedObject var arcGISState: ArcGISMapViewState
    @ObservedObject var hereState: HereMapViewState
    @ObservedObject var tomTomState: TomTomMapViewState
    @ObservedObject var mapTilerState: MapTilerViewState
    @ObservedObject var longdoState: LongdoViewState
    @ObservedObject var openMobileMapsState: OpenMobileMapsViewState
    @ObservedObject var mapplsState: MapplsViewState

    let ground: RasterLayerState?
    let labels: [RasterLayerState]

    var body: some View {
        SampleMapView(
            provider: $provider,
            googleState: googleState,
            mapLibreState: mapLibreState,
            mapKitState: mapKitState,
            mapboxState: mapboxState,
            arcGISState: arcGISState,
            hereState: hereState,
            tomTomState: tomTomState,
            mapTilerState: mapTilerState,
            longdoState: longdoState,
            openMobileMapsState: openMobileMapsState,
            mapplsState: mapplsState
        ) {
            { () -> MapViewContent in
                var content = MapViewContent()
                // Ground first, labels over it. Order here and `zIndex` say the
                // same thing; backends differ in which one they honour.
                content.rasterLayers = ([ground] + labels)
                    .compactMap { $0 }
                    .map { RasterLayer(state: $0) }
                return content
            }()
        }
    }
}
