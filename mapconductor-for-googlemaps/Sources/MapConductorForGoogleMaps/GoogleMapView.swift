import Combine
import GoogleMaps
import MapConductorCore
import SwiftUI
import UIKit

public struct GoogleMapView: View {
    @ObservedObject private var state: GoogleMapViewState

    private let onMapLoaded: OnMapLoadedHandler<GoogleMapViewState>?
    private let onMapClick: OnMapEventHandler?
    private let onCameraMoveStart: OnCameraMoveHandler?
    private let onCameraMove: OnCameraMoveHandler?
    private let onCameraMoveEnd: OnCameraMoveHandler?
    private let sdkInitialize: (() -> Void)?
    private let content: () -> MapViewContent

    public init(
        state: GoogleMapViewState,
        onMapLoaded: OnMapLoadedHandler<GoogleMapViewState>? = nil,
        onMapClick: OnMapEventHandler? = nil,
        onCameraMoveStart: OnCameraMoveHandler? = nil,
        onCameraMove: OnCameraMoveHandler? = nil,
        onCameraMoveEnd: OnCameraMoveHandler? = nil,
        sdkInitialize: (() -> Void)? = nil,
        @MapViewContentBuilder content: @escaping () -> MapViewContent = { MapViewContent() }
    ) {
        self.state = state
        self.onMapLoaded = onMapLoaded
        self.onMapClick = onMapClick
        self.onCameraMoveStart = onCameraMoveStart
        self.onCameraMove = onCameraMove
        self.onCameraMoveEnd = onCameraMoveEnd
        self.sdkInitialize = sdkInitialize
        self.content = content
    }

    public var body: some View {
        let mapContent = content()
        return ZStack {
            GoogleMapViewRepresentable(
                state: state,
                onMapLoaded: onMapLoaded,
                onMapClick: onMapClick,
                onCameraMoveStart: onCameraMoveStart,
                onCameraMove: onCameraMove,
                onCameraMoveEnd: onCameraMoveEnd,
                sdkInitialize: sdkInitialize,
                content: mapContent
            )
            ForEach(0..<mapContent.views.count, id: \.self) { index in
                mapContent.views[index]
            }
        }
    }
}

private struct GoogleMapViewRepresentable: UIViewRepresentable {
    @ObservedObject var state: GoogleMapViewState

    let onMapLoaded: OnMapLoadedHandler<GoogleMapViewState>?
    let onMapClick: OnMapEventHandler?
    let onCameraMoveStart: OnCameraMoveHandler?
    let onCameraMove: OnCameraMoveHandler?
    let onCameraMoveEnd: OnCameraMoveHandler?
    let sdkInitialize: (() -> Void)?
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

    func makeUIView(context: Context) -> GMSMapView {
        if let sdkInitialize = sdkInitialize {
            Coordinator.runOnce(sdkInitialize)
        }

        let camera = makeCamera(from: state.cameraPosition)
        let mapView = GMSMapView(frame: .zero, camera: camera)
        mapView.mapType = state.mapDesignType.getValue()
        mapView.delegate = context.coordinator
        context.coordinator.attachInfoBubbleContainer(to: mapView)
        context.coordinator.mapView = mapView
        context.coordinator.bind(state: state, mapView: mapView)
        // Ensure overlay controllers subscribe immediately (before the first updateUIView),
        // so early UI actions (e.g. tapping animation buttons) are not missed.
        MCLog.map("GoogleMapView.makeUIView updateContent markers=\(content.markers.count) bubbles=\(content.infoBubbles.count)")
        context.coordinator.updateContent(content)
        context.coordinator.updateInfoBubbleLayouts()
        return mapView
    }

    func updateUIView(_ uiView: GMSMapView, context: Context) {
        uiView.mapType = state.mapDesignType.getValue()
        MCLog.map("GoogleMapView.updateUIView updateContent markers=\(content.markers.count) bubbles=\(content.infoBubbles.count)")
        context.coordinator.updateContent(content)
        context.coordinator.updateInfoBubbleLayouts()
    }

