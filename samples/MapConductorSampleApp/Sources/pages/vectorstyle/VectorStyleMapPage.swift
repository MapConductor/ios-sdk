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
import MapConductorVectorStyle
import MapConductorVectorTile
import SwiftUI

/**
 The same style adjustment on every backend, through `XxxMapView(style:)`.

 Two things are worth watching rather than just looking at:

 - **The provider switcher.** MapLibre, Mapbox and MapTiler are handed the
   document and then told the per-layer differences; the rest cannot read a
   style at all and are given raster tiles drawn from it. Same rules, same
   map.
 - **The road-lightness slider.** Dragging it writes a new rule set on every
   frame, which on a vector backend sends differences and reloads nothing.
   If a drag makes the tiles flash, the in-place path is broken.

 android-sdk's `VectorStylePage` is the same page.
 */
struct VectorStyleMapPage: View {
    let onToggleSidebar: () -> Void

    @State private var preset: StylePreset = .roads
    @State private var roadLightness: Double = 1.0
    @State private var fromCurrentDesign = false
    @State private var styleJSON: String?
    @State private var failure: String?
    @State private var diagnostics: [String] = []

    /// Draws the style for a backend that cannot read one. The three that
    /// can never call it.
    ///
    /// `@State`, not `let`: a `View` is a value that SwiftUI rebuilds on
    /// every evaluation, so a `let` here would be a **new rasteriser each
    /// time** — and `VectorStyle` treats a different rasteriser as a
    /// different style, so the map would tear the style down and install it
    /// again on every frame. The symptom is tiles being fetched endlessly
    /// with nothing ever drawn.
    @State private var rasteriser = VectorTileRasteriser(
        assetCacheDirectory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("vectortile")
    )

    @State private var provider: MapProvider

    @StateObject private var googleState: GoogleMapViewState
    @StateObject private var mapLibreState: MapLibreViewState
    @StateObject private var mapKitState: MapKitViewState
    @StateObject private var mapboxState: MapboxViewState
    @StateObject private var arcGISState: ArcGISMapViewState
    @StateObject private var hereState: HereMapViewState
    @StateObject private var tomTomState: TomTomMapViewState
    @StateObject private var mapTilerState: MapTilerViewState
    @StateObject private var longdoState: LongdoViewState
    @StateObject private var openMobileMapsState: OpenMobileMapsViewState
    @StateObject private var mapplsState: MapplsViewState

    init(onToggleSidebar: @escaping () -> Void = {}) {
        self.onToggleSidebar = onToggleSidebar
        let vm = VectorTilePageViewModel()
        _provider = State(initialValue: MapProvider.initial())
        _googleState = StateObject(
            wrappedValue: GoogleMapViewState(cameraPosition: vm.initCameraPosition))
        _mapLibreState = StateObject(
            wrappedValue: MapLibreViewState(
                mapDesignType: MapLibreDesign.DemoTiles, cameraPosition: vm.initCameraPosition))
        _mapKitState = StateObject(
            wrappedValue: MapKitViewState(
                mapDesignType: MapKitMapDesign.Standard, cameraPosition: vm.initCameraPosition))
        _mapboxState = StateObject(
            wrappedValue: MapboxViewState(cameraPosition: vm.initCameraPosition))
        _arcGISState = StateObject(
            wrappedValue: ArcGISMapViewState(
                mapDesignType: ArcGISDesign.OsmStandard, cameraPosition: vm.initCameraPosition))
        _hereState = StateObject(
            wrappedValue: HereMapViewState(
                mapDesignType: HereMapDesign.NormalDay, cameraPosition: vm.initCameraPosition))
        _tomTomState = StateObject(
            wrappedValue: TomTomMapViewState(
                mapDesignType: TomTomMapDesign.Standard, cameraPosition: vm.initCameraPosition))
        _mapTilerState = StateObject(
            wrappedValue: MapTilerViewState(
                mapDesignType: MapTilerDesign.Streets, cameraPosition: vm.initCameraPosition))
        _longdoState = StateObject(
            wrappedValue: LongdoViewState(
                mapDesignType: LongdoDesign.Normal, cameraPosition: vm.initCameraPosition))
        _openMobileMapsState = StateObject(
            wrappedValue: OpenMobileMapsViewState(
                mapDesignType: OpenMobileMapsDesign.openStreetMap,
                cameraPosition: vm.initCameraPosition))
        _mapplsState = StateObject(
            wrappedValue: MapplsViewState(
                mapDesignType: MapplsDesign.Default, cameraPosition: vm.initCameraPosition))
    }

