import Foundation
import MapConductorCore
import UIKit

final class FitBoundsPageViewModel: ObservableObject {
    let initCameraPosition: MapCameraPosition
    let marker: MarkerState
    let boundsPolygon: PolygonState

    private var dragStartPosition: GeoPoint?
    private var clearTask: Task<Void, Never>?
    private var activeState: (any MapViewStateProtocol)?

    init() {
        let initial = GeoPoint.fromLatLong(latitude: 35.68, longitude: 139.76)
        self.initCameraPosition = MapCameraPosition(
            position: initial,
            zoom: 10.0,
            bearing: 0.0,
            tilt: 0.0,
            paddings: nil
        )
        self.boundsPolygon = PolygonState(
            points: Self.hiddenPolygonPoints(around: initial),
            id: "fitbounds_polygon",
            strokeColor: .clear,
            strokeWidth: 0.0,
            fillColor: .clear
        )
        self.marker = MarkerState(
            position: initial,
            id: "fitbounds_marker",
            draggable: true
        )
        marker.onDragStart = { [weak self] m in self?.onDragStart(m) }
        marker.onDrag      = { [weak self] m in self?.onDrag(m) }
        marker.onDragEnd   = { [weak self] m in self?.onDragEnd(m) }
    }

    func setActiveState(_ state: any MapViewStateProtocol) {
        activeState = state
    }

    private func onDragStart(_ marker: MarkerState) {
        clearTask?.cancel()
        clearTask = nil
        dragStartPosition = GeoPoint.from(position: marker.position)
    }

    private func onDrag(_ marker: MarkerState) {
        guard let start = dragStartPosition else { return }
        let current = GeoPoint.from(position: marker.position)
        showBoundsPolygon(points: Self.polygonPoints(from: start, to: current))
    }

    private func onDragEnd(_ marker: MarkerState) {
        guard let start = dragStartPosition else { return }
        let current = GeoPoint.from(position: marker.position)
        let bounds = GeoRectBounds(
            southWest: GeoPoint(
                latitude: min(start.latitude, current.latitude),
                longitude: min(start.longitude, current.longitude)
            ),
            northEast: GeoPoint(
                latitude: max(start.latitude, current.latitude),
                longitude: max(start.longitude, current.longitude)
            )
        )
        activeState?.fitBounds(bounds: bounds, padding: 0)
        dragStartPosition = nil
        clearTask?.cancel()
        clearTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard let self else { return }
            self.hideBoundsPolygon(around: GeoPoint.from(position: marker.position))
        }
    }

    private func showBoundsPolygon(points: [GeoPointProtocol]) {
        boundsPolygon.points = points
        boundsPolygon.strokeColor = .red
        boundsPolygon.strokeWidth = 2.0
        boundsPolygon.fillColor = UIColor.red.withAlphaComponent(0.3)
    }

    private func hideBoundsPolygon(around point: GeoPoint) {
        boundsPolygon.points = Self.hiddenPolygonPoints(around: point)
        boundsPolygon.strokeColor = .clear
        boundsPolygon.strokeWidth = 0.0
        boundsPolygon.fillColor = .clear
    }

    private static func hiddenPolygonPoints(around point: GeoPoint) -> [GeoPointProtocol] {
        let epsilon = 0.000001
        return polygonPoints(
            from: point,
            to: GeoPoint(latitude: point.latitude + epsilon, longitude: point.longitude + epsilon)
        )
    }

    private static func polygonPoints(from a: GeoPoint, to b: GeoPoint) -> [GeoPointProtocol] {
        let minLat = min(a.latitude, b.latitude)
        let maxLat = max(a.latitude, b.latitude)
        let minLon = min(a.longitude, b.longitude)
        let maxLon = max(a.longitude, b.longitude)
        return [
            GeoPoint(latitude: minLat, longitude: minLon),
            GeoPoint(latitude: minLat, longitude: maxLon),
            GeoPoint(latitude: maxLat, longitude: maxLon),
            GeoPoint(latitude: maxLat, longitude: minLon),
        ]
    }
}
