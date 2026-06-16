import MapConductorCore
import MapConductorForArcGIS
import MapConductorForGoogleMaps
import MapConductorForHERE
import MapConductorForMapKit
import MapConductorForMapLibre
import MapConductorForMapbox
import MapConductorGeoJSON
import SwiftUI
import UIKit
import ZIPFoundation

struct GeoJSONLayerMapPage: View {
    let onToggleSidebar: () -> Void

    @State private var provider: MapProvider
    @StateObject private var layerState: GeoJSONLayerState

    @StateObject private var googleState: GoogleMapViewState
    @StateObject private var mapLibreState: MapLibreViewState
    @StateObject private var mapKitState: MapKitViewState
    @StateObject private var mapboxState: MapboxViewState
    @StateObject private var arcGISState: ArcGISMapViewState
    @StateObject private var hereState: HereMapViewState

    @State private var features: [GeoJSONFeature] = []
    @State private var selectedFeature: GeoJSONFeature?
    @State private var tappedPosition: GeoPoint?
    @State private var isDataLoading = true

    init(onToggleSidebar: @escaping () -> Void = {}) {
        self.onToggleSidebar = onToggleSidebar
        let cameraPosition = MapCameraPosition(
            position: GeoPoint(latitude: 35.68, longitude: 139.77),
            zoom: 13.0
        )
        let style = GeoJSONTileRenderer.LayerStyle(
            strokeColor: UIColor(red: 250.0 / 255.0, green: 36.0 / 255.0, blue: 29.0 / 255.0, alpha: 0.5),
            fillColor: UIColor(red: 250.0 / 255.0, green: 36.0 / 255.0, blue: 29.0 / 255.0, alpha: 0.0),
            strokeWidth: 6,
            pointRadius: 8
        )

        _provider = State(initialValue: .mapLibre)
        _layerState = StateObject(wrappedValue: GeoJSONLayerState(layerStyle: style))
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
                    onMapClick: handleMapClick
                ) {
                    GeoJSONLayer(state: layerState, features: features)

                    if let tappedPosition, let selectedFeature {
                        InfoBubble(position: tappedPosition) {
                            PropertyTable(properties: selectedFeature.properties)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("GeoJSON Layer")
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text("Tap a feature to inspect its properties.")
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
                    LoadingOverlay(message: "Parsing \(geoJSONAssetName).zip...")
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
        layerState.processClick(geoPoint: geoPoint)
    }

    private func loadFeaturesIfNeeded() {
        guard features.isEmpty else { return }
        isDataLoading = true
        Task {
            let loadedFeatures = await loadGeoJSONFeatures()
            await MainActor.run {
                features = loadedFeatures
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
                    PropertyRow(name: key, value: formatPropertyValue(properties[key]), isHeader: false)
                }
            }
        }
        .frame(width: 400)
        .frame(maxHeight: 300)
    }
}

private struct PropertyRow: View {
    let name: String
    let value: String
    let isHeader: Bool

    var body: some View {
        HStack(spacing: 0) {
            cell(name, width: 140)
            cell(value, width: 260)
        }
        .background(isHeader ? Color(UIColor.systemGray5) : Color.clear)
    }

    private func cell(_ text: String, width: CGFloat) -> some View {
        Text(text)
            .font(.caption)
            .foregroundColor(.black)
            .frame(width: width, alignment: .leading)
            .padding(8)
            .border(Color.gray, width: 1)
    }
}

private struct LoadingOverlay: View {
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading GeoJSON")
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

private func loadGeoJSONFeatures() async -> [GeoJSONFeature] {
    await Task.detached(priority: .userInitiated) {
        guard let url = Bundle.main.url(forResource: geoJSONAssetName, withExtension: "zip"),
              let archive = try? Archive(url: url, accessMode: .read, pathEncoding: nil) else {
            return []
        }

        for entry in archive where !entry.path.hasPrefix("__MACOSX") && entry.path.hasSuffix(".geojson") {
            do {
                var data = Data()
                _ = try archive.extract(entry) { chunk in
                    data.append(chunk)
                }
                return GeoJSONParser.parse(data: data)
            } catch {
                print("[GeoJSONLayerMapPage] Error loading \(entry.path): \(error)")
                return []
            }
        }

        return []
    }.value
}

private func formatPropertyValue(_ value: Any?) -> String {
    guard let value else { return "" }
    if JSONSerialization.isValidJSONObject(value),
       let data = try? JSONSerialization.data(withJSONObject: value),
       let json = String(data: data, encoding: .utf8) {
        return json
    }
    return String(describing: value)
}

private let geoJSONAssetName = "N02-22_GML"
