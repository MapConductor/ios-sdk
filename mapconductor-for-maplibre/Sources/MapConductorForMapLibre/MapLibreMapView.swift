import Combine
import Foundation
import MapConductorCore
import MapLibre
import SwiftUI
import UIKit

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
        let mapContent = content()
        return ZStack {
            MapLibreMapViewRepresentable(
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
        // Prefer full-resolution rendering on Retina displays.
        // (MapLibre uses the view's pixel ratio for both tiles and symbols.)
        mapView.contentScaleFactor = UIScreen.main.scale
        mapView.layer.contentsScale = UIScreen.main.scale
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
            zoomLevel: state.cameraPosition.adjustedZoomForMapLibre(),
            direction: state.cameraPosition.bearing,
            animated: false
        )
        let initialCamera = mapView.camera
        initialCamera.pitch = state.cameraPosition.tilt
        mapView.setCamera(initialCamera, animated: false)

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
        uiView.contentScaleFactor = UIScreen.main.scale
        uiView.layer.contentsScale = UIScreen.main.scale
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
        private var groundImageController: MapLibreGroundImageController?
        private var rasterController: MapLibreRasterLayerController?
        private var circleController: MapLibreCircleController?
        private var polylineController: MapLibrePolylineController?
        private var polygonController: MapLibrePolygonController?
        private var infoBubbleController: InfoBubbleController?
        private var strategyMarkerController: StrategyMarkerController<
            MLNPointFeature,
            AnyMarkerRenderingStrategy<MLNPointFeature>,
            MapLibreMarkerRenderer
        >?
        private var strategyMarkerRenderer: MapLibreMarkerRenderer?
        private var strategyMarkerSubscriptions: [String: AnyCancellable] = [:]
        private var strategyMarkerStatesById: [String: MarkerState] = [:]
        private var latestStrategyStates: [MarkerState] = []
        private var isStyleLoaded = false

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

            let groundImageController = MapLibreGroundImageController(mapView: mapView)
            self.groundImageController = groundImageController

            let rasterController = MapLibreRasterLayerController(mapView: mapView)
            self.rasterController = rasterController

            let circleController = MapLibreCircleController(mapView: mapView)
            self.circleController = circleController

            let polylineController = MapLibrePolylineController(mapView: mapView)
            self.polylineController = polylineController

            let polygonController = MapLibrePolygonController(mapView: mapView)
            self.polygonController = polygonController
            if let style = mapView.style {
                groundImageController.onStyleLoaded(style)
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
            groundImageController?.unbind()
            groundImageController = nil
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
            strategyMarkerSubscriptions.values.forEach { $0.cancel() }
            strategyMarkerSubscriptions.removeAll()
            strategyMarkerStatesById.removeAll()
            latestStrategyStates.removeAll()
            strategyMarkerRenderer?.unbind()
            strategyMarkerRenderer = nil
            strategyMarkerController?.destroy()
            strategyMarkerController = nil
            isStyleLoaded = false
        }

        func updateContent(_ content: MapViewContent) {
            infoBubbleController?.syncInfoBubbles(content.infoBubbles)
            markerController?.syncMarkers(content.markers)
            updateStrategyRendering(content)
            groundImageController?.syncGroundImages(content.groundImages)
            rasterController?.syncRasterLayers(content.rasterLayers)
            circleController?.syncCircles(content.circles)
            polylineController?.syncPolylines(content.polylines)
            polygonController?.syncPolygons(content.polygons)
            infoBubbleController?.updateAllLayouts()
        }

        // MARK: - MLNMapViewDelegate

        func mapViewDidFinishLoadingMap(_ mapView: MLNMapView) {
            isStyleLoaded = true
            if let style = mapView.style {
                groundImageController?.onStyleLoaded(style)
                rasterController?.onStyleLoaded(style)
                polygonController?.onStyleLoaded(style)
                polylineController?.onStyleLoaded(style)
                circleController?.onStyleLoaded(style)
                markerController?.onStyleLoaded(style)
                strategyMarkerRenderer?.onStyleLoaded(style)
                if let strategyMarkerController, !latestStrategyStates.isEmpty {
                    Task { [weak self] in
                        guard let self else { return }
                        await strategyMarkerController.onCameraChanged(
                            mapCameraPosition: self.currentCameraPosition(from: mapView)
                        )
                        await strategyMarkerController.add(data: self.latestStrategyStates)
                    }
                }
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
            Task { [weak self] in
                await self?.strategyMarkerController?.onCameraChanged(mapCameraPosition: camera)
            }
            updateInfoBubbleLayouts()
        }

        func mapViewRegionIsChanging(_ mapView: MLNMapView) {
            let camera = currentCameraPosition(from: mapView)
            state.updateCameraPosition(camera)
            controller?.notifyCameraMove(camera)
            onCameraMove?(camera)
            // Removed async Task calls to prevent crashes
            // Geometry layers don't need to respond to camera changes
            Task { [weak self] in
                await self?.strategyMarkerController?.onCameraChanged(mapCameraPosition: camera)
            }
            updateInfoBubbleLayouts()
        }

        func mapView(_ mapView: MLNMapView, regionDidChangeAnimated animated: Bool) {
            let camera = currentCameraPosition(from: mapView)
            state.updateCameraPosition(camera)
            controller?.notifyCameraMoveEnd(camera)
            onCameraMoveEnd?(camera)
            // Removed async Task calls to prevent crashes
            // Geometry layers don't need to respond to camera changes
            Task { [weak self] in
                await self?.strategyMarkerController?.onCameraChanged(mapCameraPosition: camera)
            }
            updateInfoBubbleLayouts()
        }

        @objc func handleMapTap(_ recognizer: UITapGestureRecognizer) {
            guard let mapView = mapView, recognizer.state == .ended else { return }
            let point = recognizer.location(in: mapView)

            if markerController?.handleTap(at: point) == true {
                updateInfoBubbleLayouts()
                return
            }
            if handleStrategyTap(at: point) {
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
            if groundImageController?.handleTap(at: coordinate) == true {
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
            let visibleBounds = mapView.visibleCoordinateBounds
            let bounds = GeoRectBounds(
                southWest: GeoPoint(
                    latitude: visibleBounds.sw.latitude,
                    longitude: visibleBounds.sw.longitude,
                    altitude: 0
                ),
                northEast: GeoPoint(
                    latitude: visibleBounds.ne.latitude,
                    longitude: visibleBounds.ne.longitude,
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

        private func updateStrategyRendering(_ content: MapViewContent) {
            guard let mapView else { return }
            if let strategy = content.markerRenderingStrategy as? AnyMarkerRenderingStrategy<MLNPointFeature> {
                if strategyMarkerController == nil ||
                    strategyMarkerController?.markerManager !== strategy.markerManager {
                    strategyMarkerRenderer?.unbind()
                    let layer = MarkerLayer(
                        sourceId: "mapconductor-cluster-source-\(UUID().uuidString)",
                        layerId: "mapconductor-cluster-layer-\(UUID().uuidString)"
                    )
                    let renderer = MapLibreMarkerRenderer(
                        mapView: mapView,
                        markerManager: strategy.markerManager,
                        markerLayer: layer
                    )
                    strategyMarkerRenderer = renderer
                    let controller = StrategyMarkerController(strategy: strategy, renderer: renderer)
                    strategyMarkerController = controller
                    if let style = mapView.style {
                        renderer.onStyleLoaded(style)
                    }
                    Task { [weak self] in
                        guard let self else { return }
                        await controller.onCameraChanged(
                            mapCameraPosition: self.currentCameraPosition(from: mapView)
                        )
                    }
                }
                syncStrategyMarkers(content.markerRenderingMarkers)
            } else {
                strategyMarkerSubscriptions.values.forEach { $0.cancel() }
                strategyMarkerSubscriptions.removeAll()
                strategyMarkerStatesById.removeAll()
                latestStrategyStates.removeAll()
                strategyMarkerRenderer?.unbind()
                strategyMarkerRenderer = nil
                strategyMarkerController?.destroy()
                strategyMarkerController = nil
            }
        }

        private func syncStrategyMarkers(_ markers: [MarkerState]) {
            guard let controller = strategyMarkerController else { return }
            let newIds = Set(markers.map { $0.id })
            let oldIds = Set(strategyMarkerStatesById.keys)
            var shouldSyncList = newIds != oldIds

            var newStatesById: [String: MarkerState] = [:]
            for state in markers {
                if let existing = strategyMarkerStatesById[state.id], existing !== state {
                    strategyMarkerSubscriptions[state.id]?.cancel()
                    strategyMarkerSubscriptions.removeValue(forKey: state.id)
                    shouldSyncList = true
                }
                newStatesById[state.id] = state
            }
            strategyMarkerStatesById = newStatesById
            latestStrategyStates = markers

            let removedIds = oldIds.subtracting(newIds)
            for id in removedIds {
                strategyMarkerSubscriptions[id]?.cancel()
                strategyMarkerSubscriptions.removeValue(forKey: id)
            }

            if shouldSyncList && isStyleLoaded {
                Task { [weak self] in
                    guard let self else { return }
                    await controller.add(data: markers)
                }
            }

            for state in markers {
                subscribeToStrategyMarker(state)
            }
        }

        private func subscribeToStrategyMarker(_ state: MarkerState) {
            guard strategyMarkerSubscriptions[state.id] == nil else { return }
            strategyMarkerSubscriptions[state.id] = state.asFlow()
                .dropFirst() // Skip initial value to avoid triggering update on subscription
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    guard let self,
                          self.strategyMarkerStatesById[state.id] != nil else { return }
                    Task { [weak self] in
                        guard let self else { return }
                        await self.strategyMarkerController?.update(state: state)
                    }
                }
        }

        private func handleStrategyTap(at point: CGPoint) -> Bool {
            guard let markerId = strategyMarkerRenderer?.markerId(at: point),
                  let state = strategyMarkerController?.markerManager.getEntity(markerId)?.state,
                  state.clickable else { return false }
            strategyMarkerController?.dispatchClick(state)
            return true
        }

        private func geoPoint(at point: CGPoint, mapView: MLNMapView) -> GeoPoint? {
            guard !mapView.bounds.isEmpty else { return nil }
            let coordinate = mapView.convert(point, toCoordinateFrom: mapView)
            return GeoPoint(latitude: coordinate.latitude, longitude: coordinate.longitude, altitude: 0)
        }
    }
}
