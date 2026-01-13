import Combine
import MapKit
import MapConductorCore
import QuartzCore
import SwiftUI
import UIKit

/// A container view that only intercepts touches on its subviews (InfoBubbles),
/// allowing touches elsewhere to pass through to the map view below.
private class PassthroughContainerView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hitView = super.hitTest(point, with: event)
        // If the hit view is this container itself (not a subview), return nil
        // to pass the touch through to the view below (the map).
        return hitView == self ? nil : hitView
    }
}

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

        // Use the extension method to properly set camera with tilt and bearing
        let camera = state.cameraPosition.toMKMapCamera()
        mapView.setCamera(camera, animated: false)

        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleMapTap(_:)))
        tapGesture.cancelsTouchesInView = false
        mapView.addGestureRecognizer(tapGesture)

        context.coordinator.attachInfoBubbleContainer(to: mapView)
        context.coordinator.mapView = mapView
        context.coordinator.bind(state: state, mapView: mapView)
        MCLog.map("MapKitMapView.makeUIView updateContent markers=\(content.markers.count) bubbles=\(content.infoBubbles.count)")
        context.coordinator.updateContent(content)
        context.coordinator.updateInfoBubbleLayouts()
        return mapView
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {
        uiView.mapType = state.mapDesignType.getValue()
        MCLog.map("MapKitMapView.updateUIView updateContent markers=\(content.markers.count) bubbles=\(content.infoBubbles.count)")
        context.coordinator.updateContent(content)
        context.coordinator.updateInfoBubbleLayouts()
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
        private var markerController: MapKitMarkerController?
        private var infoBubbleController: InfoBubbleController?
        private var circleController: MapKitCircleController?
        private var polylineController: MapKitPolylineController?
        private var polygonController: MapKitPolygonController?
        private var rasterLayerController: MapKitRasterLayerController?
        private var groundImageController: MapKitGroundImageController?

        private var didCallMapLoaded = false
        private var isRegionChanging = false
        private var cameraObserver: NSKeyValueObservation?
        private let infoBubbleContainer = PassthroughContainerView()

        private var draggingMarkerId: String?
        private weak var draggingAnnotationView: MKAnnotationView?
        private var dragDisplayLink: CADisplayLink?

        // Store icon for each marker state to provide to delegate (best-effort cache).
        // `mapView(_:viewFor:)` should not depend on this cache because it can be called
        // before `updateContent` finishes populating it.
        private var markerIcons: [String: BitmapIcon] = [:]
        private var markerStates: [String: MarkerState] = [:]

        private var strategyMarkerController:
            StrategyMarkerController<
                MKPointAnnotation,
                AnyMarkerRenderingStrategy<MKPointAnnotation>,
                MapKitMarkerRenderer
            >?
        private var strategyMarkerRenderer: MapKitMarkerRenderer?
        private var strategyMarkerSubscriptions: [String: AnyCancellable] = [:]
        private var strategyMarkerStatesById: [String: MarkerState] = [:]
        private var strategyMarkerIcons: [String: BitmapIcon] = [:]

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

            let markerController = MapKitMarkerController(mapView: mapView) { [weak self] id in
                // Info bubble position update callback
                self?.updateInfoBubblePosition(for: id)
            }
            self.markerController = markerController

            let infoBubbleController = InfoBubbleController(
                mapView: mapView,
                container: infoBubbleContainer,
                markerController: markerController
            )
            self.infoBubbleController = infoBubbleController

            let circleController = MapKitCircleController(mapView: mapView)
            self.circleController = circleController

            let polylineController = MapKitPolylineController(mapView: mapView)
            self.polylineController = polylineController

            let polygonController = MapKitPolygonController(mapView: mapView)
            self.polygonController = polygonController

            let rasterLayerController = MapKitRasterLayerController(mapView: mapView)
            self.rasterLayerController = rasterLayerController

            let groundImageController = MapKitGroundImageController(mapView: mapView)
            self.groundImageController = groundImageController

            // Observe camera changes to detect tilt and bearing updates
            // This captures changes that regionDidChange might miss
            cameraObserver = mapView.observe(\.camera, options: [.old, .new]) { [weak self] observedMapView, change in
                guard let self = self else { return }
                // Check if camera actually changed (not just the same notification)
                if let oldCamera = change.oldValue, let newCamera = change.newValue {
                    let headingChanged = abs(oldCamera.heading - newCamera.heading) > 0.01
                    let pitchChanged = abs(oldCamera.pitch - newCamera.pitch) > 0.01

                    // If tilt or bearing changed, update immediately
                    if headingChanged || pitchChanged {
                        let camera = self.currentCameraPosition(from: observedMapView)
                        self.state.updateCameraPosition(camera)
                        self.controller?.notifyCameraMoveEnd(camera)
                        self.onCameraMoveEnd?(camera)
                        self.updateInfoBubbleLayouts()
                    }
                }
            }
        }

        func unbind() {
            stopDragTracking()
            cameraObserver?.invalidate()
            cameraObserver = nil
            state.setController(nil)
            state.setMapViewHolder(nil)
            controller = nil
            markerController?.unbind()
            markerController = nil
            infoBubbleController?.unbind()
            infoBubbleController = nil
            circleController?.unbind()
            circleController = nil
            polylineController?.unbind()
            polylineController = nil
            polygonController?.unbind()
            polygonController = nil
            rasterLayerController?.unbind()
            rasterLayerController = nil
            groundImageController?.unbind()
            groundImageController = nil
            markerIcons.removeAll()
            markerStates.removeAll()

            strategyMarkerSubscriptions.values.forEach { $0.cancel() }
            strategyMarkerSubscriptions.removeAll()
            strategyMarkerStatesById.removeAll()
            strategyMarkerIcons.removeAll()
            strategyMarkerRenderer?.unbind()
            strategyMarkerRenderer = nil
            strategyMarkerController?.destroy()
            strategyMarkerController = nil
        }

        func updateContent(_ content: MapViewContent) {
            MCLog.map("MapKitMapView.updateContent markers=\(content.markers.count) circles=\(content.circles.count) polylines=\(content.polylines.count) polygons=\(content.polygons.count)")
            infoBubbleController?.syncInfoBubbles(content.infoBubbles)

            // Prime marker caches before triggering MKMapView annotation creation.
            // (MapKit can ask for annotation views immediately after addAnnotation.)
            markerIcons = content.markers.reduce(into: [:]) { dict, marker in
                dict[marker.id] = (marker.state.icon ?? DefaultMarkerIcon()).toBitmapIcon()
            }
            markerStates = content.markers.reduce(into: [:]) { dict, marker in
                dict[marker.id] = marker.state
            }

            markerController?.syncMarkers(content.markers)
            updateStrategyRendering(content)
            circleController?.syncCircles(content.circles)
            polylineController?.syncPolylines(content.polylines)
            polygonController?.syncPolygons(content.polygons)
            rasterLayerController?.syncRasterLayers(content.rasterLayers)
            groundImageController?.syncGroundImages(content.groundImages)
        }

        private func updateStrategyRendering(_ content: MapViewContent) {
            guard let mapView else { return }
            if let strategy = content.markerRenderingStrategy as? AnyMarkerRenderingStrategy<MKPointAnnotation> {
                MCLog.map("MapKitMapView.updateStrategyRendering enabled markers=\(content.markerRenderingMarkers.count)")
                if strategyMarkerController == nil ||
                    strategyMarkerController?.markerManager !== strategy.markerManager {
                    MCLog.map("MapKitMapView.updateStrategyRendering createController")
                    strategyMarkerRenderer?.unbind()
                    let renderer = MapKitMarkerRenderer(
                        mapView: mapView,
                        markerManager: strategy.markerManager
                    )
                    strategyMarkerRenderer = renderer
                    let controller = StrategyMarkerController(strategy: strategy, renderer: renderer)
                    strategyMarkerController = controller
                    Task { [weak self] in
                        guard let self else { return }
                        await controller.onCameraChanged(mapCameraPosition: self.currentCameraPosition(from: mapView))
                    }
                }
                syncStrategyMarkers(content.markerRenderingMarkers)
            } else {
                if content.markerRenderingStrategy != nil {
                    MCLog.map("MapKitMapView.updateStrategyRendering strategyTypeMismatch type=\(type(of: content.markerRenderingStrategy!))")
                }
                strategyMarkerSubscriptions.values.forEach { $0.cancel() }
                strategyMarkerSubscriptions.removeAll()
                strategyMarkerStatesById.removeAll()
                strategyMarkerIcons.removeAll()
                strategyMarkerRenderer?.unbind()
                strategyMarkerRenderer = nil
                strategyMarkerController?.destroy()
                strategyMarkerController = nil
            }
        }

        private func syncStrategyMarkers(_ markers: [MarkerState]) {
            guard let controller = strategyMarkerController else { return }
            MCLog.map("MapKitMapView.syncStrategyMarkers count=\(markers.count)")
            let newIds = Set(markers.map { $0.id })
            let oldIds = Set(strategyMarkerStatesById.keys)
            var shouldSyncList = newIds != oldIds

            var newStatesById: [String: MarkerState] = [:]
            var newIcons: [String: BitmapIcon] = [:]
            for state in markers {
                if let existing = strategyMarkerStatesById[state.id], existing !== state {
                    strategyMarkerSubscriptions[state.id]?.cancel()
                    strategyMarkerSubscriptions.removeValue(forKey: state.id)
                    shouldSyncList = true
                }
                newStatesById[state.id] = state
                newIcons[state.id] = (state.icon ?? DefaultMarkerIcon()).toBitmapIcon()
            }
            strategyMarkerStatesById = newStatesById
            strategyMarkerIcons = newIcons

            let removedIds = oldIds.subtracting(newIds)
            for id in removedIds {
                strategyMarkerSubscriptions[id]?.cancel()
                strategyMarkerSubscriptions.removeValue(forKey: id)
            }

            if shouldSyncList {
                Task { [weak self] in
                    guard let self else { return }
                    MCLog.map("MapKitMapView.syncStrategyMarkers -> add() count=\(markers.count)")
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
                .dropFirst()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    guard let self else { return }
                    guard self.strategyMarkerStatesById[state.id] != nil else { return }
                    Task { [weak self] in
                        guard let self else { return }
                        await self.strategyMarkerController?.update(state: state)
                    }
                }
        }

        // MARK: - MKMapViewDelegate

        func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
            guard !isRegionChanging else { return }
            isRegionChanging = true
            let camera = currentCameraPosition(from: mapView)
            controller?.notifyCameraMoveStart(camera)
            onCameraMoveStart?(camera)
        }

        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            guard isRegionChanging else { return }
            let camera = mapView.toMapCameraPosition()
            state.updateCameraPosition(camera)
            controller?.notifyCameraMove(camera)
            onCameraMove?(camera)
            Task { [weak self] in
                guard let self else { return }
                await self.strategyMarkerController?.onCameraChanged(mapCameraPosition: camera)
            }
            updateInfoBubbleLayouts()
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            let camera = currentCameraPosition(from: mapView)
            state.updateCameraPosition(camera)
            controller?.notifyCameraMoveEnd(camera)
            onCameraMoveEnd?(camera)
            Task { [weak self] in
                guard let self else { return }
                await self.strategyMarkerController?.onCameraChanged(mapCameraPosition: camera)
            }
            updateInfoBubbleLayouts()
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

            // Hit-test overlays first (MapKit doesn't provide built-in overlay tap callbacks).
            if groundImageController?.handleTap(at: coordinate) == true { return }
            if circleController?.handleTap(at: coordinate) == true { return }
            if polylineController?.handleTap(at: coordinate) == true { return }
            if polygonController?.handleTap(at: coordinate) == true { return }

            let geoPoint = GeoPoint(latitude: coordinate.latitude, longitude: coordinate.longitude, altitude: 0)
            controller?.notifyMapClick(geoPoint)
            onMapClick?(geoPoint)
        }

        // MARK: - Annotation Delegate Methods

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            // Allow MapKit to render the user location annotation.
            if annotation is MKUserLocation { return nil }

            guard let pointAnnotation = annotation as? MKPointAnnotation else {
                return nil
            }

            let mapConductorAnnotation = pointAnnotation as? MapConductorPointAnnotation
            let markerIdString = mapConductorAnnotation?.markerId ?? pointAnnotation.title ?? ""
            let markerState = markerController?.getMarkerState(for: markerIdString)
                ?? markerStates[markerIdString]
                ?? strategyMarkerStatesById[markerIdString]
                ?? mapConductorAnnotation?.markerState
            let cachedIcon = markerIcons[markerIdString] ?? mapConductorAnnotation?.initialBitmapIcon
                ?? strategyMarkerIcons[markerIdString]

            // If this isn't one of our markers, allow MapKit's default behavior.
            if markerState == nil, cachedIcon == nil { return nil }

            // Avoid returning nil here; returning nil makes MapKit fall back to the default pin annotation.
            let resolvedIcon = cachedIcon ?? (markerState?.icon ?? DefaultMarkerIcon()).toBitmapIcon()

            let identifier = "MapKitMarker"
            let annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
                ?? MKAnnotationView(annotation: annotation, reuseIdentifier: identifier)

            annotationView.annotation = annotation
            if let markerState {
                if markerController?.getMarkerState(for: markerIdString) != nil || markerStates[markerIdString] != nil {
                    markerController?.renderer.configureAnnotationView(annotationView, for: markerState, bitmapIcon: resolvedIcon)
                } else {
                    strategyMarkerRenderer?.configureAnnotationView(annotationView, for: markerState, bitmapIcon: resolvedIcon)
                }
            } else {
                annotationView.image = resolvedIcon.bitmap
                annotationView.isDraggable = false
                annotationView.canShowCallout = false
                annotationView.isEnabled = true
                annotationView.centerOffset = CGPoint(
                    x: (resolvedIcon.anchor.x - 0.5) * resolvedIcon.bitmap.size.width,
                    y: -(resolvedIcon.anchor.y - 0.5) * resolvedIcon.bitmap.size.height
                )
                annotationView.alpha = 1
            }

            return annotationView
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard let pointAnnotation = view.annotation as? MKPointAnnotation,
                  let markerId = pointAnnotation.title,
                  let markerState = markerController?.getMarkerState(for: markerId)
                    ?? markerStates[markerId]
                    ?? strategyMarkerStatesById[markerId] else {
                return
            }

            // Trigger onClick callback
            markerState.onClick?(markerState)

            // For draggable markers, keep selection to allow drag gesture
            // For non-draggable markers, deselect immediately
            if !markerState.draggable {
                mapView.deselectAnnotation(view.annotation, animated: false)
            }
        }

        func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView, didChange newState: MKAnnotationView.DragState, fromOldState oldState: MKAnnotationView.DragState) {
            guard let pointAnnotation = view.annotation as? MKPointAnnotation,
                  let markerId = pointAnnotation.title,
                  let markerState = markerController?.getMarkerState(for: markerId)
                    ?? markerStates[markerId] else {
                return
            }

            switch newState {
            case .starting:
                markerState.onDragStart?(markerState)
                startDragTracking(markerId: markerState.id, annotationView: view)
            case .dragging:
                // Drag updates are handled by CADisplayLink in startDragTracking().
                startDragTracking(markerId: markerState.id, annotationView: view)
            case .ending, .canceling:
                // Ensure final location is reflected in both marker state and bubble position.
                let coordinate = coordinateForAnnotationView(view, in: mapView)
                markerState.position = GeoPoint(latitude: coordinate.latitude, longitude: coordinate.longitude, altitude: 0)
                markerState.onDragEnd?(markerState)
                updateInfoBubblePosition(for: markerState.id)
                // Deselect after drag ends
                mapView.deselectAnnotation(view.annotation, animated: false)
                stopDragTracking()
            case .none:
                stopDragTracking()
                break
            @unknown default:
                stopDragTracking()
                break
            }
        }

        // MARK: - Overlay Delegate Methods

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            // Handle raster tile overlays first to ensure they always get an MKTileOverlayRenderer.
            // (If MapKit caches a default renderer once, it may not re-query later.)
            if let tileOverlay = overlay as? MKTileOverlay {
                return rasterLayerController?.renderer.renderer(for: tileOverlay) ?? MKTileOverlayRenderer(tileOverlay: tileOverlay)
            }
            // Check if it's a ground image overlay
            if let renderer = groundImageController?.renderer.renderer(for: overlay) {
                return renderer
            }
            // Check if it's a raster layer overlay (tile overlay)
            if let renderer = rasterLayerController?.renderer.renderer(for: overlay) {
                return renderer
            }
            // Check if it's a circle overlay
            if let renderer = circleController?.renderer.renderer(for: overlay) {
                return renderer
            }
            // Check if it's a polyline overlay
            if let renderer = polylineController?.renderer.renderer(for: overlay) {
                return renderer
            }
            // Check if it's a polygon overlay
            if let renderer = polygonController?.renderer.renderer(for: overlay) {
                return renderer
            }
            // Default renderer
            return MKOverlayRenderer(overlay: overlay)
        }

        // MARK: - Helper Methods

        private func coordinateForAnnotationView(_ view: MKAnnotationView, in mapView: MKMapView) -> CLLocationCoordinate2D {
            // centerOffset is the offset from the map coordinate point to the view center.
            let anchorPoint = CGPoint(
                x: view.center.x - view.centerOffset.x,
                y: view.center.y - view.centerOffset.y
            )
            return mapView.convert(anchorPoint, toCoordinateFrom: mapView)
        }
        
        private func startDragTracking(markerId: String, annotationView: MKAnnotationView) {
            draggingMarkerId = markerId
            draggingAnnotationView = annotationView
            guard dragDisplayLink == nil else { return }
            let displayLink = CADisplayLink(target: self, selector: #selector(stepDragTracking(_:)))
            dragDisplayLink = displayLink
            displayLink.add(to: .main, forMode: .common)
        }

        private func stopDragTracking() {
            dragDisplayLink?.invalidate()
            dragDisplayLink = nil
            draggingMarkerId = nil
            draggingAnnotationView = nil
        }

        @objc private func stepDragTracking(_ displayLink: CADisplayLink) {
            guard let id = draggingMarkerId,
                  let mapView,
                  let annotationView = draggingAnnotationView else {
                        stopDragTracking()
                        return
                    }

            // During interactive dragging, MapKit moves the annotation view continuously, but the annotation's
            // coordinate may not update until the drag ends. Track the view position (coordinate point) instead.
            let coordinatePoint = CGPoint(
                x: annotationView.center.x - annotationView.centerOffset.x,
                y: annotationView.center.y - annotationView.centerOffset.y
            )
            infoBubbleController?.updateInfoBubblePosition(for: id, coordinatePoint: coordinatePoint)

            if let markerState = markerController?.getMarkerState(for: id) {
                let coordinate = mapView.convert(coordinatePoint, toCoordinateFrom: mapView)
                markerState.position = GeoPoint(latitude: coordinate.latitude, longitude: coordinate.longitude, altitude: 0)
                markerState.onDrag?(markerState)
            }
        }

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

        fileprivate func attachInfoBubbleContainer(to mapView: MKMapView) {
            guard infoBubbleContainer.superview !== mapView else { return }
            infoBubbleContainer.backgroundColor = .clear
            infoBubbleContainer.isUserInteractionEnabled = true  // Enable interaction for InfoBubble buttons
            infoBubbleContainer.frame = mapView.bounds
            infoBubbleContainer.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            mapView.addSubview(infoBubbleContainer)
        }

        fileprivate func updateInfoBubbleLayouts() {
            infoBubbleController?.updateAllLayouts()
        }

        private func updateInfoBubblePosition(for id: String) {
            infoBubbleController?.updateInfoBubblePosition(for: id)
        }
    }
}