    var body: some View {
        DemoMapPageScaffold(provider: $provider, onToggleSidebar: onToggleSidebar) {
            ZStack(alignment: .bottomLeading) {
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
                    mapplsState: mapplsState,
                    mapStyle: style,
                    onStyleDiagnostics: { diagnostics = $0 }
                ) {
                    MapViewContent()
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Style Adjustments").font(.headline)

                    Picker("", selection: $preset) {
                        ForEach(StylePreset.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("stylePreset")

                    Toggle("Adjust the map's own style", isOn: $fromCurrentDesign)
                        .font(.caption)
                        .accessibilityIdentifier("currentDesignToggle")

                    Text(String(format: "Road lightness %.2f", roadLightness)).font(.caption)
                    Slider(value: $roadLightness, in: 0...1)
                        .accessibilityIdentifier("roadLightness")

                    // The rule that matched nothing, the adjustment this
                    // backend would not take, the style that could not be
                    // read: the failures here all look like "it nearly
                    // worked" and nothing else reports them.
                    ForEach(diagnostics, id: \.self) { message in
                        Text(message).font(.caption2).foregroundColor(.orange)
                    }
                    if let failure {
                        Text("style failed: \(failure)").font(.caption2).foregroundColor(.red)
                    }
                }
                .padding(16)
                .frame(maxWidth: 420, alignment: .leading)
                .background(Color(UIColor.systemBackground).opacity(0.95))
                .cornerRadius(12)
                .padding(16)
            }
        }
        .task {
            guard styleJSON == nil, failure == nil else { return }
            do { styleJSON = try await VectorTileStyleLoader.load() } catch {
                failure = String(describing: error)
            }
        }
    }

    /// A new value on every slider frame, by design: what decides whether the
    /// map reinstalls is the style's `key`, not identity.
    private var style: MapViewStyle? {
        let rules = preset.rules(roadLightness: roadLightness)
        if fromCurrentDesign {
            return VectorStyle(document: .currentDesign, rules: rules, rasteriser: rasteriser)
        }
        guard let styleJSON else { return nil }
        return VectorStyle(document: .text(styleJSON), rules: rules, rasteriser: rasteriser)
    }
}

enum StylePreset: CaseIterable {
    case roads, night, water, asAuthored

    var label: String {
        switch self {
        case .roads: return "Roads"
        case .night: return "Night"
        case .water: return "Water"
        case .asAuthored: return "As authored"
        }
    }

    func rules(roadLightness: Double) -> StyleRules {
        let road = UIColor(white: roadLightness, alpha: 1)
        switch self {
        case .asAuthored:
            return StyleRules.none
        case .roads:
            return StyleRules.build { rules in
                rules.all { $0.color = .black }
                rules.role(LayerRole.label) { $0.visible = false }
                rules.role(LayerRole.roadCasing) { $0.color = UIColor(white: 0.19, alpha: 1) }
                rules.role(LayerRole.road) {
                    $0.color = road
                    $0.widthScale = 1.4
                }
            }
        case .night:
            return StyleRules.build { rules in
                rules.all { $0.darken(0.55) }
                rules.role(LayerRole.road) { $0.color = road }
                rules.role(LayerRole.water) { $0.color = UIColor(red: 0.04, green: 0.11, blue: 0.17, alpha: 1) }
            }
        case .water:
            return StyleRules.build { rules in
                rules.all { $0.visible = false }
                rules.role(LayerRole.background) {
                    $0.visible = true
                    $0.color = UIColor(white: 0.95, alpha: 1)
                }
                rules.role(LayerRole.water) {
                    $0.visible = true
                    $0.color = UIColor(red: 0.18, green: 0.44, blue: 0.72, alpha: 1)
                }
            }
        }
    }
}
