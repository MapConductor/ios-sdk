import SwiftUI

// Environment key for HeatmapPointCollector
private struct HeatmapPointCollectorKey: EnvironmentKey {
    static let defaultValue: HeatmapPointCollector? = nil
}

extension EnvironmentValues {
    var heatmapPointCollector: HeatmapPointCollector? {
        get { self[HeatmapPointCollectorKey.self] }
        set { self[HeatmapPointCollectorKey.self] = newValue }
    }
}
