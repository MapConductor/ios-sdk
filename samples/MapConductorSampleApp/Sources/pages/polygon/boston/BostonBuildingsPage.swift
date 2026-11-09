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

/// Boston's buildings or parcels drawn with one `Polygons` (see ``BostonBuildingsViewModel``).
struct BostonBuildingsPage: View {
    let onToggleSidebar: () -> Void

    @State private var provider: MapProvider
    @StateObject private var viewModel: BostonBuildingsViewModel
    @State private var probe = BostonProbe()

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
        let vm = BostonBuildingsViewModel()
        let camera = vm.initCameraPosition
        _viewModel = StateObject(wrappedValue: vm)
        _provider = State(initialValue: MapProvider.initial())
        _googleState = StateObject(wrappedValue: GoogleMapViewState(cameraPosition: camera))
        _mapLibreState = StateObject(wrappedValue: MapLibreViewState(cameraPosition: camera))
        _mapKitState = StateObject(wrappedValue: MapKitViewState(mapDesignType: MapKitMapDesign.Standard, cameraPosition: camera))
        _mapboxState = StateObject(wrappedValue: MapboxViewState(cameraPosition: camera))
        _arcGISState = StateObject(wrappedValue: ArcGISMapViewState(mapDesignType: ArcGISDesign.OsmStandard, cameraPosition: camera))
        _hereState = StateObject(wrappedValue: HereMapViewState(mapDesignType: HereMapDesign.NormalDay, cameraPosition: camera))
        _tomTomState = StateObject(wrappedValue: TomTomMapViewState(mapDesignType: TomTomMapDesign.Standard, cameraPosition: camera))
        _mapTilerState = StateObject(wrappedValue: MapTilerViewState(mapDesignType: MapTilerDesign.Streets, cameraPosition: camera))
        _longdoState = StateObject(wrappedValue: LongdoViewState(mapDesignType: LongdoDesign.Normal, cameraPosition: camera))
        _openMobileMapsState = StateObject(wrappedValue: OpenMobileMapsViewState(
            mapDesignType: OpenMobileMapsDesign.openStreetMap, cameraPosition: camera
        ))
        _mapplsState = StateObject(wrappedValue: MapplsViewState(mapDesignType: MapplsDesign.Default, cameraPosition: camera))
    }

    var body: some View {
        DemoMapPageScaffold(provider: $provider, onToggleSidebar: onToggleSidebar) {
            ZStack(alignment: .bottomLeading) {
                BostonMapComponent(
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
                    polygons: viewModel.polygonList,
                    tap: viewModel.tap,
                    onMapClick: { viewModel.onMapClick($0) }
                )

                if let phase = viewModel.phase {
                    BostonLoadingOverlay(phase: phase)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                BostonControlPanel(viewModel: viewModel)
                    .padding(12)
            }
        }
        .onAppear {
            viewModel.start()
            probe.start()
        }
        .onDisappear { probe.stop() }
        .onChange(of: viewModel.polygons.count) { count in
            guard count > 0 else { return }
            probe.autopan(from: viewModel.initCameraPosition) { target, millis in
                activeState?.moveCameraTo(cameraPosition: target, durationMillis: Long(millis))
            }
        }
    }

    private var activeState: (any MapViewStateProtocol)? {
        switch provider {
        case .googleMaps: return googleState
        case .mapLibre: return mapLibreState
        case .mapKit: return mapKitState
        case .mapbox: return mapboxState
        case .arcGIS, .arcGIS2D: return arcGISState
        case .here: return hereState
        case .tomTom: return tomTomState
        case .mapTiler: return mapTilerState
        case .longdo: return longdoState
        case .openMobileMaps: return openMobileMapsState
        case .mappls: return mapplsState
        }
    }
}

private struct BostonMapComponent: View {
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

    /// A reference, so SwiftUI compares it by identity rather than state by state.
    let polygons: BostonPolygonList
    let tap: BostonTap?
    let onMapClick: (GeoPoint) -> Void

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
            mapplsState: mapplsState,
            onMapClick: onMapClick
        ) {
            { () -> MapViewContent in
                var content = MapViewContent()
                Polygons(polygons.states).append(to: &content)
                if let tap, let building = tap.building, let point = tap.point {
                    content.infoBubbles = [
                        InfoBubble(position: point, id: "boston-tap-\(tap.seq)", contentPadding: 8) {
                            BostonPolygonInfo(building: building)
                        }
                    ]
                }
                return content
            }()
        }
    }
}

