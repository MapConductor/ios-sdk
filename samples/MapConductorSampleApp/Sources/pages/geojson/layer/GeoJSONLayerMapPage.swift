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
import MapConductorGeoJSON
import SwiftUI
import UIKit

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
    @StateObject private var tomTomState: TomTomMapViewState
    @StateObject private var mapTilerState: MapTilerViewState
    @StateObject private var longdoState: LongdoViewState
    @StateObject private var openMobileMapsState: OpenMobileMapsViewState

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
                    onMapClick: handleMapClick
                ) {
                    GeoJSONLayer(state: layerState, features: features)

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
        layerState.processClick(geoPoint: geoPoint, pixelTolerance: 10, zoom: googleState.cameraPosition.zoom)
    }

    private func loadFeaturesIfNeeded() {
        guard features.isEmpty else { return }
        isDataLoading = true
        Task {
            let loadedData = await loadGeoJSONLayerData()
            await MainActor.run {
                if let loadedData {
                    layerState.styleProvider = loadedData.styleProvider
                    features = loadedData.features
                }
                isDataLoading = false
            }
        }
    }
}

private struct PropertyTable: View {
    let properties: [String: Any]

    /// 国土数値情報の鉄道データ（N02）の属性名。
    ///
    /// 生の `N02_001` のままだと何の値か分からないので、吹き出しでは名前に置き換える。
    /// react / android と**同じ文言**にしてある（3 プラットフォームを並べて見比べるサンプルなので、
    /// ここが違うと同じ地物を選んでいるのか判断できない）。
    ///
    /// ここに無いキーは生のキー名をそのまま出す。データ側に属性が増えても表から消えないように。
    private static let labels = [
        "N02_001": (ja: "鉄道区分", en: "Railway category"),
        "N02_002": (ja: "事業者区分", en: "Business category"),
        "N02_003": (ja: "路線名", en: "Railway name"),
        "N02_004": (ja: "運営会社", en: "Railway company"),
    ]

    /// 値の英語表記が入っている属性の接尾辞。
    ///
    /// geojson 側が `N02_003`（路線名）に対して `N02_003_en` を持っている。アプリに
    /// 対訳表を置くと 4 プラットフォーム分そろえる羽目になるので、データに持たせてある。
    private static let englishSuffix = "_en"

    private var isJapanese: Bool { Locale.current.language.languageCode?.identifier == "ja" }

    /// 端末の言語が日本語なら日本語、それ以外は英語で出す。
    /// `_en` の行そのものは出さない（同じ項目が 2 行に増えてしまうため）。
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                PropertyRow(
                    name: isJapanese ? "プロパティ" : "Property",
                    value: isJapanese ? "値" : "Value",
                    isHeader: true
                )

                ForEach(properties.keys.sorted().filter { !$0.hasSuffix(Self.englishSuffix) }, id: \.self) { key in
                    PropertyRow(
                        name: Self.labels[key].map { isJapanese ? $0.ja : $0.en } ?? key,
                        value: formatPropertyValue(value(for: key)),
                        isHeader: false
                    )
                }
            }
        }
        // 320pt より広げない。iPhone の横幅では吹き出しが画面外へはみ出す。
        .frame(width: 320)
        .frame(maxHeight: 300)
    }

    private func value(for key: String) -> Any? {
        if isJapanese { return properties[key] }
        return properties[key + Self.englishSuffix] ?? properties[key]
    }
}

private struct PropertyRow: View {
    let name: String
    let value: String
    let isHeader: Bool

    var body: some View {
        HStack(spacing: 0) {
            cell(name, width: 160)
            cell(value, width: 160)
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

private func loadGeoJSONLayerData() async -> ExampleGeoJSONLayerData? {
    await Task.detached(priority: .userInitiated) {
        do {
            return try ExampleGeoJSONLayerLoader().load(assetName: geoJSONAssetName)
        } catch {
            print("[GeoJSONLayerMapPage] Error loading \(geoJSONAssetName).zip: \(error)")
            return nil
        }
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
