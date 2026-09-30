import Foundation
import MapConductorCore
import MapConductorForArcGIS
import MapConductorForGoogleMaps
import MapConductorForLongdo
import MapConductorForMapLibre
import MapConductorForMapTiler
import MapConductorForMapbox
import MapConductorForOpenMobileMaps
import MapConductorForTomTom

/**
 Blanks a backend's own basemap, or restores it.

 Which design means "draw nothing" is provider-specific, and only some
 providers have one. Where there is none the opaque tiles cover it anyway --
 the difference is whether the device also fetches a basemap nobody sees.
 MapKit, HERE and Mappls have no such design.
 */
func showProviderBasemap(_ state: AnyObject, visible: Bool) {
    switch state {
    case let mapLibre as MapLibreViewState:
        if visible {
            mapLibre.mapDesignType = MapLibreDesign.DemoTiles
        } else if let blank = Bundle.main.url(forResource: "blank-style", withExtension: "json") {
            mapLibre.mapDesignType = MapLibreDesign(id: "blank", styleJsonURL: blank.absoluteString)
        }
    case let google as GoogleMapViewState:
        google.mapDesignType = visible ? GoogleMapDesign.Normal : GoogleMapDesign.None
    case let arcGIS as ArcGISMapViewState:
        arcGIS.mapDesignType = visible ? ArcGISDesign.OsmStandard : ArcGISDesign.None
    case let mapbox as MapboxViewState:
        mapbox.mapDesignType = visible ? MapboxMapDesign.Standard : MapboxMapDesign.None
    case let tomTom as TomTomMapViewState:
        tomTom.mapDesignType = visible ? TomTomMapDesign.Standard : TomTomMapDesign.None
    case let mapTiler as MapTilerViewState:
        mapTiler.mapDesignType = visible ? MapTilerDesign.Streets : MapTilerDesign.None
    case let longdo as LongdoViewState:
        longdo.mapDesignType = visible ? LongdoDesign.Normal : LongdoDesign.None
    case let omm as OpenMobileMapsViewState:
        omm.mapDesignType = visible ? OpenMobileMapsDesign.openStreetMap : OpenMobileMapsDesign.none
    default:
        break
    }
}