    static func dismantleUIView(_ uiView: GMSMapView, coordinator: Coordinator) {
        coordinator.unbind()
        uiView.delegate = nil
    }

    private func makeCamera(from camera: MapCameraPosition) -> GMSCameraPosition {
        GMSCameraPosition(
            latitude: camera.position.latitude,
            longitude: camera.position.longitude,
            zoom: Float(camera.zoom),
            bearing: camera.bearing,
            viewingAngle: camera.tilt
        )
    }

    @MainActor
    final class Coordinator: NSObject, GMSMapViewDelegate {
        private static var hasInitializedSdk = false

        private let state: GoogleMapViewState
        private let onMapLoaded: OnMapLoadedHandler<GoogleMapViewState>?
        private let onMapClick: OnMapEventHandler?
        private let onCameraMoveStart: OnCameraMoveHandler?
        private let onCameraMove: OnCameraMoveHandler?
        private let onCameraMoveEnd: OnCameraMoveHandler?

        weak var mapView: GMSMapView?
        private var controller: GoogleMapViewController?
        private var markerController: GoogleMapMarkerController?
        private var rasterController: GoogleMapRasterLayerController?
        private var circleController: GoogleMapCircleController?
        private var polylineController: GoogleMapPolylineController?
        private var polygonController: GoogleMapPolygonController?
        private var infoBubbleController: InfoBubbleController?
        private var strategyMarkerController: StrategyMarkerController<
            GMSMarker,
            AnyMarkerRenderingStrategy<GMSMarker>,
            GoogleMapMarkerRenderer
        >?
        private var strategyMarkerRenderer: GoogleMapMarkerRenderer?
        private var strategyMarkerSubscriptions: [String: AnyCancellable] = [:]
        private var strategyMarkerStatesById: [String: MarkerState] = [:]

        private var didCallMapLoaded = false
        private let infoBubbleContainer = UIView()

