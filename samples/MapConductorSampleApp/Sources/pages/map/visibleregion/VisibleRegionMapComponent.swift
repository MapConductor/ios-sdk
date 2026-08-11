import MapConductorCore
import MapConductorForArcGIS
import MapConductorForGoogleMaps
import MapConductorForHERE
import MapConductorForLongdo
import MapConductorForMapKit
import MapConductorForMapLibre
import MapConductorForMapTiler
import MapConductorForMapbox
import MapConductorForTomTom
import SwiftUI
import UIKit

/// 表示領域（VisibleRegion）を数値で見るサンプル。
///
/// react-sdk の `VisibleRegionPage.tsx` と**同じ内容・同じ並び**にしてある。
/// 3 プラットフォームを並べて見比べるページなので、項目が違うと比較にならない。
///
/// ## 地図にマーカーを置かない
///
/// 以前は角の 6 点にマーカーを立てていたが、react と揃えるにあたり外した。
/// このページで見たいのは**数値**であって、マーカーがあると
/// 「マーカーの位置が正しいか」という別の話が混ざる。
///
/// ## `onCameraMove` で受けること
///
/// `onCameraMoveEnd` にすると**動かし終わるまで数値が変わらない**。
/// react は動かしている最中も更新されるので、そちらへ揃える。
struct VisibleRegionMapComponent: View {
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

    let onCameraChanged: ((MapCameraPosition) -> Void)?

    @State private var cameraPosition: MapCameraPosition?

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
                onCameraMove: { position in
                    cameraPosition = position
                    onCameraChanged?(position)
                }
            ) {
                MapViewContent()
            }

            VisibleRegionInfoPanel(cameraPosition: cameraPosition)
                .padding(16)
                .frame(maxWidth: 350, alignment: .leading)
        }
    }
}

private struct VisibleRegionInfoPanel: View {
    let cameraPosition: MapCameraPosition?

    /// 取得できないときの表示。react の `Unavailable` と揃える。
    private static let unavailable = "Unavailable"

    var body: some View {
        let visibleRegion = cameraPosition?.visibleRegion
        let bounds = visibleRegion?.bounds

        VStack(alignment: .leading, spacing: 2) {
            Text("Visible Region")
                .font(.headline)
                .padding(.bottom, 6)
            infoLine("Move the map to update the current camera and visible region.")
            infoLine("Center: \(Self.format(cameraPosition?.position))")
            infoLine("Zoom: \(Self.format(cameraPosition?.zoom, digits: 2))")
            infoLine("Bearing: \(Self.format(cameraPosition?.bearing, digits: 1)) deg")
            infoLine("Tilt: \(Self.format(cameraPosition?.tilt, digits: 1)) deg")
            infoLine("Bounds: \(Self.format(bounds))")
            infoLine("Near Left: \(Self.format(visibleRegion?.nearLeft))")
            infoLine("Near Right: \(Self.format(visibleRegion?.nearRight))")
            infoLine("Far Left: \(Self.format(visibleRegion?.farLeft))")
            infoLine("Far Right: \(Self.format(visibleRegion?.farRight))")
        }
        .padding(12)
        .background(Color(UIColor.systemBackground).opacity(0.95))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
    }

    private func infoLine(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 座標の表示。`toUrlValue(5)` は react / android と同じ書式なので、
    /// 3 プラットフォームの数値をそのまま突き合わせられる。
    private static func format(_ point: (any GeoPointProtocol)?) -> String {
        guard let point else { return unavailable }
        return GeoPoint.from(position: point).toUrlValue(precision: 5)
    }

    private static func format(_ bounds: GeoRectBounds?) -> String {
        guard let bounds, !bounds.isEmpty else { return unavailable }
        return bounds.toUrlValue(precision: 5)
    }

    private static func format(_ value: Double?, digits: Int) -> String {
        guard let value else { return unavailable }
        return String(format: "%.\(digits)f", value)
    }
}
