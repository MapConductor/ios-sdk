import SwiftUI
import MapConductorCore

/// A view that represents a single point in a heatmap.
/// This view must be used inside a HeatmapOverlay view.
///
/// Example:
/// ```swift
/// HeatmapOverlay {
///     ForEach(points) { pointState in
///         HeatmapPoint(state: pointState)
///     }
/// }
/// ```
public struct HeatmapPointView: View {
    @Environment(\.heatmapPointCollector) private var collector
    private let state: HeatmapPointState

    public init(state: HeatmapPointState) {
        self.state = state
    }

    public init(
        position: GeoPoint,
        weight: Double = 1.0,
        id: String? = nil
    ) {
        self.state = HeatmapPointState(
            position: position,
            weight: weight,
            id: id
        )
    }

    public var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                guard let collector = collector else {
                    fatalError("HeatmapPoint must be used inside HeatmapOverlay")
                }
                collector.add(state: state)
            }
            .onDisappear {
                collector?.remove(id: state.id)
            }
    }
}
