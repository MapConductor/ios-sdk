import MapConductorCore
import MapConductorForArcGIS
import MapConductorForGoogleMaps
import MapConductorForHERE
import MapConductorForMapKit
import MapConductorForMapLibre
import MapConductorForMapbox
import SwiftUI
import UIKit

struct TiltMapPage: View {
    let onToggleSidebar: () -> Void

    @State private var provider: MapProvider
    @StateObject private var viewModel: TiltMapPageViewModel
    @StateObject private var googleState: GoogleMapViewState
    @StateObject private var mapLibreState: MapLibreViewState
    @StateObject private var mapKitState: MapKitViewState
    @StateObject private var mapboxState: MapboxViewState
    @StateObject private var arcGISState: ArcGISMapViewState
    @StateObject private var hereState: HereMapViewState

    init(onToggleSidebar: @escaping () -> Void = {}) {
        self.onToggleSidebar = onToggleSidebar
        let viewModel = TiltMapPageViewModel()
        _viewModel = StateObject(wrappedValue: viewModel)
        _provider = State(initialValue: MapProvider.initial())
        _googleState = StateObject(
            wrappedValue: GoogleMapViewState(cameraPosition: viewModel.initCameraPosition)
        )
        _mapLibreState = StateObject(
            wrappedValue: MapLibreViewState(
                mapDesignType: MapLibreDesign.OsmBright,
                cameraPosition: viewModel.initCameraPosition
            )
        )
        _mapKitState = StateObject(
            wrappedValue: MapKitViewState(
                mapDesignType: MapKitMapDesign.Standard,
                cameraPosition: viewModel.initCameraPosition
            )
        )
        _mapboxState = StateObject(
            wrappedValue: MapboxViewState(
                cameraPosition: viewModel.initCameraPosition,
            )
        )
        _arcGISState = StateObject(
            wrappedValue: ArcGISMapViewState(
                mapDesignType: ArcGISDesign.OsmStandard,
                cameraPosition: viewModel.initCameraPosition
            )
        )
        _hereState = StateObject(
            wrappedValue: HereMapViewState(
                mapDesignType: HereMapDesign.NormalDay,
                cameraPosition: viewModel.initCameraPosition
            )
        )
    }

