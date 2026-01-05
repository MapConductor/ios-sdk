import Combine
import Foundation
import MapConductorCore
import MapLibre
import SwiftUI
import UIKit

private let mapLibreCameraZoomAdjustValue = 1.0

public struct MapLibreMapView: View {
    @ObservedObject private var state: MapLibreViewState

    private let onMapLoaded: OnMapLoadedHandler<MapLibreViewState>?
    private let onMapClick: OnMapEventHandler?
    private let onCameraMoveStart: OnCameraMoveHandler?
    private let onCameraMove: OnCameraMoveHandler?
    private let onCameraMoveEnd: OnCameraMoveHandler?
    private let content: () -> MapViewContent

    public init(
        state: MapLibreViewState,
        onMapLoaded: OnMapLoadedHandler<MapLibreViewState>? = nil,
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
        MapLibreMapViewRepresentable(
            state: state,
            onMapLoaded: onMapLoaded,
            onMapClick: onMapClick,
            onCameraMoveStart: onCameraMoveStart,
            onCameraMove: onCameraMove,
            onCameraMoveEnd: onCameraMoveEnd,
            content: content()
        )
    }
}

private struct MapLibreMapViewRepresentable: UIViewRepresentable {
    @ObservedObject var state: MapLibreViewState

    let onMapLoaded: OnMapLoadedHandler<MapLibreViewState>?
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