/// Covers the map while a dataset loads and the polygons reach it.
private struct BostonLoadingOverlay: View {
    let phase: BostonLoadPhase

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
            VStack(spacing: 10) {
                ProgressView()
                Text(text).font(.subheadline)
                if let fraction {
                    ProgressView(value: fraction).frame(width: 220)
                }
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 20)
            .frame(minWidth: 240)
            .background(Color(UIColor.systemBackground))
            .cornerRadius(10)
            .shadow(color: Color.black.opacity(0.25), radius: 12, x: 0, y: 8)
        }
        .ignoresSafeArea()
        .accessibilityIdentifier("boston-loading")
    }

    private var text: String {
        switch phase {
        case let .read(loaded, total):
            let mb = { (bytes: Int) in String(format: "%.1f", Double(bytes) / 1_048_576) }
            return total > 0 ? "Loading data… \(mb(loaded)) / \(mb(total)) MB" : "Loading data… \(mb(loaded)) MB"
        case .decode: return "Reading the polygons…"
        case .build: return "Preparing the polygons…"
        case .draw: return "Drawing the map…"
        }
    }

    private var fraction: Double? {
        if case let .read(loaded, total) = phase, total > 0 { return Double(loaded) / Double(total) }
        return nil
    }
}

private struct BostonControlPanel: View {
    @ObservedObject var viewModel: BostonBuildingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Boston buildings").font(.headline)
            Picker("Data", selection: Binding(get: { viewModel.dataset }, set: { viewModel.setDataset($0) })) {
                ForEach(BostonDataset.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            if viewModel.dataset == .downtown {
                Picker("Area", selection: Binding(get: { viewModel.area }, set: { viewModel.setArea($0) })) {
                    ForEach(bostonAreas.indices, id: \.self) { Text(bostonAreas[$0]).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            if let error = viewModel.loadError {
                Text(error).font(.caption).foregroundColor(.red).fixedSize(horizontal: false, vertical: true)
            }
            if viewModel.dataset == .parcels { BostonLandUseLegend() }
            if let stats = viewModel.stats {
                Text("\(stats.polygons.formatted()) polygons, \(stats.vertices.formatted()) vertices")
                    .font(.caption)
                Text(String(format: "load %.0f ms, states %.0f ms", stats.loadMs, stats.buildMs))
                    .font(.caption2).foregroundColor(.secondary)
            }
            if let tap = viewModel.tap {
                Text(tapText(tap)).font(.caption)
                    .accessibilityIdentifier("boston-tap")
                    // What a UI test reads back: "seq|id|lat|lng" (the React sample's data-* attributes).
                    .accessibilityValue("\(tap.seq)|\(tap.building?.id ?? "")|\(tap.point?.latitude ?? .nan)|\(tap.point?.longitude ?? .nan)")
            }
            if !viewModel.attribution.isEmpty {
                Text(viewModel.attribution).font(.system(size: 10)).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(width: 340, alignment: .leading)
        .background(Color(UIColor.systemBackground).opacity(0.95))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
    }

    private func tapText(_ tap: BostonTap) -> String {
        guard let building = tap.building else { return "No building here" }
        if let use = building.use { return "\(building.name ?? building.id) · \(use.label)" }
        let height = building.height.map { "\($0.formatted()) m" } ?? "height unknown"
        return "\(building.name ?? "Building") · \(height) · \(building.id.prefix(8))"
    }
}

private struct BostonLandUseLegend: View {
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], spacing: 2) {
            ForEach(LandUse.allCases, id: \.self) { use in
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(use.fill))
                        .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color.gray.opacity(0.6), lineWidth: 1))
                        .frame(width: 10, height: 10)
                    Text(use.label).font(.system(size: 10)).lineLimit(1)
                }
            }
        }
    }
}

/// What a tapped polygon carries, shown in an InfoBubble at the tap.
private struct BostonPolygonInfo: View {
    let building: BostonBuilding

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 2) {
            ForEach(rows, id: \.0) { row in
                GridRow {
                    Text(row.0).fontWeight(.semibold).foregroundColor(Color(red: 0.28, green: 0.33, blue: 0.41))
                    Text(row.1)
                }
            }
        }
        .font(.system(size: 12))
        .fixedSize()
        .accessibilityIdentifier("boston-polygon-info")
    }

    private var rows: [(String, String)] {
        var rows: [(String, String)] = []
        if let use = building.use {
            rows.append(("Parcel", building.name?.replacingOccurrences(of: "Parcel ", with: "") ?? "—"))
            rows.append(("Land use", use.label))
        } else {
            if let name = building.name { rows.append(("Name", name)) }
            rows.append(("Height", building.height.map { "\($0.formatted()) m" } ?? "unknown"))
            rows.append(("Overture ID", building.id.count > 13 ? "\(building.id.prefix(13))…" : building.id))
        }
        let holes = building.rings.count - 1
        rows.append(("Vertices", "\(building.vertexCount)" + (holes > 0 ? " (holes \(holes))" : "")))
        return rows
    }
}
