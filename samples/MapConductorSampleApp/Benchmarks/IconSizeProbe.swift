import MapConductorCore
import UIKit
import XCTest

@testable import MapConductorSampleApp

/// 街路樹アイコンが実際に何ピクセルで描かれるかを、出来上がったタイルから測る。
///
/// 計算で追うと前提を一つ間違えるだけで答えが変わるので、描いた結果を数える。
/// マーカーを 1 本だけ置いたタイルを描き、色の付いた画素の外接矩形を取る。
final class IconSizeProbe: XCTestCase {

    func testIconPixelSizeOnDevice() {
        let screenScale = UIScreen.main.scale
        // プロバイダと同じ組み立て（GoogleMapMarkerController.setupTileRenderer）。
        let tileSize = 256 * max(1, Int(screenScale))
        let contentScale = Double(screenScale)

        let icon = StreetTreeIcons.palette(count: 1).first!
        let bitmap = icon.toBitmapIcon()

        let zoom = 16
        let n = Double(1 << zoom)
        let lat = 35.68, lon = 139.75
        let latRad = lat * .pi / 180
        let tx = (lon + 180.0) / 360.0 * n
        let ty = (1.0 - log(tan(latRad) + 1.0 / cos(latRad)) / .pi) / 2.0 * n

        let manager = MarkerManager<AnyObject>.defaultManager(minMarkerCount: 1)
        manager.registerEntity(
            MarkerEntity(
                marker: nil,
                state: MarkerState(position: GeoPoint(latitude: lat, longitude: lon), icon: icon),
                visible: true, isRendered: true, tiling: true
            )
        )

        // サンプルと同じ iconScaleCallback。zoom 16 は 1.4 の帯。
        // サンプルと同じ帯。@MainActor のビューモデルをここから呼べないので写す。
        let base: (MarkerState, Int) -> Double = { _, z in
            z > 15 ? 1.4 : (z > 13 ? 1.0 : (z > 11 ? 0.7 : 0.5))
        }
        let renderer = MarkerTileRenderer<AnyObject>(
            markerManager: manager,
            tileSize: tileSize,
            cacheSizeBytes: 1 << 20,
            iconScaleCallback: { state, z in base(state, z) * contentScale }
        )

        guard let data = renderer.renderTile(request: TileRequest(x: Int(tx), y: Int(ty), z: zoom)),
              let image = UIImage(data: data), let cg = image.cgImage else {
            return XCTFail("タイルが描けていない")
        }

        // 不透明な画素の外接矩形。
        let w = cg.width, h = cg.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let context = CGContext(
            data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

        var minX = w, maxX = -1, minY = h, maxY = -1
        for y in 0..<h {
            for x in 0..<w where pixels[(y * w + x) * 4 + 3] > 8 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }

        let drawnW = maxX - minX + 1, drawnH = maxY - minY + 1
        // 画面上の見かけの大きさ。タイルは 256pt として表示される。
        let apparentPt = Double(drawnW) / Double(w) * 256.0
        print(String(
            format: "ICONPROBE screenScale=%.0f tileSize=%d canvas=%dx%d bitmapIconSize=%.1f drawnPx=%dx%d apparentPt=%.2f",
            screenScale, tileSize, w, h, bitmap.size.width, drawnW, drawnH, apparentPt))
    }
}
