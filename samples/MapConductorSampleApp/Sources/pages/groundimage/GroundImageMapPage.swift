import MapConductorCore
import MapConductorForGoogleMaps
import MapConductorForMapLibre
import SwiftUI
import UIKit

struct GroundImageMapPage: View {
    let onToggleSidebar: () -> Void

    @State private var provider: MapProvider
    @StateObject private var viewModel: GroundImagePageViewModel

    @StateObject private var googleState: GoogleMapViewState
    @StateObject private var mapLibreState: MapLibreViewState

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
    }

    var body: some View {
        DemoMapPageScaffold(provider: $provider, onToggleSidebar: onToggleSidebar) {
            ZStack(alignment: .bottomLeading) {
                GroundImageMapComponent(
                    provider: $provider,
                    googleState: googleState,
                    mapLibreState: mapLibreState,
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
