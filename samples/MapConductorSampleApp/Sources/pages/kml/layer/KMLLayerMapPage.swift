import MapConductorCore
import MapConductorForArcGIS
import MapConductorForGoogleMaps
import MapConductorForHERE
import MapConductorForTomTom
import MapConductorForMapTiler
import MapConductorForMapKit
import MapConductorForMapLibre
import MapConductorForMapbox
import MapConductorForLongdo
import MapConductorForOpenMobileMaps
import MapConductorForMappls
import MapConductorKML
import SwiftUI
import UIKit

struct KMLLayerMapPage: View {
    let onToggleSidebar: () -> Void

    @State private var provider: MapProvider
    @StateObject private var layerState: KMLLayerState

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

    @State private var features: [KMLFeature] = []
    @State private var selectedFeature: KMLFeature?
    @State private var tappedPosition: GeoPoint?
    @State private var isDataLoading = true

    init(onToggleSidebar: @escaping () -> Void = {}) {
        self.onToggleSidebar = onToggleSidebar
        let cameraPosition = MapCameraPosition(
            position: GeoPoint(latitude: 35.685, longitude: 139.76),
            zoom: 13.0
        )
        // Fallback style used when a placemark carries no KML <Style>.
        // android の KMLMapPage と同じ色（argb(255,250,36,29) / argb(96,250,36,29)）。
        let style = KMLTileRenderer.LayerStyle(
            strokeColor: UIColor(red: 250.0 / 255.0, green: 36.0 / 255.0, blue: 29.0 / 255.0, alpha: 1.0),
            fillColor: UIColor(red: 250.0 / 255.0, green: 36.0 / 255.0, blue: 29.0 / 255.0, alpha: 96.0 / 255.0),
            strokeWidth: 3,
            pointRadius: 8
        )

        // 他のページと同じく、選択中のプロバイダを引き継ぐ。
        _provider = State(initialValue: MapProvider.initial())
        _layerState = StateObject(wrappedValue: KMLLayerState(layerStyle: style))
        _googleState = StateObject(wrappedValue: GoogleMapViewState(cameraPosition: cameraPosition))
        _mapLibreState = StateObject(
            wrappedValue: MapLibreViewState(
                mapDesignType: MapLibreDesign.DemoTiles,
                cameraPosition: cameraPosition
            )
        )
        _mapKitState = StateObject(
            wrappedValue: MapKitViewState(
                mapDesignType: MapKitMapDesign.Standard,
                cameraPosition: cameraPosition
            )
        )
        _mapboxState = StateObject(wrappedValue: MapboxViewState(cameraPosition: cameraPosition))
        _arcGISState = StateObject(
            wrappedValue: ArcGISMapViewState(
                mapDesignType: ArcGISDesign.OsmStandard,
                cameraPosition: cameraPosition
            )
        )
        _hereState = StateObject(
            wrappedValue: HereMapViewState(
                mapDesignType: HereMapDesign.NormalDay,
                cameraPosition: cameraPosition
            )
        )
        _tomTomState = StateObject(
            wrappedValue: TomTomMapViewState(
                mapDesignType: TomTomMapDesign.Standard,
                cameraPosition: cameraPosition
            )
        )
        _mapTilerState = StateObject(
            wrappedValue: MapTilerViewState(
                mapDesignType: MapTilerDesign.Streets,
                cameraPosition: cameraPosition
            )
        )
        _longdoState = StateObject(
            wrappedValue: LongdoViewState(
                mapDesignType: LongdoDesign.Normal,
                cameraPosition: cameraPosition
            )
        )
        _openMobileMapsState = StateObject(
            wrappedValue: OpenMobileMapsViewState(
                mapDesignType: OpenMobileMapsDesign.openStreetMap,
                cameraPosition: cameraPosition
            )
        )
        _mapplsState = StateObject(
            wrappedValue: MapplsViewState(
                mapDesignType: MapplsDesign.Default,
                cameraPosition: cameraPosition
            )
        )
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
                    onMapClick: handleMapClick
                ) {
                    KMLLayer(state: layerState, features: features)

                    if let tappedPosition, let selectedFeature {
                        InfoBubble(
                            position: tappedPosition,
                            contentPadding: 12,
                            cornerRadius: 6,
                            tailSize: 10
                        ) {
                            PropertyTable(properties: selectedFeature.properties)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("KML Layer")
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text("Parsed from \(kmlAssetName). Tap a feature to inspect its properties.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(16)
                .background(Color(UIColor.systemBackground).opacity(0.95))
                .cornerRadius(12)
                .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
                .padding(.leading, 16)
                .padding(.bottom, 16)

                if isDataLoading {
                    LoadingOverlay(message: "Parsing \(kmlAssetName)...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            }
        }
        .onAppear {
            layerState.onClick = { feature, position in
                DispatchQueue.main.async {
                    selectedFeature = feature
                    tappedPosition = position
                }
            }
            loadFeaturesIfNeeded()
        }
    }

    private func handleMapClick(_ geoPoint: GeoPoint) {
        selectedFeature = nil
        tappedPosition = nil
        // ★ **選択中のプロバイダ**のズームを渡すこと（GeoJSONLayerMapPage の注意書きと同じ）。
        layerState.processClick(geoPoint: geoPoint, pixelTolerance: 12, zoom: activeCameraZoom)
    }

    /// 選択中のプロバイダのカメラのズーム。
    private var activeCameraZoom: Double {
        switch provider {
        case .googleMaps: return googleState.cameraPosition.zoom
        case .mapLibre: return mapLibreState.cameraPosition.zoom
        case .mapKit: return mapKitState.cameraPosition.zoom
        case .mapbox: return mapboxState.cameraPosition.zoom
        case .arcGIS, .arcGIS2D: return arcGISState.cameraPosition.zoom
        case .here: return hereState.cameraPosition.zoom
        case .tomTom: return tomTomState.cameraPosition.zoom
        case .mapTiler: return mapTilerState.cameraPosition.zoom
        case .longdo: return longdoState.cameraPosition.zoom
        case .openMobileMaps: return openMobileMapsState.cameraPosition.zoom

        case .mappls: return mapplsState.cameraPosition.zoom
        }
    }

    private func loadFeaturesIfNeeded() {
        guard features.isEmpty else { return }
        isDataLoading = true
        Task {
            let loaded = await loadKMLFeatures()
            await MainActor.run {
                features = loaded
                isDataLoading = false
            }
        }
    }
}

private struct PropertyTable: View {
    let properties: [String: Any]

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                PropertyRow(name: "Property", value: "Value", isHeader: true)

                ForEach(properties.keys.sorted(), id: \.self) { key in
                    PropertyRow(
                        name: key,
                        value: formatPropertyValue(properties[key]),
                        isHeader: false
                    )
                }
            }
        }
        // 320pt より広げない。iPhone の横幅では吹き出しが画面外へはみ出す。
        .frame(width: 320)
        .frame(maxHeight: 300)
    }
}

private struct PropertyRow: View {
    let name: String
    let value: String
    let isHeader: Bool

