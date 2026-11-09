import Foundation
import MapConductorCore
import QuartzCore
import UIKit

/// What the last tap hit: a building, or nothing (`building` nil).
struct BostonTap {
    let seq: Int
    let building: BostonBuilding?
    /// Where the tap landed: the polygon event's point, or the map click's.
    let point: GeoPoint?
}

struct BostonStats {
    let polygons: Int
    let vertices: Int
    let loadMs: Double
    let buildMs: Double
}

/// The states handed to the map, as one object: SwiftUI compares a view's
/// inputs, and an array of a hundred thousand states compared element by element
/// (each `==` hashes every vertex) would cost seconds per redraw.
final class BostonPolygonList {
    let states: [PolygonState]
    init(_ states: [PolygonState]) { self.states = states }
}

/// The three nested areas around Downtown Crossing; a building belongs to the smallest that holds it.
let bostonAreas = ["0.8 × 1.1 km", "1.6 × 2.2 km", "3.2 × 4.4 km"]

/**
 Polygons of Boston drawn with one `Polygons` on top of the real map.

 - Downtown: Overture building footprints in three nested areas around Downtown
   Crossing — 0.8 x 1.1 km, 1.6 x 2.2 km and 3.2 x 4.4 km — each building tagged
   with the smallest one that holds it.
 - City buildings / city parcels: the whole city (about 100,000 polygons each), a
   load test. See BostonData.swift for where those files come from. Parcels are
   coloured by land use.

 Tapping a polygon highlights it and shows what it is in an InfoBubble at the tap;
 tapping elsewhere closes it. Every tap is also printed as a `BostonTap` line,
 which is how hit testing is checked from outside.

 Launch environment, so a measurement opens the same view on every provider:
 `MAPCONDUCTOR_SAMPLE_INIT_CAMERA` ("lat,lng,zoom"),
 `MAPCONDUCTOR_SAMPLE_BOSTON_DATA` (downtown, buildings or parcels),
 `MAPCONDUCTOR_SAMPLE_BOSTON_AREA` (0, 1 or 2).
 Same data and behaviour as the React and Android samples.
 */
@MainActor
final class BostonBuildingsViewModel: ObservableObject {
    static let tapped = UIColor(red: 37 / 255, green: 99 / 255, blue: 235 / 255, alpha: 0.85)

    let initCameraPosition: MapCameraPosition

    @Published private(set) var dataset: BostonDataset
    @Published private(set) var area: Int
    @Published private(set) var polygonList = BostonPolygonList([])
    var polygons: [PolygonState] { polygonList.states }
    @Published private(set) var stats: BostonStats?
    @Published private(set) var phase: BostonLoadPhase?
    @Published private(set) var loadError: String?
    @Published private(set) var attribution = ""
    @Published private(set) var tap: BostonTap?

    private var doc: BostonDoc?
    private var states: [PolygonState] = []
    private var loadMs = 0.0
    private var buildMs = 0.0
    private var highlighted: (state: PolygonState, fill: UIColor)?
    private var loadTask: Task<Void, Never>?

    init() {
        let env = ProcessInfo.processInfo.environment
        let parts = env["MAPCONDUCTOR_SAMPLE_INIT_CAMERA"]?.split(separator: ",").compactMap { Double($0) } ?? []
        let (lat, lng, zoom) = parts.count == 3 ? (parts[0], parts[1], parts[2]) : (42.35545, -71.0605, 16.0)
        initCameraPosition = MapCameraPosition(
            position: GeoPoint(latitude: lat, longitude: lng), zoom: zoom, bearing: 0, tilt: 0, paddings: nil
        )
        dataset = env["MAPCONDUCTOR_SAMPLE_BOSTON_DATA"].flatMap(BostonDataset.init(rawValue:)) ?? .downtown
        area = env["MAPCONDUCTOR_SAMPLE_BOSTON_AREA"].flatMap(Int.init).flatMap { bostonAreas.indices.contains($0) ? $0 : nil } ?? 0
    }

    func start() {
        if doc == nil, loadTask == nil { load() }
    }

    func setDataset(_ next: BostonDataset) {
        guard next != dataset else { return }
        dataset = next
        load()
    }

    func setArea(_ level: Int) {
        guard level != area else { return }
        area = level
        show()
    }

    func onMapClick(_ point: GeoPoint) {
        onTap(state: nil, building: nil, point: point)
    }

