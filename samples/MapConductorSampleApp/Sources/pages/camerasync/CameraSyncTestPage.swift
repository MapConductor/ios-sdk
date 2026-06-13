import MapConductorCore
import MapConductorForGoogleMaps
import MapConductorForMapLibre
import MapConductorForMapKit
import MapConductorForMapbox
import MapConductorForArcGIS
import MapConductorForHERE
import SwiftUI
import GoogleMaps

struct CameraSyncTestPage: View {
    let onToggleSidebar: () -> Void

    @StateObject private var viewModel = CameraSyncTestViewModel()
    @StateObject private var leftGoogleState: GoogleMapViewState
    @StateObject private var leftMapLibreState: MapLibreViewState
    @StateObject private var leftMapKitState: MapKitViewState
    @StateObject private var leftMapboxState: MapboxViewState
    @StateObject private var leftArcGISState: ArcGISMapViewState
    @StateObject private var leftHereState: HereMapViewState

    @StateObject private var rightGoogleState: GoogleMapViewState
    @StateObject private var rightMapLibreState: MapLibreViewState
    @StateObject private var rightMapKitState: MapKitViewState
    @StateObject private var rightMapboxState: MapboxViewState
    @StateObject private var rightArcGISState: ArcGISMapViewState
    @StateObject private var rightHereState: HereMapViewState

    // Camera state displayed in the info panels
    @State private var leftCameraPosition: MapCameraPosition
    @State private var rightCameraPosition: MapCameraPosition

    // Feedback-loop guard: when we move a map programmatically, ignore the resulting
    // camera callbacks until the move settles (mirrors Android's programmatic key logic).
    @State private var programmaticLeftKey: Int64? = nil
    @State private var programmaticLeftTarget: MapCameraPosition? = nil
    @State private var programmaticLeftUntilMs: Double = 0
    @State private var programmaticLeftSinceMs: Double = 0

    @State private var programmaticRightKey: Int64? = nil
    @State private var programmaticRightTarget: MapCameraPosition? = nil
    @State private var programmaticRightUntilMs: Double = 0
    @State private var programmaticRightSinceMs: Double = 0

    // Move-time throttle so we don't overwhelm the target SDK (~30 fps).
    @State private var lastLeftMoveSyncAtMs: Double = 0
    @State private var lastRightMoveSyncAtMs: Double = 0

    private let programmaticTtlMs: Double = 1200
    private let programmaticGraceMs: Double = 250
    private let moveSyncIntervalMs: Double = 33

