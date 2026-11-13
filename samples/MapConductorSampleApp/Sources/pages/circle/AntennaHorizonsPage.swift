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


private let carrierNames = ["AT&T", "T-Mobile / Sprint", "Verizon", "Others"]
private let carrierColors: [UIColor] = [.systemBlue, .systemPink, .systemOrange, .systemGray]
private let carrierStrokeColors = carrierColors.map { $0.withAlphaComponent(0.35) }
private let carrierFillColors = carrierColors.map { $0.withAlphaComponent(0.65) }
private struct AntennaRecord: Sendable { let lat: Double; let lon: Double; let radius: Double; let registration: UInt32; let carrier: Int }
private func loadAntennas() throws -> [AntennaRecord] {
    guard let url = Bundle.main.url(forResource: "us-antennas", withExtension: "bin", subdirectory: "antennas") else { throw CocoaError(.fileNoSuchFile) }
    let bytes = try Data(contentsOf: url)
    guard bytes.count >= 8, String(data: bytes.prefix(4), encoding: .ascii) == "MCCE" else { throw CocoaError(.fileReadCorruptFile) }
    func u32(_ p: Int) -> UInt32 { (0..<4).reduce(UInt32(0)) { $0 | UInt32(bytes[p + $1]) << (8 * $1) } }
    let count = Int(u32(4))
    guard bytes.count == 8 + count * 16 else { throw CocoaError(.fileReadCorruptFile) }
    return try (0..<count).map { i in
        let p = 8 + i * 16
        let a = AntennaRecord(lat: Double(Int32(bitPattern: u32(p))) / 100000, lon: Double(Int32(bitPattern: u32(p + 4))) / 100000, radius: Double(Float(bitPattern: u32(p + 8))), registration: UInt32(i), carrier: Int(u32(p + 12) / 1000))
        guard a.lat.isFinite, abs(a.lat) <= 90, a.lon.isFinite, abs(a.lon) <= 180, a.radius > 0, a.radius <= 100000, (0...3).contains(a.carrier) else { throw CocoaError(.fileReadCorruptFile) }
        return a
    }
}
struct AntennaHorizonsPage: View {
    let onToggleSidebar: () -> Void
    @State private var provider: MapProvider
    @State private var rows: [AntennaRecord] = []
    @State private var circles: [CircleState] = []
    @State private var allCircles: [CircleState] = []
    @State private var carrierCounts = [0, 0, 0, 0]
    @State private var tap: AntennaRecord?
    @State private var error: String?
    @State private var carriers: Set<Int> = [0, 1, 2, 3]
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
        let camera = MapCameraPosition(position: GeoPoint(latitude: 39, longitude: -98), zoom: 4)
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
            onMapClick: { _ in tap = nil }
        ) {
                    { () -> MapViewContent in
                        var content = MapViewContent()
                        Circles(circles).append(to: &content)
                        if let a = tap {
                            content.infoBubbles = [InfoBubble(position: GeoPoint(latitude: a.lat, longitude: a.lon), id: "antenna-tap") {
                                Text("\(carrierNames[a.carrier])\nCell position · Display radius: 500 m")
                            }]
                        }
                        return content
                    }()
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("US cell positions (MCC 310–314)").font(.headline)
                    Text(error ?? (rows.isEmpty ? "Loading OpenCellID data…" : "\(circles.count) / \(rows.count) circles"))
                        .accessibilityIdentifier("antenna-circle-count")
                    HStack { Button("US overview") { moveCamera(39, -98, 4) }; Button("Alaska") { moveCamera(64, -150, 5) } }
                    ForEach(0..<4) { index in
                        Toggle("\(carrierNames[index]) (\(carrierCounts[index]))", isOn: Binding(get: { carriers.contains(index) }, set: { checked in
                            if checked { carriers.insert(index) } else { carriers.remove(index) }
                        }))
                    }
                    Text("Cell positions shown as 500 m radius circles; not signal coverage. Showing all cells for the selected carriers. MCC 310–314; not a complete tower inventory.").font(.caption)
                    Text("Cell tower data from [OpenCellID](https://opencellid.org) · [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/)").font(.caption2)
                }.padding().frame(maxWidth: 350).background(.regularMaterial).clipShape(RoundedRectangle(cornerRadius: 12)).padding()
            }
        }
        .task {
            guard rows.isEmpty else { return }
            do {
                let loaded = try await Task.detached { try loadAntennas() }.value
                guard !Task.isCancelled else { return }
                prepare(loaded)
            }
            catch { self.error = error.localizedDescription }
        }
        .onChange(of: carriers) { _ in rebuild() }
    }
    private func prepare(_ loaded: [AntennaRecord]) {
        rows = loaded
        var counts = [0, 0, 0, 0]
        let onCellClick: OnCircleEventHandler = { [selection = $tap] event in
            guard let id = event.state.extra as? String, id.hasPrefix("asr-"),
                  let index = Int(id.dropFirst(4)), loaded.indices.contains(index) else { return }
            selection.wrappedValue = loaded[index]
        }
        allCircles = loaded.map { a in
            counts[a.carrier] += 1
            let id = "asr-\(a.registration)"
            return CircleState(center: GeoPoint(latitude: a.lat, longitude: a.lon), radiusMeters: 500, geodesic: true, strokeColor: carrierStrokeColors[a.carrier], strokeWidth: 0.5, fillColor: carrierFillColors[a.carrier], id: id, zIndex: Int(a.registration), extra: id, onClick: onCellClick)
        }
        carrierCounts = counts
        rebuild()
    }
    private func rebuild() {
        tap = nil
        if carriers.count == carrierNames.count { circles = allCircles }
        else if carriers.isEmpty { circles = [] }
        else { circles = allCircles.indices.compactMap { carriers.contains(rows[$0].carrier) ? allCircles[$0] : nil } }
    }
    private func moveCamera(_ lat: Double, _ lon: Double, _ zoom: Double) {
        let camera = MapCameraPosition(position: GeoPoint(latitude: lat, longitude: lon), zoom: zoom)
        googleState.moveCameraTo(cameraPosition: camera)
        mapLibreState.moveCameraTo(cameraPosition: camera)
        mapKitState.moveCameraTo(cameraPosition: camera)
        mapboxState.moveCameraTo(cameraPosition: camera)
        arcGISState.moveCameraTo(cameraPosition: camera)
        hereState.moveCameraTo(cameraPosition: camera)
        tomTomState.moveCameraTo(cameraPosition: camera)
        mapTilerState.moveCameraTo(cameraPosition: camera)
        longdoState.moveCameraTo(cameraPosition: camera)
        openMobileMapsState.moveCameraTo(cameraPosition: camera)
        mapplsState.moveCameraTo(cameraPosition: camera)
    }
}