    var body: some View {
        DemoMapPageScaffold(provider: $provider, onToggleSidebar: onToggleSidebar) {
            ZStack(alignment: .bottomLeading) {
                SampleMapView(
                    provider: $provider,
                    googleState: googleState,
                    mapLibreState: mapLibreState,
                    mapKitState: mapKitState,
                    mapboxState: mapboxState,
                    arcGISState: arcGISState,
                    hereState: hereState,
                    onCameraMoveStart: viewModel.onMapCameraMoveStart,
                    onCameraMoveEnd: viewModel.onMapCameraMoveEnd
                ) {
                    MapViewContent()
                }
                .onAppear { viewModel.onMapViewChanged(activeState) }
                .onChange(of: provider) { _ in viewModel.onMapViewChanged(activeState) }

                VStack(spacing: 6) {
                    TiltCameraDiagram(tilt: viewModel.tilt)
                        .frame(height: 120)

                    HStack {
                        Text(String(format: "tilt: %.2f", viewModel.tilt))
                            .fixedSize()
                        Slider(
                            value: Binding(
                                get: { viewModel.tilt },
                                set: { viewModel.setTilt($0, state: activeState) }
                            ),
                            in: -60.0...60.0,
                            onEditingChanged: viewModel.setTiltEditing
                        )
                        .disabled(viewModel.disableSlider)
                    }
                }
                .padding(6)
                .frame(maxWidth: 600)
                .background(Color(UIColor.systemBackground).opacity(0.95))
                .cornerRadius(12)
                .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
    }

    private var activeState: any MapViewStateProtocol {
        switch provider {
        case .googleMaps: return googleState
        case .mapLibre: return mapLibreState
        case .mapKit: return mapKitState
        case .mapbox: return mapboxState
        case .arcGIS: return arcGISState
        case .here: return hereState
        }
    }
}

private struct TiltCameraDiagram: View {
    let tilt: Double

    var body: some View {
        Canvas { context, size in
            let width = size.width
            let height = size.height
            let groundY = height * 0.78
            let originX = width * 0.5
            let cameraY = height * 0.22
            let tiltRadians = min(abs(tilt), 90.0) * .pi / 180.0
            let targetDistance = min((groundY - cameraY) * tan(tiltRadians), width * 0.44)
            let targetX = tilt < 0.0 ? originX - targetDistance : originX
            let cameraX = tilt > 0.0 ? originX + targetDistance : originX

            strokeLine(
                in: &context,
                from: CGPoint(x: width * 0.08, y: groundY),
                to: CGPoint(x: width * 0.94, y: groundY),
                color: Color(red: 0.89, green: 0.88, blue: 0.93),
                width: 3,
                lineCap: .round
            )
            strokeLine(
                in: &context,
                from: CGPoint(x: cameraX, y: cameraY),
                to: CGPoint(x: cameraX, y: groundY),
                color: Color(red: 0.56, green: 0.53, blue: 0.60),
                width: 2
            )
            fillCircle(
                in: &context,
                center: CGPoint(x: cameraX, y: cameraY),
                radius: 8,
                color: Color(red: 0.36, green: 0.65, blue: 1.0)
            )
            fillCircle(
                in: &context,
                center: CGPoint(x: targetX, y: groundY),
                radius: 7,
                color: Color(red: 1.0, green: 0.38, blue: 0.35)
            )
            strokeLine(
                in: &context,
                from: CGPoint(x: cameraX, y: cameraY),
                to: CGPoint(x: tilt == 0.0 ? cameraX : targetX, y: groundY),
                color: Color(red: 1.0, green: 0.78, blue: 0.34),
                width: 4,
                lineCap: .round
            )

            var cameraBody = Path()
            cameraBody.move(to: CGPoint(x: cameraX - 12, y: cameraY - 8))
            cameraBody.addLine(to: CGPoint(x: cameraX + 14, y: cameraY - 4))
            cameraBody.addLine(to: CGPoint(x: cameraX + 10, y: cameraY + 10))
            cameraBody.addLine(to: CGPoint(x: cameraX - 12, y: cameraY + 8))
            cameraBody.closeSubpath()
            context.fill(cameraBody, with: .color(Color(red: 0.18, green: 0.16, blue: 0.22)))
            context.stroke(cameraBody, with: .color(.white.opacity(0.7)), lineWidth: 1.5)

            fillCircle(
                in: &context,
                center: CGPoint(x: originX, y: groundY),
                radius: 3.5,
                color: Color(red: 0.56, green: 0.53, blue: 0.60)
            )
            strokeLine(
                in: &context,
                from: CGPoint(x: min(cameraX, targetX), y: groundY + 12),
                to: CGPoint(x: max(cameraX, targetX), y: groundY + 12),
                color: Color(red: 0.72, green: 0.69, blue: 0.79),
                width: 2,
                lineCap: .round
            )
        }
    }

    private func strokeLine(
        in context: inout GraphicsContext,
        from start: CGPoint,
        to end: CGPoint,
        color: Color,
        width: CGFloat,
        lineCap: CGLineCap = .butt
    ) {
        var path = Path()
        path.move(to: start)
        path.addLine(to: end)
        context.stroke(
            path,
            with: .color(color),
            style: StrokeStyle(lineWidth: width, lineCap: lineCap)
        )
    }

    private func fillCircle(
        in context: inout GraphicsContext,
        center: CGPoint,
        radius: CGFloat,
        color: Color
    ) {
        let rect = CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        )
        context.fill(Path(ellipseIn: rect), with: .color(color))
    }
}
