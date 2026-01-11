import Foundation
import MapConductorCore
import SwiftUI
import UIKit

@MainActor
final class GroundImagePageViewModel: ObservableObject {
    let initCameraPosition: MapCameraPosition
    let groundImageState: GroundImageState
    let markers: [MarkerState]

    @Published var opacity: Double
    @Published var message: String? = nil

    private let resources: GroundImageResources
    private let southWestMarker: MarkerState
    private let northEastMarker: MarkerState

    init(resources: GroundImageResources) {
        self.resources = resources

        let center = GeoPoint(latitude: 40.7430785, longitude: -74.175995, altitude: 0)
        self.initCameraPosition = MapCameraPosition(
            position: center,
            zoom: 12.0,
            bearing: 0.0,
            tilt: 0.0,
            paddings: nil
        )

        let southWest = GeoPoint(latitude: 40.712216, longitude: -74.22655, altitude: 0)
        let northEast = GeoPoint(latitude: 40.773941, longitude: -74.12544, altitude: 0)

        let initialOpacity = 0.5
        self.opacity = initialOpacity

        let bounds = GroundImagePageViewModel.makeBounds(southWest: southWest, northEast: northEast)
        self.groundImageState = GroundImageState(
            bounds: bounds,
            image: resources.image,
            opacity: initialOpacity,
            tileSize: 512,
            id: "groundImage",
            extra: nil,
            onClick: nil
        )

        self.southWestMarker = MarkerState(
            position: southWest,
            id: "south_west",
            extra: nil,
            icon: DefaultMarkerIcon(fillColor: .systemBlue, strokeColor: .white, label: "SW", labelTextColor: .white),
            animation: nil,
            clickable: true,
            draggable: true,
            onClick: nil,
            onDragStart: nil,
            onDrag: nil,
            onDragEnd: nil,
            onAnimateStart: nil,
            onAnimateEnd: nil
        )

        self.northEastMarker = MarkerState(
            position: northEast,
            id: "north_east",
            extra: nil,
            icon: DefaultMarkerIcon(fillColor: .systemRed, strokeColor: .white, label: "NE", labelTextColor: .white),
            animation: nil,
            clickable: true,
            draggable: true,
            onClick: nil,
            onDragStart: nil,
            onDrag: nil,
            onDragEnd: nil,
            onAnimateStart: nil,
            onAnimateEnd: nil
        )

        self.markers = [southWestMarker, northEastMarker]

        self.groundImageState.onClick = { [weak self] event in
            self?.onGroundImageClick(event)
        }
        self.southWestMarker.onDrag = { [weak self] marker in
            self?.onMarkerDrag(marker)
        }
        self.northEastMarker.onDrag = { [weak self] marker in
            self?.onMarkerDrag(marker)
        }

        updateLabelsAndBounds()
        groundImageState.opacity = opacity
    }

    func setOpacity(_ value: Double) {
        let resolved = min(max(value, 0.0), 1.0)
        opacity = resolved
        groundImageState.opacity = resolved
    }

    private func onGroundImageClick(_ event: GroundImageEvent) {
        if groundImageState.image === resources.image {
            groundImageState.image = resources.clickedImage
        } else {
            groundImageState.image = resources.image
        }
        showMessage("Ground Image clicked.")
    }

    private func onMarkerDrag(_ marker: MarkerState) {
        if marker.id == southWestMarker.id {
            southWestMarker.position = GeoPoint.from(position: marker.position)
        } else if marker.id == northEastMarker.id {
            northEastMarker.position = GeoPoint.from(position: marker.position)
        }

        updateLabelsAndBounds()
    }

    private func showMessage(_ text: String) {
        message = text
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if self?.message == text {
                self?.message = nil
            }
        }
    }

    private func updateLabelsAndBounds() {
        let sw = GeoPoint.from(position: southWestMarker.position)
        let ne = GeoPoint.from(position: northEastMarker.position)
        let labels = GroundImagePageViewModel.calculateMarkerLabels(southWest: sw, northEast: ne)

        southWestMarker.icon = DefaultMarkerIcon(
            fillColor: .systemBlue,
            strokeColor: .white,
            label: labels.0,
            labelTextColor: .white
        )
        northEastMarker.icon = DefaultMarkerIcon(
            fillColor: .systemRed,
            strokeColor: .white,
            label: labels.1,
            labelTextColor: .white
        )

        groundImageState.bounds = GeoRectBounds().also { bounds in
            bounds.extend(point: sw)
            bounds.extend(point: ne)
        }
    }

    private static func calculateMarkerLabels(southWest: GeoPoint, northEast: GeoPoint) -> (String, String) {
        let swLat = southWest.latitude
        let swLng = southWest.longitude
        let neLat = northEast.latitude
        let neLng = northEast.longitude

        let southWestLabel: String
        switch (swLat <= neLat, swLng <= neLng) {
        case (true, true):
            southWestLabel = "SW"
        case (true, false):
            southWestLabel = "SE"
        case (false, true):
            southWestLabel = "NW"
        case (false, false):
            southWestLabel = "NE"
        }

        let northEastLabel: String
        switch (neLat >= swLat, neLng >= swLng) {
        case (true, true):
            northEastLabel = "NE"
        case (true, false):
            northEastLabel = "NW"
        case (false, true):
            northEastLabel = "SE"
        case (false, false):
            northEastLabel = "SW"
        }

        return (southWestLabel, northEastLabel)
    }

    private static func makeBounds(southWest: GeoPoint, northEast: GeoPoint) -> GeoRectBounds {
        GeoRectBounds(southWest: southWest, northEast: northEast)
    }
}

private extension GeoRectBounds {
    func also(_ block: (GeoRectBounds) -> Void) -> GeoRectBounds {
        block(self)
        return self
    }
}
