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

/// Boston's roads drawn with one `Polylines` (see ``BostonRoadsViewModel``).
struct BostonRoadsPage: View {
    let onToggleSidebar: () -> Void

    @State private var provider: MapProvider
    @StateObject private var viewModel: BostonRoadsViewModel
    @State private var probe = BostonProbe()
    @State private var cycleStarted = false

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
        let vm = BostonRoadsViewModel()
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
                BostonRoadsMapComponent(
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
                    polylines: viewModel.polylineList,
                    tiling: viewModel.tilingOptions,
                    stacking: viewModel.stacking ? viewModel.stackingOverlays : nil,
                    tap: viewModel.tap,
                    onMapClick: { viewModel.onMapClick($0) }
                )

                if let phase = viewModel.phase {
                    BostonRoadsLoadingOverlay(phase: phase, added: viewModel.addedCount, total: viewModel.stats?.polylines)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                BostonRoadsControlPanel(viewModel: viewModel)
                    .padding(12)
            }
        }
        .onAppear {
            viewModel.start()
            probe.start()
        }
        .onDisappear { probe.stop() }
        .onChange(of: provider) { next in
            print("ROADS provider=\(next.rawValue) footprint=\(Int(BostonRoadsViewModel.footprintMB()))MB")
        }
        .onChange(of: viewModel.polylines.count) { count in
            guard count > 0 else { return }
            probe.autopan(from: viewModel.initCameraPosition) { target, millis in
                activeState?.moveCameraTo(cameraPosition: target, durationMillis: Long(millis))
            }
            startCycleIfAsked()
        }
    }

    /// `MAPCONDUCTOR_SAMPLE_ROADS_CYCLE="maplibre,googlemaps,…[,seconds]"`: switches the
    /// provider through the list once the roads are first shown, `seconds` (20 by default)
    /// apart, printing the memory footprint just before each switch and at the end.
    private func startCycleIfAsked() {
        guard !cycleStarted, let raw = ProcessInfo.processInfo.environment["MAPCONDUCTOR_SAMPLE_ROADS_CYCLE"] else { return }
        cycleStarted = true
        let parts = raw.split(separator: ",").map(String.init)
        let seconds = parts.last.flatMap(Double.init) ?? 20
        let providers = parts.compactMap(MapProvider.parse)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            for (i, next) in providers.enumerated() {
                print(String(format: "ROADS cycle i=%d from=%@ footprint=%.0fMB", i, provider.rawValue, BostonRoadsViewModel.footprintMB()))
                provider = next
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            }
            print(String(format: "ROADS cycle done at=%@ footprint=%.0fMB", provider.rawValue, BostonRoadsViewModel.footprintMB()))
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

private struct BostonRoadsMapComponent: View {
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
    let polylines: BostonPolylineList
    let tiling: PolylineTilingOptions
    let stacking: BostonStackingOverlays?
    let tap: BostonRoadTap?
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
                PolylineTiling(tiling).append(to: &content)
                Polylines(polylines.states).append(to: &content)
                if let stacking {
                    // A second `Polylines` next to the roads: the geodesic line is drawn natively, above the road tiles.
                    Polylines([stacking.geodesic]).append(to: &content)
                    Polygons(stacking.polygons).append(to: &content)
                    Circles([stacking.circle]).append(to: &content)
                    Markers(stacking.markers).append(to: &content)
                }
                if let tap, let road = tap.road, let point = tap.point {
                    content.infoBubbles = [
                        InfoBubble(position: point, id: "boston-road-tap-\(tap.seq)", contentPadding: 8) {
                            BostonRoadInfo(road: road)
                        }
                    ]
                }
                return content
            }()
        }
    }
}

