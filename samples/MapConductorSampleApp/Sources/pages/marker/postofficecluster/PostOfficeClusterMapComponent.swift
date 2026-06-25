import GoogleMaps
import MapConductorCore
import MapConductorForGoogleMaps
import MapConductorForMapLibre
import MapConductorForMapKit
import MapConductorForMapbox
import MapConductorForArcGIS
import MapConductorForHERE
import MapConductorMarkerCluster
import MapKit
import MapLibre
import SwiftUI
import UIKit

struct PostOfficeClusterMapComponent: View {
    @Binding var provider: MapProvider
    @ObservedObject var googleState: GoogleMapViewState
    @ObservedObject var mapLibreState: MapLibreViewState
    @ObservedObject var mapKitState: MapKitViewState
    @ObservedObject var mapboxState: MapboxViewState
    @ObservedObject var arcGISState: ArcGISMapViewState
    @ObservedObject var hereState: HereMapViewState

    let markers: [MarkerState]
    let selectedMarker: MarkerState?
    let onMapClick: (GeoPoint) -> Void
    let onInfoClick: ((PostOffice) -> Void)?

    @StateObject private var googleGroupState: MarkerClusterGroupState<GoogleMapActualMarker>
    @StateObject private var mapLibreGroupState: MarkerClusterGroupState<MapLibreActualMarker>
    @StateObject private var mapKitGroupState: MarkerClusterGroupState<MapKitActualMarker>
    @StateObject private var mapboxGroupState: MarkerClusterGroupState<MapboxActualMarker>
    @StateObject private var hereGroupState: MarkerClusterGroupState<HereActualMarker>
    @StateObject private var arcGISGroupState: MarkerClusterGroupState<ArcGISActualMarker>

    init(
        provider: Binding<MapProvider>,
        googleState: GoogleMapViewState,
        mapLibreState: MapLibreViewState,
        mapKitState: MapKitViewState,
        mapboxState: MapboxViewState,
        arcGISState: ArcGISMapViewState,
        hereState: HereMapViewState,
        markers: [MarkerState],
        selectedMarker: MarkerState?,
        onMapClick: @escaping (GeoPoint) -> Void,
        onInfoClick: ((PostOffice) -> Void)? = nil
    ) {
        self._provider = provider
        self.googleState = googleState
        self.mapLibreState = mapLibreState
        self.mapKitState = mapKitState
        self.mapboxState = mapboxState
        self.arcGISState = arcGISState
        self.hereState = hereState
        self.markers = markers
        self.selectedMarker = selectedMarker
        self.onMapClick = onMapClick
        self.onInfoClick = onInfoClick

        // Android default is 90 DIP.
        let radiusPt = 75 * UIScreen.main.scale

        let clusterIconImage: UIImage? = {
            guard let url = Bundle.main.url(forResource: "cluster_red", withExtension: "png"),
                  let data = try? Data(contentsOf: url),
                  let image = UIImage(data: data) else {
                return nil
            }
            return image
        }()
        let clusterIconProvider: (Int) -> MarkerIconProtocol = { count -> MarkerIconProtocol in
            if let image = clusterIconImage {
                return Self.makeClusterIcon(backgroundImage: image, count: count)
            }
            return DefaultMarkerIcon(label: String(count))
        }

        self._googleGroupState = StateObject(
            wrappedValue: MarkerClusterGroupState<GoogleMapActualMarker>(
                clusterRadiusPx: radiusPt,
                minClusterSize: 3,
                clusterIconProvider: clusterIconProvider,
                enableZoomAnimation: true,
                enablePanAnimation: true,
            )
        )
        self._mapLibreGroupState = StateObject(
            wrappedValue: MarkerClusterGroupState<MapLibreActualMarker>(
                clusterRadiusPx: radiusPt,
                minClusterSize: 3,
                clusterIconProvider: clusterIconProvider,
                enableZoomAnimation: true,
                enablePanAnimation: true,
            )
        )
        self._mapKitGroupState = StateObject(
            wrappedValue: MarkerClusterGroupState<MapKitActualMarker>(
                clusterRadiusPx: radiusPt,
                minClusterSize: 3,
                clusterIconProvider: clusterIconProvider,
                enableZoomAnimation: true,
                enablePanAnimation: true,
            )
        )
        self._mapboxGroupState = StateObject(
            wrappedValue: MarkerClusterGroupState<MapboxActualMarker>(
                clusterRadiusPx: radiusPt,
                minClusterSize: 3,
                clusterIconProvider: clusterIconProvider,
                enableZoomAnimation: true,
                enablePanAnimation: true,
            )
        )
        self._hereGroupState = StateObject(
            wrappedValue: MarkerClusterGroupState<HereActualMarker>(
                clusterRadiusPx: radiusPt,
                minClusterSize: 3,
                clusterIconProvider: clusterIconProvider,
                enableZoomAnimation: true,
                enablePanAnimation: true,
                debugHullPolygons: false,
            )
        )
        self._arcGISGroupState = StateObject(
            wrappedValue: MarkerClusterGroupState<ArcGISActualMarker>(
                clusterRadiusPx: radiusPt,
                minClusterSize: 3,
                clusterIconProvider: clusterIconProvider,
                enableZoomAnimation: true,
                enablePanAnimation: true,
            )
        )
    }

