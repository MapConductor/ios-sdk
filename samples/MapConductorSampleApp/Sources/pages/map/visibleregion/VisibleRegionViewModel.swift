import Foundation
import MapConductorCore

/// 表示領域サンプルの状態。
///
/// 表示に使う値は ``VisibleRegionMapComponent`` が `MapCameraPosition` から直接読むので、
/// ここは「いまどのカメラか」を持つだけ。react-sdk の `VisibleRegionPage.tsx` が
/// `useState<MapCameraPosition>` 1 本で済ませているのと同じ形にしてある。
@MainActor
final class VisibleRegionViewModel: ObservableObject {
    @Published var cameraPosition: MapCameraPosition?

    func onCameraChanged(_ camera: MapCameraPosition) {
        cameraPosition = camera
    }
}