    func makeUIView(context: Context) -> MLNMapView {
        let mapView = MLNMapView(frame: .zero)
        if let styleURL = URL(string: state.mapDesignType.styleJsonURL) {
            mapView.styleURL = styleURL
        }
        mapView.prefetchesTiles = false
        mapView.tileCacheEnabled = false
        mapView.delegate = context.coordinator
        mapView.setCenter(
            CLLocationCoordinate2D(
                latitude: state.cameraPosition.position.latitude,
                longitude: state.cameraPosition.position.longitude
            ),
            zoomLevel: max(state.cameraPosition.zoom - mapLibreCameraZoomAdjustValue, 0.0),
            animated: false
        )
        mapView.camera.heading = state.cameraPosition.bearing
        mapView.camera.pitch = state.cameraPosition.tilt

        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleMapTap(_:)))
        tapGesture.cancelsTouchesInView = false
        mapView.addGestureRecognizer(tapGesture)

        let longPressGesture = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleMarkerLongPress(_:))
        )
        longPressGesture.minimumPressDuration = 0.2
        mapView.addGestureRecognizer(longPressGesture)

        context.coordinator.attachInfoBubbleContainer(to: mapView)
        context.coordinator.mapView = mapView
        context.coordinator.bind(state: state, mapView: mapView)
        // Ensure overlay controllers subscribe immediately (before the first updateUIView),
        // so early UI actions (e.g. tapping animation buttons) are not missed.
        MCLog.map("MapLibreMapView.makeUIView updateContent markers=\(content.markers.count) bubbles=\(content.infoBubbles.count)")
        context.coordinator.updateContent(content)
        context.coordinator.updateInfoBubbleLayouts()
        return mapView
    }

    func updateUIView(_ uiView: MLNMapView, context: Context) {
        if let styleURL = URL(string: state.mapDesignType.styleJsonURL),
           uiView.styleURL != styleURL {
            uiView.styleURL = styleURL
        }
        MCLog.map("MapLibreMapView.updateUIView updateContent markers=\(content.markers.count) bubbles=\(content.infoBubbles.count)")
        context.coordinator.updateContent(content)
        context.coordinator.updateInfoBubbleLayouts()
    }

    static func dismantleUIView(_ uiView: MLNMapView, coordinator: Coordinator) {
        coordinator.unbind()
        uiView.delegate = nil
    }

    @MainActor
    final class Coordinator: NSObject, MLNMapViewDelegate {
        private let state: MapLibreViewState
        private let onMapLoaded: OnMapLoadedHandler<MapLibreViewState>?
        private let onMapClick: OnMapEventHandler?
        private let onCameraMoveStart: OnCameraMoveHandler?
        private let onCameraMove: OnCameraMoveHandler?
        private let onCameraMoveEnd: OnCameraMoveHandler?

        weak var mapView: MLNMapView?
        private var controller: MapLibreViewController?
        private var markerController: MapLibreMarkerController?
        private var rasterController: MapLibreRasterLayerController?
        private var circleController: MapLibreCircleController?
        private var polylineController: MapLibrePolylineController?
        private var polygonController: MapLibrePolygonController?
        private var infoBubbleController: InfoBubbleController?

        private var didCallMapLoaded = false
        private let infoBubbleContainer = UIView()

        init(
            state: MapLibreViewState,
            onMapLoaded: OnMapLoadedHandler<MapLibreViewState>?,
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

        func bind(state: MapLibreViewState, mapView: MLNMapView) {
            let controller = MapLibreViewController(mapView: mapView)
            self.controller = controller
            state.setController(controller)
            state.setMapViewHolder(controller.holder)

            let markerController = MapLibreMarkerController(mapView: mapView) { [weak self] id in
                self?.infoBubbleController?.updateInfoBubblePosition(for: id)
            }
            self.markerController = markerController

            let rasterController = MapLibreRasterLayerController(mapView: mapView)
            self.rasterController = rasterController

            let circleController = MapLibreCircleController(mapView: mapView)
            self.circleController = circleController

            let polylineController = MapLibrePolylineController(mapView: mapView)
            self.polylineController = polylineController

            let polygonController = MapLibrePolygonController(mapView: mapView)
            self.polygonController = polygonController
            if let style = mapView.style {
                rasterController.onStyleLoaded(style)
                polygonController.onStyleLoaded(style)
                polylineController.onStyleLoaded(style)
                circleController.onStyleLoaded(style)
                markerController.onStyleLoaded(style)
            }

            let infoBubbleController = InfoBubbleController(
                mapView: mapView,
                container: infoBubbleContainer,
                markerController: markerController
            )
            self.infoBubbleController = infoBubbleController
        }

        func unbind() {
            state.setController(nil)
            state.setMapViewHolder(nil)
            controller = nil
            markerController?.unbind()
            markerController = nil
            rasterController?.unbind()
            rasterController = nil
            circleController?.unbind()
            circleController = nil
            polylineController?.unbind()
            polylineController = nil
            polygonController?.unbind()
            polygonController = nil
            infoBubbleController?.unbind()
            infoBubbleController = nil
        }

        func updateContent(_ content: MapViewContent) {
            infoBubbleController?.syncInfoBubbles(content.infoBubbles)
            markerController?.syncMarkers(content.markers)
            rasterController?.syncRasterLayers(content.rasterLayers)
            circleController?.syncCircles(content.circles)
            polylineController?.syncPolylines(content.polylines)
            polygonController?.syncPolygons(content.polygons)
            infoBubbleController?.updateAllLayouts()
        }

        // MARK: - MLNMapViewDelegate

        func mapViewDidFinishLoadingMap(_ mapView: MLNMapView) {
            if let style = mapView.style {
                rasterController?.onStyleLoaded(style)
                polygonController?.onStyleLoaded(style)
                polylineController?.onStyleLoaded(style)
                circleController?.onStyleLoaded(style)
                markerController?.onStyleLoaded(style)
            }
            if !didCallMapLoaded {
                didCallMapLoaded = true
                onMapLoaded?(state)
            }
            updateInfoBubbleLayouts()
        }

        func mapView(_ mapView: MLNMapView, regionWillChangeAnimated animated: Bool) {
            let camera = currentCameraPosition(from: mapView)
            controller?.notifyCameraMoveStart(camera)
            onCameraMoveStart?(camera)
            // Removed async Task calls to prevent crashes
            // Geometry layers don't need to respond to camera changes
            updateInfoBubbleLayouts()
        }

        func mapViewRegionIsChanging(_ mapView: MLNMapView) {
            let camera = currentCameraPosition(from: mapView)
            state.updateCameraPosition(camera)
            controller?.notifyCameraMove(camera)
            onCameraMove?(camera)
            // Removed async Task calls to prevent crashes
            // Geometry layers don't need to respond to camera changes
            updateInfoBubbleLayouts()
        }

        func mapView(_ mapView: MLNMapView, regionDidChangeAnimated animated: Bool) {
            let camera = currentCameraPosition(from: mapView)
            state.updateCameraPosition(camera)
            controller?.notifyCameraMoveEnd(camera)
            onCameraMoveEnd?(camera)
            // Removed async Task calls to prevent crashes
            // Geometry layers don't need to respond to camera changes
            updateInfoBubbleLayouts()
        }

        @objc func handleMapTap(_ recognizer: UITapGestureRecognizer) {
            guard let mapView = mapView, recognizer.state == .ended else { return }
            let point = recognizer.location(in: mapView)

            if markerController?.handleTap(at: point) == true {
                updateInfoBubbleLayouts()
                return
            }

            let coordinate = mapView.convert(point, toCoordinateFrom: mapView)
            if circleController?.handleTap(at: coordinate) == true {
                updateInfoBubbleLayouts()
                return
            }
            if polylineController?.handleTap(at: coordinate) == true {
                updateInfoBubbleLayouts()
                return
            }
            if polygonController?.handleTap(at: coordinate) == true {
                updateInfoBubbleLayouts()
                return
            }
            let geoPoint = GeoPoint(latitude: coordinate.latitude, longitude: coordinate.longitude, altitude: 0)
            controller?.notifyMapClick(geoPoint)
            onMapClick?(geoPoint)
        }

        @objc func handleMarkerLongPress(_ recognizer: UILongPressGestureRecognizer) {
            markerController?.handleLongPress(recognizer)
            updateInfoBubbleLayouts()
        }

        // MARK: - Helper Methods

        private func currentCameraPosition(from mapView: MLNMapView) -> MapCameraPosition {
            MapCameraPosition(
                position: GeoPoint(
                    latitude: mapView.centerCoordinate.latitude,
                    longitude: mapView.centerCoordinate.longitude,
                    altitude: 0
                ),
                zoom: mapView.zoomLevel + mapLibreCameraZoomAdjustValue,
                bearing: mapView.camera.heading,
                tilt: mapView.camera.pitch
            )
        }

        fileprivate func attachInfoBubbleContainer(to mapView: MLNMapView) {
            guard infoBubbleContainer.superview !== mapView else { return }
            infoBubbleContainer.backgroundColor = .clear
            infoBubbleContainer.isUserInteractionEnabled = false
            infoBubbleContainer.frame = mapView.bounds
            infoBubbleContainer.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            mapView.addSubview(infoBubbleContainer)
        }

        fileprivate func updateInfoBubbleLayouts() {
            infoBubbleController?.updateAllLayouts()
        }
    }
}