    private func load() {
        loadTask?.cancel()
        let dataset = self.dataset
        polygonList = BostonPolygonList([])
        stats = nil
        loadError = nil
        tap = nil
        highlighted = nil
        doc = nil
        phase = .read(loaded: 0, total: 0)
        let started = CACurrentMediaTime()
        loadTask = Task { [weak self] in
            do {
                let doc = try await BostonDataLoader.load(dataset) { [weak self] progress in
                    guard let self, self.dataset == dataset, self.phase != nil else { return }
                    self.phase = progress
                }
                guard let self, !Task.isCancelled, self.dataset == dataset else { return }
                self.loadMs = (CACurrentMediaTime() - started) * 1000
                // Building the states takes a moment; show that phase first.
                self.phase = .build
                await Task.yield()
                try? await Task.sleep(nanoseconds: 16_000_000)
                let built = CACurrentMediaTime()
                self.doc = doc
                self.attribution = doc.attribution
                // Off the main thread: a hundred thousand states with 1.4 million
                // points is a second of work the overlay should keep turning through.
                let onTap: (PolygonEvent, BostonBuilding) -> Void = { [weak self] event, building in
                    MainActor.assumeIsolated {
                        self?.onTap(state: event.state, building: building, point: GeoPoint.from(position: event.clicked))
                    }
                }
                self.states = await Task.detached(priority: .userInitiated) {
                    doc.buildings.map { Self.makeState($0, dataset: dataset, onTap: onTap) }
                }.value
                guard !Task.isCancelled, self.dataset == dataset else { return }
                self.buildMs = (CACurrentMediaTime() - built) * 1000
                self.show()
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.phase = nil
                self.loadError = error.localizedDescription
            }
            self?.loadTask = nil
        }
    }

    private func show() {
        guard let doc else { return }
        var shown: [PolygonState] = []
        var vertices = 0
        for (i, building) in doc.buildings.enumerated() where building.level <= area {
            shown.append(states[i])
            vertices += building.vertexCount
        }
        stats = BostonStats(polygons: shown.count, vertices: vertices, loadMs: loadMs, buildMs: buildMs)
        print(String(
            format: "BOSTON shown dataset=%@ polygons=%d vertices=%d load=%.0fms build=%.0fms t=%.3f",
            dataset.rawValue, shown.count, vertices, loadMs, buildMs, CACurrentMediaTime()
        ))
        phase = .draw
        polygonList = BostonPolygonList(shown)
        // The overlay stays up until the frame after the list reached the map.
        DispatchQueue.main.async { [weak self] in
            DispatchQueue.main.async {
                guard let self, self.phase == .draw else { return }
                self.phase = nil
                print(String(format: "BOSTON handed t=%.3f", CACurrentMediaTime()))
            }
        }
    }

    /// Moves the highlight to `state` (or clears it) and records the tap.
    private func onTap(state: PolygonState?, building: BostonBuilding?, point: GeoPoint?) {
        if let previous = highlighted { previous.state.fillColor = previous.fill }
        highlighted = state.map { ($0, $0.fillColor) }
        state?.fillColor = Self.tapped
        let seq = (tap?.seq ?? 0) + 1
        tap = BostonTap(seq: seq, building: building, point: point)
        print("BostonTap seq=\(seq) id=\(building?.id ?? "") lat=\(point?.latitude ?? .nan) lng=\(point?.longitude ?? .nan)")
    }

    nonisolated private static func makeState(
        _ building: BostonBuilding,
        dataset: BostonDataset,
        onTap: @escaping (PolygonEvent, BostonBuilding) -> Void
    ) -> PolygonState {
        let rings = building.rings.map { ring -> [GeoPointProtocol] in
            stride(from: 0, to: ring.count, by: 2).map { GeoPoint(latitude: ring[$0 + 1], longitude: ring[$0]) }
        }
        return PolygonState(
            points: rings[0],
            holes: Array(rings.dropFirst()),
            id: building.id,
            strokeColor: dataset == .parcels
                ? UIColor(red: 71 / 255, green: 85 / 255, blue: 105 / 255, alpha: 0.7)
                : UIColor(red: 68 / 255, green: 64 / 255, blue: 60 / 255, alpha: 0.8),
            strokeWidth: 1,
            fillColor: Self.fill(dataset: dataset, building: building),
            extra: building.id,
            onClick: { event in onTap(event, building) }
        )
    }

    /// Parcels: by land use. Buildings: darker for taller, grey when the height is unknown.
    nonisolated private static func fill(dataset: BostonDataset, building: BostonBuilding) -> UIColor {
        if dataset == .parcels { return (building.use ?? .unknown).fill }
        guard let height = building.height else { return UIColor(red: 148 / 255, green: 163 / 255, blue: 184 / 255, alpha: 0.6) }
        if height < 15 { return UIColor(red: 254 / 255, green: 240 / 255, blue: 138 / 255, alpha: 0.7) }
        if height < 30 { return UIColor(red: 253 / 255, green: 186 / 255, blue: 116 / 255, alpha: 0.7) }
        if height < 60 { return UIColor(red: 249 / 255, green: 115 / 255, blue: 22 / 255, alpha: 0.7) }
        if height < 120 { return UIColor(red: 220 / 255, green: 38 / 255, blue: 38 / 255, alpha: 0.7) }
        return UIColor(red: 127 / 255, green: 29 / 255, blue: 29 / 255, alpha: 0.75)
    }
}