        init(
            state: GoogleMapViewState,
            onMapLoaded: OnMapLoadedHandler<GoogleMapViewState>?,
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

        static func runOnce(_ initializer: () -> Void) {
            if hasInitializedSdk { return }
            hasInitializedSdk = true
            initializer()
        }

        func bind(state: GoogleMapViewState, mapView: GMSMapView) {
            let controller = GoogleMapViewController(mapView: mapView)
            self.controller = controller
            state.setController(controller)
            state.setMapViewHolder(controller.holder)

            let markerController = GoogleMapMarkerController(mapView: mapView) { [weak self] id in
                self?.infoBubbleController?.updateInfoBubblePosition(for: id)
            }
            self.markerController = markerController

            let rasterController = GoogleMapRasterLayerController(mapView: mapView)
            self.rasterController = rasterController

            let polylineController = GoogleMapPolylineController(mapView: mapView)
            self.polylineController = polylineController

            let polygonController = GoogleMapPolygonController(mapView: mapView)
            self.polygonController = polygonController

            let circleController = GoogleMapCircleController(mapView: mapView)
            self.circleController = circleController

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
            polylineController?.unbind()
            polylineController = nil
            polygonController?.unbind()
            polygonController = nil
            circleController?.unbind()
            circleController = nil
            infoBubbleController?.unbind()
            infoBubbleController = nil
            strategyMarkerSubscriptions.values.forEach { $0.cancel() }
            strategyMarkerSubscriptions.removeAll()
            strategyMarkerStatesById.removeAll()
            strategyMarkerRenderer?.unbind()
            strategyMarkerRenderer = nil
            strategyMarkerController?.destroy()
            strategyMarkerController = nil
        }

        func updateContent(_ content: MapViewContent) {
            infoBubbleController?.syncInfoBubbles(content.infoBubbles)
            markerController?.syncMarkers(content.markers)
            updateStrategyRendering(content)
            rasterController?.syncRasterLayers(content.rasterLayers)
            circleController?.syncCircles(content.circles)
            polylineController?.syncPolylines(content.polylines)
            polygonController?.syncPolygons(content.polygons)
            infoBubbleController?.updateAllLayouts()
        }

        // MARK: - GMSMapViewDelegate

        func mapView(_ mapView: GMSMapView, didTapAt coordinate: CLLocationCoordinate2D) {
            if circleController?.handleTap(at: coordinate) == true {
                return
            }
            if polylineController?.handleTap(at: coordinate) == true {
                return
            }
            if polygonController?.handleTap(at: coordinate) == true {
                return
            }
            let point = GeoPoint(latitude: coordinate.latitude, longitude: coordinate.longitude, altitude: 0)
            controller?.notifyMapClick(point)
            onMapClick?(point)
        }

        func mapView(_ mapView: GMSMapView, willMove gesture: Bool) {
            let camera = currentCameraPosition(from: mapView)
            controller?.notifyCameraMoveStart(camera)
            onCameraMoveStart?(camera)
            Task { [weak self] in
                await self?.rasterController?.onCameraChanged(mapCameraPosition: camera)
                await self?.polylineController?.onCameraChanged(mapCameraPosition: camera)
                await self?.strategyMarkerController?.onCameraChanged(mapCameraPosition: camera)
            }
            updateInfoBubbleLayouts()
        }

        func mapView(_ mapView: GMSMapView, didChange position: GMSCameraPosition) {
            let camera = currentCameraPosition(from: mapView)
            state.updateCameraPosition(camera)
            controller?.notifyCameraMove(camera)
            onCameraMove?(camera)
            Task { [weak self] in
                await self?.rasterController?.onCameraChanged(mapCameraPosition: camera)
                await self?.polylineController?.onCameraChanged(mapCameraPosition: camera)
                await self?.strategyMarkerController?.onCameraChanged(mapCameraPosition: camera)
            }
            updateInfoBubbleLayouts()
        }

        func mapView(_ mapView: GMSMapView, idleAt position: GMSCameraPosition) {
            let camera = currentCameraPosition(from: mapView)
            state.updateCameraPosition(camera)
            controller?.notifyCameraMoveEnd(camera)
            onCameraMoveEnd?(camera)
            Task { [weak self] in
                await self?.rasterController?.onCameraChanged(mapCameraPosition: camera)
                await self?.polylineController?.onCameraChanged(mapCameraPosition: camera)
                await self?.strategyMarkerController?.onCameraChanged(mapCameraPosition: camera)
            }
            updateInfoBubbleLayouts()

            if !didCallMapLoaded {
                didCallMapLoaded = true
                onMapLoaded?(state)
            }
        }

        func mapView(_ mapView: GMSMapView, didTap marker: GMSMarker) -> Bool {
            guard let id = marker.userData as? String else { return false }
            if let state = markerController?.getMarkerState(for: id) {
                markerController?.dispatchClick(state: state)
            } else if let state = strategyMarkerController?.markerManager.getEntity(id)?.state {
                strategyMarkerController?.dispatchClick(state)
            }
            return false
        }

        func mapView(_ mapView: GMSMapView, didBeginDragging marker: GMSMarker) {
            guard let id = marker.userData as? String else { return }
            let state = markerController?.getMarkerState(for: id) ??
                strategyMarkerController?.markerManager.getEntity(id)?.state
            guard let state else { return }
            state.position = GeoPoint(
                latitude: marker.position.latitude,
                longitude: marker.position.longitude,
                altitude: 0
            )
            infoBubbleController?.updateInfoBubblePosition(for: id)
            if markerController?.getMarkerState(for: id) != nil {
                markerController?.dispatchDragStart(state: state)
            } else {
                strategyMarkerController?.dispatchDragStart(state)
            }
        }

        func mapView(_ mapView: GMSMapView, didDrag marker: GMSMarker) {
            guard let id = marker.userData as? String else { return }
            let state = markerController?.getMarkerState(for: id) ??
                strategyMarkerController?.markerManager.getEntity(id)?.state
            guard let state else { return }
            state.position = GeoPoint(
                latitude: marker.position.latitude,
                longitude: marker.position.longitude,
                altitude: 0
            )
            infoBubbleController?.updateInfoBubblePosition(for: id)
            if markerController?.getMarkerState(for: id) != nil {
                markerController?.dispatchDrag(state: state)
            } else {
                strategyMarkerController?.dispatchDrag(state)
            }
        }

        func mapView(_ mapView: GMSMapView, didEndDragging marker: GMSMarker) {
            guard let id = marker.userData as? String else { return }
            let state = markerController?.getMarkerState(for: id) ??
                strategyMarkerController?.markerManager.getEntity(id)?.state
            guard let state else { return }
            state.position = GeoPoint(
                latitude: marker.position.latitude,
                longitude: marker.position.longitude,
                altitude: 0
            )
            infoBubbleController?.updateInfoBubblePosition(for: id)
            if markerController?.getMarkerState(for: id) != nil {
                markerController?.dispatchDragEnd(state: state)
            } else {
                strategyMarkerController?.dispatchDragEnd(state)
            }
        }

        func mapView(_ mapView: GMSMapView, markerInfoContents marker: GMSMarker) -> UIView? {
            nil
        }

        // MARK: - Helper Methods

        private func currentCameraPosition(from mapView: GMSMapView) -> MapCameraPosition {
            let camera = mapView.camera
            let region = mapView.projection.visibleRegion()
            let bounds = GMSCoordinateBounds(region: region)
            let visibleRegion = VisibleRegion(
                bounds: GeoRectBounds(
                    southWest: GeoPoint(
                        latitude: bounds.southWest.latitude,
                        longitude: bounds.southWest.longitude,
                        altitude: 0
                    ),
                    northEast: GeoPoint(
                        latitude: bounds.northEast.latitude,
                        longitude: bounds.northEast.longitude,
                        altitude: 0
                    )
                ),
                nearLeft: GeoPoint(
                    latitude: region.nearLeft.latitude,
                    longitude: region.nearLeft.longitude,
                    altitude: 0
                ),
                nearRight: GeoPoint(
                    latitude: region.nearRight.latitude,
                    longitude: region.nearRight.longitude,
                    altitude: 0
                ),
                farLeft: GeoPoint(
                    latitude: region.farLeft.latitude,
                    longitude: region.farLeft.longitude,
                    altitude: 0
                ),
                farRight: GeoPoint(
                    latitude: region.farRight.latitude,
                    longitude: region.farRight.longitude,
                    altitude: 0
                )
            )
            return MapCameraPosition(
                position: GeoPoint(latitude: camera.target.latitude, longitude: camera.target.longitude, altitude: 0),
                zoom: Double(camera.zoom),
                bearing: camera.bearing,
                tilt: camera.viewingAngle,
                visibleRegion: visibleRegion
            )
        }

        private func updateStrategyRendering(_ content: MapViewContent) {
            guard let mapView else { return }
            if let strategy = content.markerRenderingStrategy as? AnyMarkerRenderingStrategy<GMSMarker> {
                if strategyMarkerController == nil ||
                    strategyMarkerController?.markerManager !== strategy.markerManager {
                    strategyMarkerRenderer?.unbind()
                    let renderer = GoogleMapMarkerRenderer(
                        mapView: mapView,
                        markerManager: strategy.markerManager
                    )
                    strategyMarkerRenderer = renderer
                    strategyMarkerController = StrategyMarkerController(strategy: strategy, renderer: renderer)
                    Task { [weak self] in
                        guard let self else { return }
                        await self.strategyMarkerController?.onCameraChanged(
                            mapCameraPosition: self.currentCameraPosition(from: mapView)
                        )
                    }
                }
                syncStrategyMarkers(content.markerRenderingMarkers)
            } else {
                strategyMarkerSubscriptions.values.forEach { $0.cancel() }
                strategyMarkerSubscriptions.removeAll()
                strategyMarkerStatesById.removeAll()
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

            let removedIds = oldIds.subtracting(newIds)
            for id in removedIds {
                strategyMarkerSubscriptions[id]?.cancel()
                strategyMarkerSubscriptions.removeValue(forKey: id)
            }

            if shouldSyncList {
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

        fileprivate func attachInfoBubbleContainer(to mapView: GMSMapView) {
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