    init(onToggleSidebar: @escaping () -> Void = {}) {
        self.onToggleSidebar = onToggleSidebar
        let vm = CameraSyncTestViewModel()
        _viewModel = StateObject(wrappedValue: vm)
        _leftCameraPosition = State(initialValue: vm.initCameraPosition)
        _rightCameraPosition = State(initialValue: vm.initCameraPosition)

        _leftGoogleState = StateObject(wrappedValue: GoogleMapViewState(cameraPosition: vm.initCameraPosition))
        _leftMapLibreState = StateObject(wrappedValue: MapLibreViewState(mapDesignType: MapLibreDesign.OsmBright, cameraPosition: vm.initCameraPosition))
        _leftMapKitState = StateObject(wrappedValue: MapKitViewState(mapDesignType: MapKitMapDesign.Standard, cameraPosition: vm.initCameraPosition))
        _leftMapboxState = StateObject(wrappedValue: MapboxViewState(cameraPosition: vm.initCameraPosition))
        _leftArcGISState = StateObject(wrappedValue: ArcGISMapViewState(mapDesignType: ArcGISDesign.OsmStandard, cameraPosition: vm.initCameraPosition))
        _leftHereState = StateObject(wrappedValue: HereMapViewState(mapDesignType: HereMapDesign.NormalDay, cameraPosition: vm.initCameraPosition))

        _rightGoogleState = StateObject(wrappedValue: GoogleMapViewState(cameraPosition: vm.initCameraPosition))
        _rightMapLibreState = StateObject(wrappedValue: MapLibreViewState(mapDesignType: MapLibreDesign.OsmBright, cameraPosition: vm.initCameraPosition))
        _rightMapKitState = StateObject(wrappedValue: MapKitViewState(mapDesignType: MapKitMapDesign.Standard, cameraPosition: vm.initCameraPosition))
        _rightMapboxState = StateObject(wrappedValue: MapboxViewState(cameraPosition: vm.initCameraPosition))
        _rightArcGISState = StateObject(wrappedValue: ArcGISMapViewState(mapDesignType: ArcGISDesign.OsmStandard, cameraPosition: vm.initCameraPosition))
        _rightHereState = StateObject(wrappedValue: HereMapViewState(mapDesignType: HereMapDesign.NormalDay, cameraPosition: vm.initCameraPosition))
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
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Left (Source)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Picker("Left", selection: $viewModel.leftProvider) {
                            ForEach(MapProvider.allCases) { provider in
                                Text(viewModel.getProviderName(provider)).tag(provider)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Right (Synced)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Picker("Right", selection: $viewModel.rightProvider) {
                            ForEach(MapProvider.allCases) { provider in
                                Text(viewModel.getProviderName(provider)).tag(provider)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
                .padding(.trailing)
            }
            .background(Color(UIColor.systemBackground))

            // Location navigation buttons
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(0..<viewModel.locations.count, id: \.self) { index in
                        Button(action: { navigateToLocation(index) }) {
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
                .padding(.horizontal)
            }
            .padding(.vertical, 8)
            .background(Color(UIColor.systemBackground))

            Divider()

            // Adaptive layout: portrait → vertical stack, landscape → horizontal stack
            GeometryReader { geometry in
                let isPortrait = geometry.size.height > geometry.size.width
                if isPortrait {
                    VStack(spacing: 0) {
                        mapPane(side: .left)
                        Divider()
                        mapPane(side: .right)
                    }
                } else {
                    HStack(spacing: 0) {
                        mapPane(side: .left)
                        Divider()
                        mapPane(side: .right)
                    }
                }
            }
        }
    }

    // MARK: - Map pane

    @ViewBuilder
    private func mapPane(side: ActiveMapPane) -> some View {
        let provider = side == .left ? viewModel.leftProvider : viewModel.rightProvider
        ZStack(alignment: .bottomLeading) {
            buildMapView(
                provider: provider,
                side: side
            )
            cameraInfoPanel(
                side: side,
                label: side == .left ? "Source Camera" : "Synced Camera"
            )
            .padding(8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func buildMapView(provider: MapProvider, side: ActiveMapPane) -> some View {
        let onMove: OnCameraMoveHandler = { position in handleCameraMove(position, from: side) }
        let onMoveEnd: OnCameraMoveHandler = { position in handleCameraMoveEnd(position, from: side) }

        switch provider {
        case .googleMaps:
            if let apiKey = SampleConfig.googleMapsApiKey {
                GoogleMapView(
                    state: side == .left ? leftGoogleState : rightGoogleState,
                    onCameraMove: onMove,
                    onCameraMoveEnd: onMoveEnd,
                    sdkInitialize: { GMSServices.provideAPIKey(apiKey) }
                ) { mapContent() }
            } else {
                Text("Google Maps is not available due to no API key")
            }

        case .mapLibre:
            MapLibreMapView(
                state: side == .left ? leftMapLibreState : rightMapLibreState,
                onCameraMove: onMove,
                onCameraMoveEnd: onMoveEnd
            ) { mapContent() }

        case .mapKit:
            MapKitMapView(
                state: side == .left ? leftMapKitState : rightMapKitState,
                onCameraMove: onMove,
                onCameraMoveEnd: onMoveEnd
            ) { mapContent() }

        case .mapbox:
            if let accessToken = SampleConfig.mapboxAccessToken {
                MapboxMapView(
                    state: side == .left ? leftMapboxState : rightMapboxState,
                    onCameraMove: onMove,
                    onCameraMoveEnd: onMoveEnd,
                    sdkInitialize: { initializeMapbox(accessToken: accessToken) },
                    content: { mapContent() }
                )
            } else {
                Text("Mapbox is not available due to no access token")
            }

        case .arcGIS:
            if let apiKey = SampleConfig.arcGISApiKey {
                ArcGISMapView(
                    state: side == .left ? leftArcGISState : rightArcGISState,
                    onCameraMove: onMove,
                    onCameraMoveEnd: onMoveEnd,
                    sdkInitialize: { _ = arcGISApiKeyInitialize(apiKey: apiKey) }
                ) { mapContent() }
            } else {
                Text("ArcGIS is not available due to no API key")
            }

        case .here:
            if let accessKey = SampleConfig.hereAccessKeyId,
               let accessSecret = SampleConfig.hereAccessKeySecret {
                HereMapView(
                    state: side == .left ? leftHereState : rightHereState,
                    onCameraMove: onMove,
                    onCameraMoveEnd: onMoveEnd,
                    sdkInitialize: {
                        do {
                            try hereKeyInitialize(accessKeyId: accessKey, accessKeySecret: accessSecret)
                        } catch {
                            NSLog("[MapConductor] HERE authentication failed: %@", String(describing: error))
                        }
                    }
                ) { mapContent() }
            } else {
                Text("Here is not available due to no API key")
            }
        }
    }

    // MARK: - Sync logic

    private func handleCameraMove(_ position: MapCameraPosition, from side: ActiveMapPane) {
        let now = nowMs()
        switch side {
        case .left:
            if programmaticLeftKey != nil {
                if now > programmaticLeftUntilMs {
                    clearProgrammatic(.left)
                } else {
                    let age = now - programmaticLeftSinceMs
                    if age <= programmaticGraceMs || isProgrammaticMove(.left, position, now) {
                        leftCameraPosition = position
                        return
                    }
                    clearProgrammatic(.left)
                }
            }
            if now - lastLeftMoveSyncAtMs < moveSyncIntervalMs { return }
            lastLeftMoveSyncAtMs = now
            leftCameraPosition = position
            rightCameraPosition = position
            markProgrammatic(.right, target: position, now: now)
            moveRight(to: position, duration: 0)

        case .right:
            if programmaticRightKey != nil {
                if now > programmaticRightUntilMs {
                    clearProgrammatic(.right)
                } else {
                    let age = now - programmaticRightSinceMs
                    if age <= programmaticGraceMs || isProgrammaticMove(.right, position, now) {
                        rightCameraPosition = position
                        return
                    }
                    clearProgrammatic(.right)
                }
            }
            if now - lastRightMoveSyncAtMs < moveSyncIntervalMs { return }
            lastRightMoveSyncAtMs = now
            rightCameraPosition = position
            leftCameraPosition = position
            markProgrammatic(.left, target: position, now: now)
            moveLeft(to: position, duration: 0)
        }
    }

    private func handleCameraMoveEnd(_ position: MapCameraPosition, from side: ActiveMapPane) {
        let now = nowMs()
        switch side {
        case .left:
            if programmaticLeftKey != nil {
                if now > programmaticLeftUntilMs {
                    clearProgrammatic(.left)
                } else {
                    let age = now - programmaticLeftSinceMs
                    if age <= programmaticGraceMs || isProgrammaticMove(.left, position, now) {
                        leftCameraPosition = position
                        return
                    }
                    clearProgrammatic(.left)
                }
            }
            leftCameraPosition = position
            rightCameraPosition = position
            markProgrammatic(.right, target: position, now: now)
            moveRight(to: position, duration: 0)

        case .right:
            if programmaticRightKey != nil {
                if now > programmaticRightUntilMs {
                    clearProgrammatic(.right)
                } else {
                    let age = now - programmaticRightSinceMs
                    if age <= programmaticGraceMs || isProgrammaticMove(.right, position, now) {
                        rightCameraPosition = position
                        return
                    }
                    clearProgrammatic(.right)
                }
            }
            rightCameraPosition = position
            leftCameraPosition = position
            markProgrammatic(.left, target: position, now: now)
            moveLeft(to: position, duration: 0)
        }
    }

    // MARK: - Programmatic move helpers

    private func cameraKey(_ camera: MapCameraPosition) -> Int64 {
        let latE5 = Int64(camera.position.latitude * 1e5)
        let lonE5 = Int64(camera.position.longitude * 1e5)
        let zoom100 = Int64(camera.zoom * 100)
        let bearing10 = Int64(camera.bearing * 10)
        return ((latE5 * 31 &+ lonE5) * 31 &+ zoom100) * 31 &+ bearing10
    }

    private func bearingDelta(_ a: Double, _ b: Double) -> Double {
        let d = ((a - b).truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        return d > 180 ? 360 - d : d
    }

    private func isCloseToTarget(_ camera: MapCameraPosition, _ target: MapCameraPosition) -> Bool {
        abs(camera.position.latitude - target.position.latitude) < 0.0012 &&
        abs(camera.position.longitude - target.position.longitude) < 0.0012 &&
        abs(camera.zoom - target.zoom) < 0.75 &&
        bearingDelta(camera.bearing, target.bearing) < 12 &&
        abs(camera.tilt - target.tilt) < 6
    }

    private func isProgrammaticMove(_ side: ActiveMapPane, _ camera: MapCameraPosition, _ now: Double) -> Bool {
        let (key, target, until): (Int64?, MapCameraPosition?, Double)
        switch side {
        case .left:  (key, target, until) = (programmaticLeftKey, programmaticLeftTarget, programmaticLeftUntilMs)
        case .right: (key, target, until) = (programmaticRightKey, programmaticRightTarget, programmaticRightUntilMs)
        }
        guard key != nil else { return false }
        if now > until { return false }
        if cameraKey(camera) == key { return true }
        return target.map { isCloseToTarget(camera, $0) } ?? false
    }

    private func markProgrammatic(_ side: ActiveMapPane, target: MapCameraPosition, now: Double) {
        let key = cameraKey(target)
        switch side {
        case .left:
            programmaticLeftKey = key
            programmaticLeftTarget = target
            programmaticLeftSinceMs = now
            programmaticLeftUntilMs = now + programmaticTtlMs
        case .right:
            programmaticRightKey = key
            programmaticRightTarget = target
            programmaticRightSinceMs = now
            programmaticRightUntilMs = now + programmaticTtlMs
        }
    }

    private func clearProgrammatic(_ side: ActiveMapPane) {
        switch side {
        case .left:
            programmaticLeftKey = nil; programmaticLeftTarget = nil
            programmaticLeftSinceMs = 0; programmaticLeftUntilMs = 0
        case .right:
            programmaticRightKey = nil; programmaticRightTarget = nil
            programmaticRightSinceMs = 0; programmaticRightUntilMs = 0
        }
    }

    // MARK: - Map movement

    private func moveLeft(to position: MapCameraPosition, duration: Int64) {
        switch viewModel.leftProvider {
        case .googleMaps:  leftGoogleState.moveCameraTo(cameraPosition: position, durationMillis: duration)
        case .mapLibre:    leftMapLibreState.moveCameraTo(cameraPosition: position, durationMillis: duration)
        case .mapKit:      leftMapKitState.moveCameraTo(cameraPosition: position, durationMillis: duration)
        case .mapbox:      leftMapboxState.moveCameraTo(cameraPosition: position, durationMillis: duration)
        case .arcGIS:      leftArcGISState.moveCameraTo(cameraPosition: position, durationMillis: duration)
        case .here:        leftHereState.moveCameraTo(cameraPosition: position, durationMillis: duration)
        }
    }

    private func moveRight(to position: MapCameraPosition, duration: Int64) {
        switch viewModel.rightProvider {
        case .googleMaps:  rightGoogleState.moveCameraTo(cameraPosition: position, durationMillis: duration)
        case .mapLibre:    rightMapLibreState.moveCameraTo(cameraPosition: position, durationMillis: duration)
        case .mapKit:      rightMapKitState.moveCameraTo(cameraPosition: position, durationMillis: duration)
        case .mapbox:      rightMapboxState.moveCameraTo(cameraPosition: position, durationMillis: duration)
        case .arcGIS:      rightArcGISState.moveCameraTo(cameraPosition: position, durationMillis: duration)
        case .here:        rightHereState.moveCameraTo(cameraPosition: position, durationMillis: duration)
        }
    }

    // MARK: - Location navigation

    private func navigateToLocation(_ index: Int) {
        let location = viewModel.locations[index]
        let position = MapCameraPosition(position: location.center, zoom: location.zoom, bearing: 0.0, tilt: 0.0)
        let now = nowMs()
        moveLeft(to: position, duration: 1000)
        moveRight(to: position, duration: 1000)
        leftCameraPosition = position
        rightCameraPosition = position
        markProgrammatic(.left, target: position, now: now)
        markProgrammatic(.right, target: position, now: now)
        // Extend the guard to cover the full 1s animation window.
        programmaticLeftUntilMs = now + 1000 + programmaticTtlMs
        programmaticRightUntilMs = now + 1000 + programmaticTtlMs
    }

    // MARK: - Camera info panel

    @ViewBuilder
    private func cameraInfoPanel(side: ActiveMapPane, label: String) -> some View {
        let position = side == .left ? leftCameraPosition : rightCameraPosition
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .fontWeight(.bold)
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Lat: \(String(format: "%.5f", position.position.latitude))").font(.caption2)
                    Text("Lng: \(String(format: "%.5f", position.position.longitude))").font(.caption2)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Zoom: \(String(format: "%.2f", position.zoom))").font(.caption2)
                    Text("Tilt: \(String(format: "%.1f°", position.tilt))").font(.caption2)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bearing: \(String(format: "%.1f°", position.bearing))").font(.caption2)
                    Text("Alt: \(String(format: "%.0f m", position.position.altitude ?? 0))").font(.caption2)
                }
            }
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Map overlays

    @MapViewContentBuilder
    private func mapContent() -> MapViewContent {
        ForArray(viewModel.locations) { location in
            let sw = location.bounds.southWest!
            let ne = location.bounds.northEast!
            Polyline(state: PolylineState(
                points: [
                    sw,
                    GeoPoint(latitude: sw.latitude, longitude: ne.longitude, altitude: 0),
                    ne,
                    GeoPoint(latitude: ne.latitude, longitude: sw.longitude, altitude: 0),
                    sw,
                ],
                strokeColor: .systemRed,
                strokeWidth: 3.0,
                geodesic: true
            ))
        }
        ForArray(viewModel.getReferenceRectangles()) { rect in
            Polygon(state: rect)
        }
    }

    // MARK: - Utilities

    private func nowMs() -> Double {
        ProcessInfo.processInfo.systemUptime * 1000
    }
}

private enum ActiveMapPane {
    case left, right
}
