import MapConductorCore
import MapConductorForGoogleMaps
import MapConductorForMapLibre
import MapConductorForMapKit
import MapConductorForMapbox
import MapConductorForArcGIS
import MapConductorForHERE
import SwiftUI
import UIKit

struct GroundImageMapPage: View {
    let onToggleSidebar: () -> Void

    @State private var provider: MapProvider
    @StateObject private var viewModel: GroundImagePageViewModel

    @StateObject private var googleState: GoogleMapViewState
    @StateObject private var mapLibreState: MapLibreViewState
    @StateObject private var mapKitState: MapKitViewState
    @StateObject private var mapboxState: MapboxViewState
    @StateObject private var arcGISState: ArcGISMapViewState
    @StateObject private var hereState: HereMapViewState

    init(onToggleSidebar: @escaping () -> Void = {}) {
        self.onToggleSidebar = onToggleSidebar

        let resources = GroundImageResources(
            image: Self.loadImage(named: "newark_nj_1922_0") ?? UIImage(),
            clickedImage: Self.loadImage(named: "newark_nj_1922_1") ?? UIImage()
        )

        let vm = GroundImagePageViewModel(resources: resources)
        _viewModel = StateObject(wrappedValue: vm)
        _provider = State(initialValue: MapProvider.initial())
        _googleState = StateObject(wrappedValue: GoogleMapViewState(cameraPosition: vm.initCameraPosition))
        _mapLibreState = StateObject(wrappedValue: MapLibreViewState(
            mapDesignType: MapLibreDesign.DemoTiles,
            cameraPosition: vm.initCameraPosition
        ))
        _mapKitState = StateObject(wrappedValue: MapKitViewState(
            mapDesignType: MapKitMapDesign.Standard,
            cameraPosition: vm.initCameraPosition
        ))
        _mapboxState = StateObject(wrappedValue: MapboxViewState(
            cameraPosition: vm.initCameraPosition
        ))
        _arcGISState = StateObject(wrappedValue: ArcGISMapViewState(
            mapDesignType: ArcGISDesign.OsmStandard,
            cameraPosition: vm.initCameraPosition
        ))
        _hereState = StateObject(wrappedValue: HereMapViewState(
            mapDesignType: HereMapDesign.NormalDay,
            cameraPosition: vm.initCameraPosition
        ))
    }

    var body: some View {
        DemoMapPageScaffold(provider: $provider, onToggleSidebar: onToggleSidebar) {
            ZStack(alignment: .bottomLeading) {
                GroundImageMapComponent(
                    provider: $provider,
                    googleState: googleState,
                    mapLibreState: mapLibreState,
                    mapKitState: mapKitState,
                    mapboxState: mapboxState,
                    arcGISState: arcGISState,
                    hereState: hereState,
                    viewModel: viewModel
                )

                VStack(alignment: .leading, spacing: 10) {
                    Text("Ground Image")
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text("Tap the image to toggle, drag markers to change bounds.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("opacity: \(String(format: "%.2f", viewModel.opacity))")
                            .font(.subheadline)
                            .foregroundColor(.primary)

                        Slider(
                            value: Binding(
                                get: { viewModel.opacity },
                                set: { viewModel.setOpacity($0) }
                            ),
                            in: 0.0...1.0
                        )
                    }
//
//                    VStack(alignment: .leading, spacing: 6) {
//                        Text("tilt: \(String(format: "%.2f", viewModel.tilt))")
//                            .font(.subheadline)
//                            .foregroundColor(.primary)
//
//                        TiltCameraDiagram(tilt: viewModel.tilt)
//                            .frame(height: 120)
//
//                        Slider(
//                            value: Binding(
//                                get: { viewModel.tilt },
//                                set: { newValue in
//                                    viewModel.setTilt(newValue)
//                                    let current = activeState.cameraPosition
//                                    activeState.moveCameraTo(
//                                        cameraPosition: current.copy(tilt: viewModel.tilt),
//                                        durationMillis: 0
//                                    )
//                                }
//                            ),
//                            in: -90.0...90.0
//                        )
//                    }

                    if let message = viewModel.message {
                        Text(message)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                    }
                }
                .padding(16)
                .background(Color(UIColor.systemBackground).opacity(0.95))
                .cornerRadius(12)
                .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
                .padding(.leading, 16)
                .padding(.bottom, 16)
            }
        }
    }