    var body: some View {
        SampleMapView(
            provider: $provider,
            googleState: googleState,
            mapLibreState: mapLibreState,
            mapKitState: mapKitState,
            mapboxState: mapboxState,
            arcGISState: arcGISState,
            hereState: hereState,
            onMapClick: onMapClick
        ) {
            clusterLayer()

            if let marker = selectedMarker, let postOffice = marker.extra as? PostOffice {
                InfoBubble(marker: marker) {
                    PostOfficeInfoView(info: postOffice, onClick: onInfoClick)
                }
            }
        }
    }

    @MapViewContentBuilder
    private func clusterLayer() -> MapViewContent {
        if provider == .googleMaps {
            MarkerClusterGroup(state: googleGroupState) {
                markerItems()
            }
        } else if provider == .mapKit {
            MarkerClusterGroup(state: mapKitGroupState) {
                markerItems()
            }
        } else if provider == .mapLibre {
            MarkerClusterGroup(state: mapLibreGroupState) {
                markerItems()
            }
        } else if provider == .mapbox {
            MarkerClusterGroup(state: mapboxGroupState) {
                markerItems()
            }
        } else if provider == .here {
            MarkerClusterGroup(state: hereGroupState) {
                markerItems()
            }
        } else if provider == .arcGIS {
            MarkerClusterGroup(state: arcGISGroupState) {
                markerItems()
            }
        }
    }

    @MapViewContentBuilder
    private func markerItems() -> MapViewContent {
        for markerState in markers {
            Marker(state: markerState)
        }
    }

    private static let clusterIconSize = DefaultMarkerIcon.defaultIconSize
    private static let clusterLabelFontSize: CGFloat = 16.0
    private static let clusterLabelRect = CGRect(x: 0.03, y: 0.04, width: 0.94, height: 0.32)
    private static let clusterIconCache = ClusterIconLRUCache(capacity: 128)

    private static func makeClusterIcon(backgroundImage: UIImage, count: Int) -> BitmapIcon {
        let labelText = clusterCountLabel(for: count)
        if let cachedIcon = clusterIconCache.value(forKey: labelText) {
            return cachedIcon
        }

        let size = CGSize(width: clusterIconSize, height: clusterIconSize)
        let labelRect = CGRect(
            x: size.width * clusterLabelRect.minX,
            y: size.height * clusterLabelRect.minY,
            width: size.width * clusterLabelRect.width,
            height: size.height * clusterLabelRect.height
        )
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = UIScreen.main.scale

        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            backgroundImage.draw(in: CGRect(origin: .zero, size: size))

            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center
            paragraphStyle.lineBreakMode = .byClipping

            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: clusterLabelFontSize),
                .foregroundColor: UIColor.white,
                .paragraphStyle: paragraphStyle
            ]
            let label = labelText as NSString
            let labelSize = label.size(withAttributes: attributes)
            let textRect = CGRect(
                x: labelRect.minX,
                y: labelRect.midY - labelSize.height / 2.0,
                width: labelRect.width,
                height: labelSize.height
            )
            label.draw(in: textRect, withAttributes: attributes)
        }

        let icon = BitmapIcon(
            bitmap: image,
            anchor: CGPoint(x: 0.5, y: 0.5),
            size: size,
            iconSize: clusterIconSize,
            infoAnchor: CGPoint(x: 0.5, y: 0.5)
        )
        clusterIconCache.insert(icon, forKey: labelText)
        return icon
    }

    private static func clusterCountLabel(for count: Int) -> String {
        if count > 1_000 {
            return "1k+"
        }
        if count > 200 {
            return "200+"
        }
        if count > 100 {
            return "100+"
        }
        return String(count)
    }

    private final class ClusterIconLRUCache {
        private let capacity: Int
        private var storage: [String: BitmapIcon] = [:]
        private var recentlyUsedKeys: [String] = []
        private let lock = NSLock()

        init(capacity: Int) {
            self.capacity = max(1, capacity)
        }

        func value(forKey key: String) -> BitmapIcon? {
            lock.lock()
            defer { lock.unlock() }

            guard let value = storage[key] else {
                return nil
            }
            markRecentlyUsed(key)
            return value
        }

        func insert(_ value: BitmapIcon, forKey key: String) {
            lock.lock()
            defer { lock.unlock() }

            storage[key] = value
            markRecentlyUsed(key)
            while recentlyUsedKeys.count > capacity, let leastRecentlyUsedKey = recentlyUsedKeys.first {
                recentlyUsedKeys.removeFirst()
                storage.removeValue(forKey: leastRecentlyUsedKey)
            }
        }

        private func markRecentlyUsed(_ key: String) {
            recentlyUsedKeys.removeAll { $0 == key }
            recentlyUsedKeys.append(key)
        }
    }
}
