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
            ) {}

        case .mapLibre:
            MapLibreMapView(
                state: mapLibreState,
                onCameraMoveEnd: isSource ? { position in
                    syncToRight(position)
                } : nil
            ) {}

        case .mapKit:
            MapKitMapView(
                state: mapKitState,
                onCameraMoveEnd: isSource ? { position in
                    syncToRight(position)
                } : nil
            ) {}
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
}
