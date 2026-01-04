import SwiftUI

struct StartUpPage: View {
    let onToggleSidebar: () -> Void

    init(onToggleSidebar: @escaping () -> Void = {}) {
        self.onToggleSidebar = onToggleSidebar
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .center, spacing: 12) {
                Image(systemName: "map.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 140, height: 140)
                    .foregroundColor(.primary)
                    .padding(.bottom, 10)

                Text("MAP CONDUCTOR")
                    .font(.system(size: 36, weight: .bold))
                Text("UNIFIED MAP SDK API")
                    .font(.system(size: 20, weight: .semibold))

                Divider()
                    .padding(.vertical, 12)

                Text("- Demo Application -")
                    .font(.system(size: 22, weight: .semibold))

                Text("A unified mapping library that provides a common API for multiple map providers including Google Maps, Mapbox, HERE, and ArcGIS. Write once, deploy across all major mapping platforms.")
                    .multilineTextAlignment(.leading)

                Text("Features")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 8) {
                    Text("- Multi-Provider Support: Seamlessly switch between Google Maps, Mapbox, HERE, and ArcGIS with a single API")
                    Text("- Unified Interface: Common abstractions for markers, circles, polylines, polygons, and ground overlays")
                    Text("- High Performance: Spatial indexing with hexagonal cells for efficient marker clustering")
                    Text("- Reactive State: Built on Kotlin StateFlow for reactive UI updates")
                    Text("- Jetpack Compose: Modern Android UI toolkit integration")
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button(action: onToggleSidebar) {
                    Text("Open menu")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .padding(.top, 20)
                .frame(maxWidth: .infinity)
                .background(Color.accentColor)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            .padding(20)
        }
    }
}
