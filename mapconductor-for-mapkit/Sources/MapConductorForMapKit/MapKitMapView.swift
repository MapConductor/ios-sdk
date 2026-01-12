import Combine
import MapKit
import MapConductorCore
import SwiftUI
import UIKit

public struct MapKitMapView: View {
    @ObservedObject private var state: MapKitViewState

    private let onMapLoaded: OnMapLoadedHandler<MapKitViewState>?
    private let onMapClick: OnMapEventHandler?
    private let onCameraMoveStart: OnCameraMoveHandler?
    private let onCameraMove: OnCameraMoveHandler?
    private let onCameraMoveEnd: OnCameraMoveHandler?
    private let content: () -> MapViewContent

    public init(
        state: MapKitViewState,
        onMapLoaded: OnMapLoadedHandler<MapKitViewState>? = nil,
        onMapClick: OnMapEventHandler? = nil,
        onCameraMoveStart: OnCameraMoveHandler? = nil,
        onCameraMove: OnCameraMoveHandler? = nil,
        onCameraMoveEnd: OnCameraMoveHandler? = nil,
        @MapViewContentBuilder content: @escaping () -> MapViewContent = { MapViewContent() }
    ) {
        self.state = state
        self.onMapLoaded = onMapLoaded
        self.onMapClick = onMapClick
        self.onCameraMoveStart = onCameraMoveStart
        self.onCameraMove = onCameraMove
        self.onCameraMoveEnd = onCameraMoveEnd
        self.content = content
    }

    public var body: some View {
        let mapContent = content()
        return ZStack {
            MapKitMapViewRepresentable(
                state: state,
                onMapLoaded: onMapLoaded,
                onMapClick: onMapClick,
                onCameraMoveStart: onCameraMoveStart,
                onCameraMove: onCameraMove,
                onCameraMoveEnd: onCameraMoveEnd,
                content: mapContent
            )
            ForEach(0..<mapContent.views.count, id: \.self) { index in
                mapContent.views[index]
            }
        }
    }
}

private struct MapKitMapViewRepresentable: UIViewRepresentable {
    @ObservedObject var state: MapKitViewState

    let onMapLoaded: OnMapLoadedHandler<MapKitViewState>?
    let onMapClick: OnMapEventHandler?
    let onCameraMoveStart: OnCameraMoveHandler?
    let onCameraMove: OnCameraMoveHandler?
    let onCameraMoveEnd: OnCameraMoveHandler?
    let content: MapViewContent

