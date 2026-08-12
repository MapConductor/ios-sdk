import GoogleMaps
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

/// android の StyledInfoBubblePage.kt / react の StyledInfoBubblePage.tsx と同一仕様:
/// マーカー 1 個と常時表示の InfoBubble を置き、パネルの 8 色スウォッチ 4 行
/// （バブル塗り / バブル枠線 / 文字 / マーカー）と 2 本のスライダー
/// （枠線幅・マーカースケール 0.5〜2.0、0.25 刻み）でスタイルを組み替える。
struct StyledInfoBubblePage: View {
    let onToggleSidebar: () -> Void

    init(onToggleSidebar: @escaping () -> Void = {}) {
        self.onToggleSidebar = onToggleSidebar
    }

    private static let startPosition = GeoPoint(latitude: 35.6812, longitude: 139.7671)

    /// 4 行で共有する 8 色。白と黒を含めておくと塗り＝白 / 文字＝黒の既定も同じ列で選べる。
    private static let palette: [Color] = [
        Color(red: 1.00, green: 1.00, blue: 1.00),
        Color(red: 0.07, green: 0.09, blue: 0.15),
        Color(red: 0.94, green: 0.27, blue: 0.27),
        Color(red: 0.98, green: 0.45, blue: 0.09),
        Color(red: 0.92, green: 0.70, blue: 0.03),
        Color(red: 0.13, green: 0.77, blue: 0.37),
        Color(red: 0.23, green: 0.51, blue: 0.96),
        Color(red: 0.66, green: 0.33, blue: 0.97),
    ]

    @State private var provider: MapProvider = MapProvider.initial()

    @State private var fillColor: Color = StyledInfoBubblePage.palette[0]
    @State private var strokeColor: Color = StyledInfoBubblePage.palette[1]
    @State private var fontColor: Color = StyledInfoBubblePage.palette[1]
    @State private var markerColor: Color = StyledInfoBubblePage.palette[2]
    @State private var strokeWidth: Double = 2.0
    @State private var markerScale: Double = 1.0

    @StateObject private var googleState = GoogleMapViewState(
        cameraPosition: MapCameraPosition(position: startPosition, zoom: 14)
    )
    @StateObject private var mapLibreState = MapLibreViewState(
        mapDesignType: MapLibreDesign.DemoTiles,
        cameraPosition: MapCameraPosition(position: startPosition, zoom: 14)
    )
    @StateObject private var mapKitState = MapKitViewState(
        mapDesignType: MapKitMapDesign.Standard,
        cameraPosition: MapCameraPosition(position: startPosition, zoom: 14)
    )
    @StateObject private var mapboxState = MapboxViewState(
        cameraPosition: MapCameraPosition(position: startPosition, zoom: 14)
    )
    @StateObject private var arcGISState = ArcGISMapViewState(
        mapDesignType: ArcGISDesign.OsmStandard,
        cameraPosition: MapCameraPosition(position: startPosition, zoom: 14)
    )
    @StateObject private var hereState = HereMapViewState(
        mapDesignType: HereMapDesign.NormalDay,
        cameraPosition: MapCameraPosition(position: startPosition, zoom: 14)
    )
    @StateObject private var tomTomState = TomTomMapViewState(
        mapDesignType: TomTomMapDesign.Standard,
        cameraPosition: MapCameraPosition(position: startPosition, zoom: 14)
    )
    @StateObject private var mapTilerState = MapTilerViewState(
        mapDesignType: MapTilerDesign.Streets,
        cameraPosition: MapCameraPosition(position: startPosition, zoom: 14)
    )
    @StateObject private var longdoState = LongdoViewState(
        mapDesignType: LongdoDesign.Normal,
        cameraPosition: MapCameraPosition(position: startPosition, zoom: 14)
    )
    @StateObject private var openMobileMapsState = OpenMobileMapsViewState(
        mapDesignType: OpenMobileMapsDesign.openStreetMap,
        cameraPosition: MapCameraPosition(position: startPosition, zoom: 14)
    )
    @StateObject private var mapplsState = MapplsViewState(
        mapDesignType: MapplsDesign.Default,
        cameraPosition: MapCameraPosition(position: startPosition, zoom: 14)
    )

    @StateObject private var markerState = MarkerState(
        position: startPosition,
        id: "styled-bubble-marker",
        icon: DefaultMarkerIcon(fillColor: UIColor(red: 0.94, green: 0.27, blue: 0.27, alpha: 1))
    )

    var body: some View {
        DemoMapPageScaffold(provider: $provider, onToggleSidebar: onToggleSidebar) {
            ZStack {
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
                    mapplsState: mapplsState
                ) {
                    Marker(state: markerState)
                    InfoBubble(
                        marker: markerState,
                        bubbleColor: fillColor,
                        borderColor: strokeColor,
                        borderWidth: strokeWidth,
                        contentPadding: 10,
                        cornerRadius: 6
                    ) {
                        Text("Custom Styled Bubble")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(fontColor)
                            .fixedSize()
                    }
                }

                controlPanel
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
        }
        .onChange(of: markerColor) { _ in updateMarkerIcon() }
        .onChange(of: markerScale) { _ in updateMarkerIcon() }
    }

    private func updateMarkerIcon() {
        markerState.icon = DefaultMarkerIcon(
            fillColor: UIColor(markerColor),
            scale: CGFloat(markerScale)
        )
    }

    private var controlPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            swatchRow(label: "Fill", selected: $fillColor)
            swatchRow(label: "Stroke", selected: $strokeColor)
            swatchRow(label: "Font", selected: $fontColor)
            swatchRow(label: "Marker", selected: $markerColor)
            Text(String(format: "Stroke Width: %.2f", strokeWidth))
                .font(.caption)
            Slider(value: $strokeWidth, in: 0.5...2.0, step: 0.25)
            Text(String(format: "Marker Scale: %.2f", markerScale))
                .font(.caption)
            Slider(value: $markerScale, in: 0.5...2.0, step: 0.25)
        }
        .padding(16)
        .background(Color(UIColor.systemBackground).opacity(0.95))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
        .padding(.leading, 16)
        .padding(.bottom, 16)
    }

    private func swatchRow(label: String, selected: Binding<Color>) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption)
                .frame(width: 52, alignment: .leading)
            ForEach(Array(Self.palette.enumerated()), id: \.offset) { _, color in
                Circle()
                    .fill(color)
                    .frame(width: 18, height: 18)
                    .overlay(
                        Circle().stroke(
                            selected.wrappedValue == color
                                ? Color(red: 0.15, green: 0.39, blue: 0.92)
                                : Color.black.opacity(0.25),
                            lineWidth: selected.wrappedValue == color ? 2 : 1
                        )
                    )
                    .onTapGesture { selected.wrappedValue = color }
            }
        }
    }
}
