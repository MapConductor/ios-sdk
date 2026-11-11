import MapConductorCore
import MapConductorForGoogleMaps
import MapConductorForMapLibre
import MapConductorForMapKit
import MapConductorForMapbox
import MapConductorForArcGIS
import MapConductorForHERE
import MapConductorForTomTom
import MapConductorForMapTiler
import MapConductorForLongdo
import MapConductorForOpenMobileMaps
import MapConductorForMappls
import SwiftUI
import UIKit

struct ProjectedCoordinatesPage: View {
    let onToggleSidebar: () -> Void

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
        // react-sdk / android の同ページと同じカメラ。並べて数値を突き合わせるため揃えてある。
        let initCamera = MapCameraPosition(
            position: GeoPoint(latitude: 35.681236, longitude: 139.767125),
            zoom: 12.0
        )
        _provider = State(initialValue: MapProvider.initial())
        _googleState = StateObject(wrappedValue: GoogleMapViewState(cameraPosition: initCamera))
        _mapLibreState = StateObject(wrappedValue: MapLibreViewState(
            mapDesignType: MapLibreDesign.DemoTiles,
            cameraPosition: initCamera
        ))
        _mapKitState = StateObject(wrappedValue: MapKitViewState(
            mapDesignType: MapKitMapDesign.Standard,
            cameraPosition: initCamera
        ))
        _mapboxState = StateObject(wrappedValue: MapboxViewState(
            cameraPosition: initCamera
        ))
        _arcGISState = StateObject(wrappedValue: ArcGISMapViewState(
            mapDesignType: ArcGISDesign.OsmStandard,
            cameraPosition: initCamera
        ))
        _hereState = StateObject(wrappedValue: HereMapViewState(
            mapDesignType: HereMapDesign.NormalDay,
            cameraPosition: initCamera
        ))
        _tomTomState = StateObject(wrappedValue: TomTomMapViewState(
            mapDesignType: TomTomMapDesign.Standard,
            cameraPosition: initCamera
        ))
        _mapTilerState = StateObject(wrappedValue: MapTilerViewState(
            mapDesignType: MapTilerDesign.Streets,
            cameraPosition: initCamera
        ))
        _longdoState = StateObject(wrappedValue: LongdoViewState(
            mapDesignType: LongdoDesign.Normal,
            cameraPosition: initCamera
        ))
        _openMobileMapsState = StateObject(wrappedValue: OpenMobileMapsViewState(
            mapDesignType: OpenMobileMapsDesign.openStreetMap,
            cameraPosition: initCamera
        ))
        _mapplsState = StateObject(wrappedValue: MapplsViewState(
            mapDesignType: MapplsDesign.Default,
            cameraPosition: initCamera
        ))
    }

    var body: some View {
        DemoMapPageScaffold(provider: $provider, onToggleSidebar: onToggleSidebar) {
            ProjectedCoordinatesMapComponent(
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
            )
        }
    }
}

/// 投影座標（地図エンジンの座標系での x / y）を見るサンプル。**画面座標ではない。**
///
/// `MapViewHolder` の `toProjectedPoint` / `fromProjectedPoint` と `coordinateSystem` を
/// 使う。地図の中心と、タップした地点について、
///
/// - 地図エンジンの座標系での x / y
/// - その x / y を緯度経度へ戻した値と、元の地点とのずれ（メートル）
///
/// を出す。ずれが 0 に近ければ往復できている。
///
/// react-sdk / android の同ページと同じカメラ・同じ項目にしてある。
struct ProjectedCoordinatesMapComponent: View {
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

    @State private var center: GeoPoint?
    @State private var tapped: GeoPoint?
    // ホルダは地図が出来てから付く。読み出しを描画に任せると、付いた後に描き直しが
    // 起きず表示が取り残されるので、地図の通知で取り直して state に持つ。
    @State private var holder: AnyMapViewHolder?
    @State private var markers: [MarkerState] = []

    var body: some View {
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
                onMapClick: { point in
                    holder = activeHolder()
                    tapped = point
                    markers = Self.dropMarkers(at: point, holder: holder)
                },
                onCameraMove: { position in
                    holder = activeHolder()
                    center = GeoPoint.from(position: position.position)
                },
                onCameraMoveEnd: { position in
                    holder = activeHolder()
                    center = GeoPoint.from(position: position.position)
                }
            ) {
                var content = MapViewContent()
                content.markers = markers.map { Marker(state: $0) }
                return content
            }

