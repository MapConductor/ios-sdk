import MapConductorCore
import MapConductorForGoogleMaps
import MapConductorForMapLibre
import MapConductorForMapKit
import SwiftUI
import GoogleMaps

struct CameraSyncTestPage: View {
    let onToggleSidebar: () -> Void

    @StateObject private var viewModel = CameraSyncTestViewModel()
    @StateObject private var leftGoogleState: GoogleMapViewState
    @StateObject private var leftMapLibreState: MapLibreViewState
    @StateObject private var leftMapKitState: MapKitViewState

    @StateObject private var rightGoogleState: GoogleMapViewState
    @StateObject private var rightMapLibreState: MapLibreViewState
    @StateObject private var rightMapKitState: MapKitViewState

    init(onToggleSidebar: @escaping () -> Void = {}) {
        self.onToggleSidebar = onToggleSidebar
        let vm = CameraSyncTestViewModel()
        _viewModel = StateObject(wrappedValue: vm)

        // Left map states
        _leftGoogleState = StateObject(wrappedValue: GoogleMapViewState(
            cameraPosition: vm.initCameraPosition
        ))
        _leftMapLibreState = StateObject(wrappedValue: MapLibreViewState(
            mapDesignType: MapLibreDesign.OsmBright,
            cameraPosition: vm.initCameraPosition
        ))
        _leftMapKitState = StateObject(wrappedValue: MapKitViewState(
            mapDesignType: MapKitMapDesign.Standard,
            cameraPosition: vm.initCameraPosition
        ))

        // Right map states
        _rightGoogleState = StateObject(wrappedValue: GoogleMapViewState(
            cameraPosition: vm.initCameraPosition
        ))
        _rightMapLibreState = StateObject(wrappedValue: MapLibreViewState(
            mapDesignType: MapLibreDesign.OsmBright,
            cameraPosition: vm.initCameraPosition
        ))
        _rightMapKitState = StateObject(wrappedValue: MapKitViewState(
            mapDesignType: MapKitMapDesign.Standard,
            cameraPosition: vm.initCameraPosition
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: onToggleSidebar) {
                    Image(systemName: "line.3.horizontal")
                        .font(.title2)
                        .foregroundColor(.primary)
                }
                .padding()

                Spacer()

                Text("Camera Sync Test")
                    .font(.headline)

                Spacer()

                HStack(spacing: 20) {
                    // Left provider picker
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Left (Source)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Picker("Left", selection: $viewModel.leftProvider) {
                            ForEach(MapProvider.allCases) { provider in
                                Text(viewModel.getProviderName(provider))
                                    .tag(provider)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    // Right provider picker
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Right (Synced)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Picker("Right", selection: $viewModel.rightProvider) {
                            ForEach(MapProvider.allCases) { provider in
                                Text(viewModel.getProviderName(provider))
                                    .tag(provider)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
                .padding(.trailing)
            }
            .background(Color(UIColor.systemBackground))

            // Location navigation buttons
            HStack(spacing: 8) {
                ForEach(0..<viewModel.locations.count, id: \.self) { index in
                    Button(action: {
                        navigateToLocation(index)
                    }) {
                        Text(viewModel.locations[index].name)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(4)
                    }
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal)
            .background(Color(UIColor.systemBackground))

            Divider()

            // Maps side by side
            HStack(spacing: 0) {
                // Left map (source)
                VStack(spacing: 0) {
                    mapView(
                        provider: viewModel.leftProvider,
                        googleState: leftGoogleState,
                        mapLibreState: leftMapLibreState,
                        mapKitState: leftMapKitState,
                        isSource: true
                    )

                    cameraInfoView(
                        provider: viewModel.leftProvider,
                        googleState: leftGoogleState,
                        mapLibreState: leftMapLibreState,
                        mapKitState: leftMapKitState,
                        label: "Source Camera"
                    )
                }

                Divider()

                // Right map (synced)
                VStack(spacing: 0) {
                    mapView(
                        provider: viewModel.rightProvider,
                        googleState: rightGoogleState,
                        mapLibreState: rightMapLibreState,
                        mapKitState: rightMapKitState,
                        isSource: false
                    )

                    cameraInfoView(
                        provider: viewModel.rightProvider,
                        googleState: rightGoogleState,
                        mapLibreState: rightMapLibreState,
                        mapKitState: rightMapKitState,
                        label: "Synced Camera"
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func mapView(
        provider: MapProvider,
        googleState: GoogleMapViewState,
        mapLibreState: MapLibreViewState,
        mapKitState: MapKitViewState,
        isSource: Bool
    ) -> some View {
        switch provider {
        case .googleMaps:
            GoogleMapView(
                state: googleState,
                onCameraMoveEnd: isSource ? { position in
                    syncToRight(position)
                } : nil,
                sdkInitialize: {
                    GMSServices.provideAPIKey(SampleConfig.googleMapsApiKey)
                }
            ) {
                mapContent()
            }

        case .mapLibre:
            MapLibreMapView(
                state: mapLibreState,
                onCameraMoveEnd: isSource ? { position in
                    syncToRight(position)
                } : nil
            ) {
                mapContent()
            }

        case .mapKit:
            MapKitMapView(
                state: mapKitState,
                onCameraMoveEnd: isSource ? { position in
                    syncToRight(position)
                } : nil
            ) {
                mapContent()
            }
        }
    }

    @ViewBuilder
    private func cameraInfoView(
        provider: MapProvider,
        googleState: GoogleMapViewState,
        mapLibreState: MapLibreViewState,
        mapKitState: MapKitViewState,
        label: String
    ) -> some View {
        Group {
            let position = getCameraPosition(
                provider: provider,
                googleState: googleState,
                mapLibreState: mapLibreState,
                mapKitState: mapKitState
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)

                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Lat: \(String(format: "%.5f", position.position.latitude))")
                            .font(.caption2)
                        Text("Lng: \(String(format: "%.5f", position.position.longitude))")
                            .font(.caption2)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Zoom: \(String(format: "%.2f", position.zoom))")
                            .font(.caption2)
                        Text("Tilt: \(String(format: "%.1f°", position.tilt))")
                            .font(.caption2)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Bearing: \(String(format: "%.1f°", position.bearing))")
                            .font(.caption2)
                        Text("Alt: \(String(format: "%.0f m", position.position.altitude ?? 0))")
                            .font(.caption2)
                    }
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(UIColor.secondarySystemBackground))
        }
    }

    private func getCameraPosition(
        provider: MapProvider,
        googleState: GoogleMapViewState,
        mapLibreState: MapLibreViewState,
        mapKitState: MapKitViewState
    ) -> MapCameraPosition {
        switch provider {
        case .googleMaps:
            return googleState.cameraPosition
        case .mapLibre:
            return mapLibreState.cameraPosition
        case .mapKit:
            return mapKitState.cameraPosition
        }
    }

    private func syncToRight(_ position: MapCameraPosition) {
        switch viewModel.rightProvider {
        case .googleMaps:
            viewModel.onLeftCameraChange(position, rightState: rightGoogleState)
        case .mapLibre:
            viewModel.onLeftCameraChange(position, rightState: rightMapLibreState)
        case .mapKit:
            viewModel.onLeftCameraChange(position, rightState: rightMapKitState)
        }
    }

    @MapViewContentBuilder
    private func mapContent() -> MapViewContent {
        // Draw bounds polylines for each location
        let location0 = viewModel.locations[0]
        let bounds0 = location0.bounds
        Polyline(
            state: PolylineState(
                points: [
                    bounds0.southWest!,
                    GeoPoint(latitude: bounds0.southWest!.latitude, longitude: bounds0.northEast!.longitude, altitude: 0),
                    bounds0.northEast!,
                    GeoPoint(latitude: bounds0.northEast!.latitude, longitude: bounds0.southWest!.longitude, altitude: 0),
                    bounds0.southWest!
                ],
                strokeColor: .systemRed,
                strokeWidth: 3.0,
                geodesic: true
            )
        )

        let location1 = viewModel.locations[1]
        let bounds1 = location1.bounds
        Polyline(
            state: PolylineState(
                points: [
                    bounds1.southWest!,
                    GeoPoint(latitude: bounds1.southWest!.latitude, longitude: bounds1.northEast!.longitude, altitude: 0),
                    bounds1.northEast!,
                    GeoPoint(latitude: bounds1.northEast!.latitude, longitude: bounds1.southWest!.longitude, altitude: 0),
                    bounds1.southWest!
                ],
                strokeColor: .systemRed,
                strokeWidth: 3.0,
                geodesic: true
            )
        )

        let location2 = viewModel.locations[2]
        let bounds2 = location2.bounds
        Polyline(
            state: PolylineState(
                points: [
                    bounds2.southWest!,
                    GeoPoint(latitude: bounds2.southWest!.latitude, longitude: bounds2.northEast!.longitude, altitude: 0),
                    bounds2.northEast!,
                    GeoPoint(latitude: bounds2.northEast!.latitude, longitude: bounds2.southWest!.longitude, altitude: 0),
                    bounds2.southWest!
                ],
                strokeColor: .systemRed,
                strokeWidth: 3.0,
                geodesic: true
            )
        )

        let location3 = viewModel.locations[3]
        let bounds3 = location3.bounds
        Polyline(
            state: PolylineState(
                points: [
                    bounds3.southWest!,
                    GeoPoint(latitude: bounds3.southWest!.latitude, longitude: bounds3.northEast!.longitude, altitude: 0),
                    bounds3.northEast!,
                    GeoPoint(latitude: bounds3.northEast!.latitude, longitude: bounds3.southWest!.longitude, altitude: 0),
                    bounds3.southWest!
                ],
                strokeColor: .systemRed,
                strokeWidth: 3.0,
                geodesic: true
            )
        )

        let location4 = viewModel.locations[4]
        let bounds4 = location4.bounds
        Polyline(
            state: PolylineState(
                points: [
                    bounds4.southWest!,
                    GeoPoint(latitude: bounds4.southWest!.latitude, longitude: bounds4.northEast!.longitude, altitude: 0),
                    bounds4.northEast!,
                    GeoPoint(latitude: bounds4.northEast!.latitude, longitude: bounds4.southWest!.longitude, altitude: 0),
                    bounds4.southWest!
                ],
                strokeColor: .systemRed,
                strokeWidth: 3.0,
                geodesic: true
            )
        )

        // Draw reference rectangles for zoom calibration
        let rectangles = viewModel.getReferenceRectangles()
        Polygon(state: rectangles[0])
        Polygon(state: rectangles[1])
        Polygon(state: rectangles[2])
        Polygon(state: rectangles[3])
        Polygon(state: rectangles[4])
    }

    private func navigateToLocation(_ index: Int) {
        let location = viewModel.locations[index]
        let position = MapCameraPosition(
            position: location.center,
            zoom: location.zoom,
            bearing: 0.0,
            tilt: 0.0
        )

        // Navigate both maps
        switch viewModel.leftProvider {
        case .googleMaps:
            leftGoogleState.moveCameraTo(cameraPosition: position, durationMillis: 1000)
        case .mapLibre:
            leftMapLibreState.moveCameraTo(cameraPosition: position, durationMillis: 1000)
        case .mapKit:
            leftMapKitState.moveCameraTo(cameraPosition: position, durationMillis: 1000)
        }

        switch viewModel.rightProvider {
        case .googleMaps:
            rightGoogleState.moveCameraTo(cameraPosition: position, durationMillis: 1000)
        case .mapLibre:
            rightMapLibreState.moveCameraTo(cameraPosition: position, durationMillis: 1000)
        case .mapKit:
            rightMapKitState.moveCameraTo(cameraPosition: position, durationMillis: 1000)
        }
    }
}