/// Covers the map while the roads load and reach it.
private struct BostonRoadsLoadingOverlay: View {
    let phase: BostonLoadPhase
    let added: Int
    let total: Int?

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
        .accessibilityIdentifier("boston-roads-loading")
    }

    private var text: String {
        switch phase {
        case let .read(loaded, total):
            let mb = { (bytes: Int) in String(format: "%.1f", Double(bytes) / 1_048_576) }
            return total > 0 ? "Loading data… \(mb(loaded)) / \(mb(total)) MB" : "Loading data… \(mb(loaded)) MB"
        case .decode: return "Reading the roads…"
        case .build: return "Preparing the roads…"
        case .draw:
            guard let total else { return "Drawing the map…" }
            return "Drawing the map… \(added.formatted()) / \(total.formatted())"
        }
    }

    private var fraction: Double? {
        switch phase {
        case let .read(loaded, total) where total > 0: return Double(loaded) / Double(total)
        case .draw: return total.map { $0 > 0 ? Double(added) / Double($0) : 0 }
        default: return nil
        }
    }
}

private struct BostonRoadsControlPanel: View {
    @ObservedObject var viewModel: BostonRoadsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Boston roads").font(.headline)
            Toggle("Draw as tiles", isOn: Binding(get: { viewModel.tiling }, set: { viewModel.setTiling($0) }))
                .font(.subheadline)
                .accessibilityIdentifier("boston-roads-tiling")
            Toggle("Stacking check", isOn: Binding(get: { viewModel.stacking }, set: { viewModel.setStacking($0) }))
                .font(.subheadline)
                .accessibilityIdentifier("boston-roads-stacking")
            BostonRoadsLegend()
            if let error = viewModel.loadError {
                Text(error).font(.caption).foregroundColor(.red).fixedSize(horizontal: false, vertical: true)
            }
            if let stats = viewModel.stats {
                Text("\(stats.polylines.formatted()) polylines, \(stats.vertices.formatted()) vertices")
                    .font(.caption)
                Text(String(format: "load %.0f ms, states %.0f ms", stats.loadMs, stats.buildMs))
                    .font(.caption2).foregroundColor(.secondary)
            }
            Text(timingText)
                .font(.caption2).foregroundColor(.secondary)
                .accessibilityIdentifier("boston-roads-timing")
            if let tap = viewModel.tap {
                Text(tapText(tap)).font(.caption)
                    .accessibilityIdentifier("boston-roads-tap")
                    .accessibilityValue("\(tap.seq)|\(tap.road?.id ?? "")|\(tap.point?.latitude ?? .nan)|\(tap.point?.longitude ?? .nan)")
            }
            Text(BostonRoadsLoader.attribution).font(.system(size: 10)).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(width: 340, alignment: .leading)
        .background(Color(UIColor.systemBackground).opacity(0.95))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
    }

    private var timingText: String {
        let mode = viewModel.tiling ? "tiles" : "native"
        guard let all = viewModel.allAddedMs else {
            return "\(mode): \(viewModel.addedCount.formatted()) onAdded so far"
        }
        let first = viewModel.firstAddedMs.map { String(format: "first %.0f ms, ", $0) } ?? ""
        return String(format: "%@: load → all onAdded %.0f ms (%@%.0f MB)", mode, all, first, viewModel.footprintMB)
    }

    private func tapText(_ tap: BostonRoadTap) -> String {
        guard let road = tap.road else { return "No road here" }
        return "\(road.road.label) · \(road.name ?? "unnamed") · \(formatLength(road.lengthMetres))"
    }
}

private struct BostonRoadsLegend: View {
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], spacing: 2) {
            ForEach(RoadClass.allCases) { road in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color(road.color))
                        .frame(width: 18, height: max(1.5, road.width))
                    Text(road.label).font(.system(size: 10)).lineLimit(1)
                }
            }
        }
    }
}

/// What a tapped road carries, shown in an InfoBubble at the closest point on it.
private struct BostonRoadInfo: View {
    let road: BostonRoad

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
        .accessibilityIdentifier("boston-road-info")
    }

    private var rows: [(String, String)] {
        var rows: [(String, String)] = [("Class", road.road.label)]
        if let name = road.name { rows.append(("Name", name)) }
        rows.append(("Length", formatLength(road.lengthMetres)))
        rows.append(("Vertices", "\(road.vertexCount)"))
        return rows
    }
}

/// "123 m", or kilometres from 1,000 m up.
func formatLength(_ metres: Double) -> String {
    metres >= 1_000 ? String(format: "%.2f km", metres / 1_000) : "\(Int(metres.rounded())) m"
}
