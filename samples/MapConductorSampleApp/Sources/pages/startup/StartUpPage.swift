import SwiftUI
import UIKit

struct StartUpPage: View {
    let onToggleSidebar: () -> Void

    init(onToggleSidebar: @escaping () -> Void = {}) {
        self.onToggleSidebar = onToggleSidebar
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .center, spacing: 12) {
                if let image = loadPngImage(named: "mapcat") {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 300, height: 300)
                        .padding(.bottom, 10)
                } else {
                    // Fallback placeholder
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 140, height: 140)
                        .overlay(
                            Text("MAP\nCONDUCTOR")
                                .font(.system(size: 16, weight: .bold))
                                .multilineTextAlignment(.center)
                        )
                        .padding(.bottom, 10)
                    
                    Text("MAP CONDUCTOR")
                        .font(.system(size: 36, weight: .bold))
                    Text("UNIFIED MAP SDK API")
                        .font(.system(size: 20, weight: .semibold))
                }

                Divider()
                    .padding(.vertical, 5)

                Text("- Demo Application -")
                    .font(.system(size: 22, weight: .semibold))

                Text("A unified mapping library that provides a common API for multiple map providers including Google Maps, Mapbox, HERE, and ArcGIS. Write once, deploy across all major mapping platforms.")
                    .multilineTextAlignment(.leading)

                Text("Features")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 8) {
                    Text("- Multi-Provider Support: Seamlessly switch between MapKit, Google Maps, and MapLibre with a single API")
                    Text("- Unified Interface: Common abstractions for markers, circles, polylines, polygons, and ground overlays")
                    Text("- High Performance: Spatial indexing with hexagonal cells for efficient marker clustering")
                    Text("- Reactive State: Built on Kotlin StateFlow for reactive UI updates")
                    Text("- SwiftUI: Modern Swift UI toolkit integration")
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button(action: onToggleSidebar) {
                    Text("Open menu")
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 10)
                }
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity)
                .background(Color.accentColor)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            .padding(20)
        }
    }

    private func loadPngImage(named name: String) -> UIImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
              let data = try? Data(contentsOf: url),
              let image = UIImage(data: data) else {
            return nil
        }
        return image
    }
}