    func makeCoordinator() -> Coordinator {
        Coordinator(
            state: state,
            onMapLoaded: onMapLoaded,
            onMapClick: onMapClick,
            onCameraMoveStart: onCameraMoveStart,
            onCameraMove: onCameraMove,
            onCameraMoveEnd: onCameraMoveEnd
        )
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView(frame: .zero)
        mapView.mapType = state.mapDesignType.getValue()
        mapView.delegate = context.coordinator

        let camera = MKMapCamera(
            lookingAtCenter: CLLocationCoordinate2D(
                latitude: state.cameraPosition.position.latitude,
                longitude: state.cameraPosition.position.longitude
            ),
            fromDistance: altitudeFromZoom(state.cameraPosition.zoom, latitude: state.cameraPosition.position.latitude),
            pitch: state.cameraPosition.tilt,
            heading: state.cameraPosition.bearing
        )
        mapView.setCamera(camera, animated: false)

        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleMapTap(_:)))
        tapGesture.cancelsTouchesInView = false
        mapView.addGestureRecognizer(tapGesture)

        context.coordinator.mapView = mapView
        context.coordinator.bind(state: state, mapView: mapView)
        MCLog.map("MapKitMapView.makeUIView updateContent markers=\(content.markers.count) bubbles=\(content.infoBubbles.count)")
        context.coordinator.updateContent(content)
        return mapView
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {
        uiView.mapType = state.mapDesignType.getValue()
        MCLog.map("MapKitMapView.updateUIView updateContent markers=\(content.markers.count) bubbles=\(content.infoBubbles.count)")
        context.coordinator.updateContent(content)
    }

    static func dismantleUIView(_ uiView: MKMapView, coordinator: Coordinator) {
        coordinator.unbind()
        uiView.delegate = nil
    }

    private func altitudeFromZoom(_ zoom: Double, latitude: Double) -> CLLocationDistance {
        let earthCircumference: Double = 40075017.0
        let latitudeRadians = latitude * .pi / 180.0
        return earthCircumference * cos(latitudeRadians) / pow(2.0, zoom)
    }

    @MainActor
    final class Coordinator: NSObject, MKMapViewDelegate {
        private let state: MapKitViewState
        private let onMapLoaded: OnMapLoadedHandler<MapKitViewState>?
        private let onMapClick: OnMapEventHandler?
        private let onCameraMoveStart: OnCameraMoveHandler?
        private let onCameraMove: OnCameraMoveHandler?
        private let onCameraMoveEnd: OnCameraMoveHandler?

        weak var mapView: MKMapView?
        private var controller: MapKitViewController?

        private var didCallMapLoaded = false
        private var isRegionChanging = false

        init(
            state: MapKitViewState,
            onMapLoaded: OnMapLoadedHandler<MapKitViewState>?,
            onMapClick: OnMapEventHandler?,
            onCameraMoveStart: OnCameraMoveHandler?,
            onCameraMove: OnCameraMoveHandler?,
            onCameraMoveEnd: OnCameraMoveHandler?
        ) {
            self.state = state
            self.onMapLoaded = onMapLoaded
            self.onMapClick = onMapClick
            self.onCameraMoveStart = onCameraMoveStart
            self.onCameraMove = onCameraMove
            self.onCameraMoveEnd = onCameraMoveEnd
        }

        func bind(state: MapKitViewState, mapView: MKMapView) {
            let controller = MapKitViewController(mapView: mapView)
            self.controller = controller
            state.setController(controller)
            state.setMapViewHolder(controller.holder)
        }

        func unbind() {
            state.setController(nil)
            state.setMapViewHolder(nil)
            controller = nil
        }

        func updateContent(_ content: MapViewContent) {
            // For now, just log the content
            // Marker and overlay rendering will be implemented later
        }

        // MARK: - MKMapViewDelegate

        func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
            guard !isRegionChanging else { return }
            isRegionChanging = true
            let camera = currentCameraPosition(from: mapView)
            controller?.notifyCameraMoveStart(camera)
            onCameraMoveStart?(camera)
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            let camera = currentCameraPosition(from: mapView)
            state.updateCameraPosition(camera)
            controller?.notifyCameraMoveEnd(camera)
            onCameraMoveEnd?(camera)
            isRegionChanging = false

            if !didCallMapLoaded {
                didCallMapLoaded = true
                onMapLoaded?(state)
            }
        }

        @objc func handleMapTap(_ recognizer: UITapGestureRecognizer) {
            guard let mapView = mapView, recognizer.state == .ended else { return }
            let point = recognizer.location(in: mapView)
            let coordinate = mapView.convert(point, toCoordinateFrom: mapView)
            let geoPoint = GeoPoint(latitude: coordinate.latitude, longitude: coordinate.longitude, altitude: 0)
            controller?.notifyMapClick(geoPoint)
            onMapClick?(geoPoint)
        }

        // MARK: - Helper Methods

        private func currentCameraPosition(from mapView: MKMapView) -> MapConductorCore.MapCameraPosition {
            // Calculate visible region bounds
            let visibleRect = mapView.visibleMapRect
            let neMapPoint = MKMapPoint(x: visibleRect.maxX, y: visibleRect.minY)
            let swMapPoint = MKMapPoint(x: visibleRect.minX, y: visibleRect.maxY)
            let neCoordinate = neMapPoint.coordinate
            let swCoordinate = swMapPoint.coordinate

            let bounds = GeoRectBounds(
                southWest: GeoPoint(
                    latitude: swCoordinate.latitude,
                    longitude: swCoordinate.longitude,
                    altitude: 0
                ),
                northEast: GeoPoint(
                    latitude: neCoordinate.latitude,
                    longitude: neCoordinate.longitude,
                    altitude: 0
                )
            )

            let visibleRegion = VisibleRegion(
                bounds: bounds,
                nearLeft: geoPoint(at: CGPoint(x: 0, y: mapView.bounds.maxY), mapView: mapView),
                nearRight: geoPoint(at: CGPoint(x: mapView.bounds.maxX, y: mapView.bounds.maxY), mapView: mapView),
                farLeft: geoPoint(at: CGPoint(x: 0, y: 0), mapView: mapView),
                farRight: geoPoint(at: CGPoint(x: mapView.bounds.maxX, y: 0), mapView: mapView)
            )

            return mapView.toMapCameraPosition(visibleRegion: visibleRegion)
        }

        private func geoPoint(at point: CGPoint, mapView: MKMapView) -> GeoPoint? {
            guard !mapView.bounds.isEmpty else { return nil }
            let coordinate = mapView.convert(point, toCoordinateFrom: mapView)
            return GeoPoint(latitude: coordinate.latitude, longitude: coordinate.longitude, altitude: 0)
        }
    }
}