    private var activeState: any MapViewStateProtocol {
        switch provider {
        case .googleMaps:
            return googleState
        case .mapLibre:
            return mapLibreState
        case .mapKit:
            return mapKitState
        case .mapbox:
            return mapboxState
        case .arcGIS:
            return arcGISState
        case .here:
            return hereState
        }
    }

    private static func loadImage(named nameOrFilename: String) -> UIImage? {
        let nsFilename = nameOrFilename as NSString
        let base = nsFilename.deletingPathExtension
        let ext = nsFilename.pathExtension

        let extensions = ext.isEmpty ? ["png", "jpg", "jpeg"] : [ext]
        for ext in extensions {
            guard let url = Bundle.main.url(forResource: base, withExtension: ext),
                  let data = try? Data(contentsOf: url),
                  let image = UIImage(data: data) else {
                continue
            }
            return image
        }
        return nil
    }
}

private struct TiltCameraDiagram: View {
    let tilt: Double

    var body: some View {
        Canvas { context, size in
            let width = size.width
            let height = size.height
            let groundY = height * 0.78
            let originX = width * 0.38
            let originY = groundY
            let baseCameraY = height * 0.22
            let tiltAbs = min(abs(tilt), 90.0)
            let tiltRad = tiltAbs * .pi / 180.0
            let altitude = groundY - baseCameraY
            let targetDistance = min(altitude * tan(tiltRad), width * 0.44)
            let targetX = tilt < 0.0 ? originX + targetDistance : originX
            let targetY = groundY
            let cameraX = tilt < 0.0 ? originX : originX - targetDistance
            let cameraY = baseCameraY
            let sightEndX = tilt == 0.0 ? cameraX : targetX
            let sightEndY = targetY

            context.stroke(
                Path { path in
                    path.move(to: CGPoint(x: width * 0.08, y: groundY))
                    path.addLine(to: CGPoint(x: width * 0.94, y: groundY))
                },
                with: .color(Color(UIColor.systemGray4)),
                style: StrokeStyle(lineWidth: 3, lineCap: .round)
            )

            context.stroke(
                Path { path in
                    path.move(to: CGPoint(x: cameraX, y: cameraY))
                    path.addLine(to: CGPoint(x: cameraX, y: groundY))
                },
                with: .color(Color(UIColor.systemGray2)),
                lineWidth: 2
            )

            context.stroke(
                Path { path in
                    path.move(to: CGPoint(x: cameraX, y: cameraY))
                    path.addLine(to: CGPoint(x: sightEndX, y: sightEndY))
                },
                with: .color(Color(red: 1.0, green: 0.78, blue: 0.34)),
                style: StrokeStyle(lineWidth: 4, lineCap: .round)
            )

            context.fill(
                Path(ellipseIn: CGRect(x: cameraX - 8, y: cameraY - 8, width: 16, height: 16)),
                with: .color(Color(red: 0.36, green: 0.65, blue: 1.0))
            )
            context.fill(
                Path(ellipseIn: CGRect(x: targetX - 7, y: targetY - 7, width: 14, height: 14)),
                with: .color(Color(red: 1.0, green: 0.38, blue: 0.35))
            )

            var cameraBody = Path()
            cameraBody.move(to: CGPoint(x: cameraX - 12, y: cameraY - 8))
            cameraBody.addLine(to: CGPoint(x: cameraX + 14, y: cameraY - 4))
            cameraBody.addLine(to: CGPoint(x: cameraX + 10, y: cameraY + 10))
            cameraBody.addLine(to: CGPoint(x: cameraX - 12, y: cameraY + 8))
            cameraBody.closeSubpath()
            context.fill(cameraBody, with: .color(Color(UIColor.secondarySystemBackground)))
            context.stroke(cameraBody, with: .color(.white.opacity(0.7)), lineWidth: 1.5)

            context.fill(
                Path(ellipseIn: CGRect(x: originX - 3.5, y: originY - 3.5, width: 7, height: 7)),
                with: .color(Color(UIColor.systemGray2))
            )
            context.stroke(
                Path { path in
                    path.move(to: CGPoint(x: min(cameraX, targetX), y: groundY + 12))
                    path.addLine(to: CGPoint(x: max(cameraX, targetX), y: groundY + 12))
                },
                with: .color(Color(UIColor.systemGray3)),
                style: StrokeStyle(lineWidth: 2, lineCap: .round)
            )
        }
    }
}
