import SwiftUI
import UIKit

struct DemoMapPageScaffold<Content: View>: View {
    @Binding var provider: MapProvider
    let onToggleSidebar: () -> Void
    let content: Content

    init(
        provider: Binding<MapProvider>,
        onToggleSidebar: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self._provider = provider
        self.onToggleSidebar = onToggleSidebar
        self.content = content()
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            content
                .ignoresSafeArea()

            HStack(spacing: 12) {
                Button(action: onToggleSidebar) {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)

                Picker("Provider", selection: $provider) {
                    ForEach(MapProvider.allCases) { provider in
                        Text(provider.rawValue).tag(provider)
                    }
                }
                .pickerStyle(MenuPickerStyle())
            }
            .padding(12)
            .background(Color(UIColor.systemBackground).opacity(0.95))
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
            .padding(.top, 12)
            .padding(.trailing, 12)
        }
    }
}