    var body: some View {
        HStack(spacing: 0) {
            cell(name, width: 110)
            cell(value, width: 210)
        }
        .background(isHeader ? Color(UIColor.systemGray5) : Color.clear)
    }

    private func cell(_ text: String, width: CGFloat) -> some View {
        Text(text)
            .font(.caption)
            .foregroundColor(.black)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(width: width, alignment: .leading)
            .frame(minHeight: 34, alignment: .leading)
            .border(Color.gray, width: 1)
    }
}

private struct LoadingOverlay: View {
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading KML")
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(24)
        .background(Color(UIColor.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
    }
}

private func loadKMLFeatures() async -> [KMLFeature] {
    await Task.detached(priority: .userInitiated) {
        guard let url = Bundle.main.url(forResource: "sample", withExtension: "kml"),
              let data = try? Data(contentsOf: url) else {
            print("[KMLLayerMapPage] \(kmlAssetName) was not found in the app bundle")
            return []
        }
        do {
            return try KMLParser.parse(data: data)
        } catch {
            print("[KMLLayerMapPage] Error parsing \(kmlAssetName): \(error)")
            return []
        }
    }.value
}

private func formatPropertyValue(_ value: Any?) -> String {
    guard let value, !(value is NSNull) else { return "" }
    return String(describing: value)
}

private let kmlAssetName = "sample.kml"