            ProjectedCoordinatesInfoPanel(holder: holder, center: center, tapped: tapped)
                .padding(16)
                .frame(maxWidth: 380, alignment: .leading)
        }
        .onChange(of: provider) { _ in
            holder = nil
            center = nil
            tapped = nil
            markers = []
        }
    }

    /// タップした地点（赤）と、その投影座標を緯度経度へ戻した地点（青・小）に落とすマーカー。
    ///
    /// 投影と逆投影が合っていれば、青は赤のピン先に重なる。タップのたびに新しい
    /// マーカーにするので、Drop がそのつど再生される。同じ地点なら後から足した青が
    /// 手前に描かれる。青を小さくするのは `scale` ではなく `iconSize` で行う
    /// （android の同ページと同じ。`scale` は絵だけを縮めてピン先がアンカーからずれる）。
    private static func dropMarkers(at tapped: GeoPoint, holder: AnyMapViewHolder?) -> [MarkerState] {
        var result = [
            MarkerState(
                position: tapped,
                icon: DefaultMarkerIcon(fillColor: UIColor(red: 0.898, green: 0.224, blue: 0.208, alpha: 1), label: "T"),
                animation: .Drop
            ),
        ]
        if let projected = holder?.toProjectedPoint(tapped), let back = holder?.fromProjectedPoint(projected) {
            result.append(
                MarkerState(
                    position: back,
                    icon: DefaultMarkerIcon(
                        fillColor: UIColor(red: 0.118, green: 0.533, blue: 0.898, alpha: 1),
                        label: "P",
                        iconSize: 28
                    ),
                    animation: .Drop
                )
            )
        }
        return result
    }

    private func activeHolder() -> AnyMapViewHolder? {
        switch provider {
        case .googleMaps: return googleState.getMapViewHolder()
        case .mapLibre: return mapLibreState.getMapViewHolder()
        case .mapKit: return mapKitState.getMapViewHolder()
        case .mapbox: return mapboxState.getMapViewHolder()
        case .arcGIS, .arcGIS2D: return arcGISState.getMapViewHolder()
        case .here: return hereState.getMapViewHolder()
        case .tomTom: return tomTomState.getMapViewHolder()
        case .mapTiler: return mapTilerState.getMapViewHolder()
        case .longdo: return longdoState.getMapViewHolder()
        case .openMobileMaps: return openMobileMapsState.getMapViewHolder()
        case .mappls: return mapplsState.getMapViewHolder()
        }
    }
}

private struct ProjectedCoordinatesInfoPanel: View {
    let holder: AnyMapViewHolder?
    let center: GeoPoint?
    let tapped: GeoPoint?

    /// 取得できないときの表示。react / android の同ページと揃える。
    private static let unavailable = "Unavailable"

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Projected Coordinates")
                .font(.headline)
                .padding(.bottom, 6)
            infoLine("Tap the map to project the tapped point.")
            infoLine("Markers: red T = tapped, blue P = back from the projected point.")
            infoLine("Coordinate system: \(holder.map { Self.format($0.coordinateSystem) } ?? Self.unavailable)")
            projectionLines("Center", center)
            projectionLines("Tapped", tapped)
        }
        .padding(12)
        .background(Color(UIColor.systemBackground).opacity(0.95))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
    }

    /// 1 地点ぶん: 緯度経度、投影座標、戻した緯度経度と元とのずれ。
    @ViewBuilder
    private func projectionLines(_ label: String, _ point: GeoPoint?) -> some View {
        let projected = point.flatMap { holder?.toProjectedPoint($0) }
        let back = projected.flatMap { holder?.fromProjectedPoint($0) }
        infoLine("\(label): \(Self.format(point))")
        infoLine("  Projected: \(projected.map { String(format: "x=%.2f, y=%.2f", $0.x, $0.y) } ?? Self.unavailable)")
        if let point, let back {
            let error = Spherical.computeDistanceBetween(from: point, to: back)
            infoLine("  Back: \(Self.format(back)) (error \(String(format: "%.3f", error)) m)")
        } else {
            infoLine("  Back: \(Self.format(back))")
        }
    }

    private func infoLine(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static func format(_ system: MapCoordinateSystem) -> String {
        "\(system.code ?? "(engine-defined)") (\(system.unit.rawValue))"
    }

    private static func format(_ point: GeoPoint?) -> String {
        guard let point else { return unavailable }
        return point.toUrlValue(precision: 6)
    }
}
