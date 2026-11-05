import MapConductorCore
import UIKit
import XCTest

/// タイルの継ぎ目を**実機で描いて**画にする。
///
/// 索引の側は `MarkerTileSeamTests` が数で見ているが、あれは「A が描くはずの
/// マーカーを B も描くか」を集合として比べているだけで、絵は作らない。ここは
/// 隣り合う 4 枚を実機の Metal / CoreGraphics で焼き、1 枚に貼り合わせる。
/// 継ぎ目は貼り合わせた画像のちょうど真ん中の縦線と横線で、そこでアイコンが
/// 半分に切れていれば目で分かる。
///
/// シミュレータではなく実機なのは、GPU 経路がここでしか通らないため。
final class MarkerTileSeamShot: XCTestCase {

    private let tileSize = 512

    private struct Lcg {
        private var seed: UInt64 = 12345
        mutating func next() -> Double {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(seed >> 11) / Double(UInt64(1) << 53)
        }
    }

    private func manager(_ count: Int) -> MarkerManager<AnyObject> {
        let manager = MarkerManager<AnyObject>.defaultManager(minMarkerCount: 1)
        var lcg = Lcg()
        for _ in 0..<count {
            let lat = 35.5 + lcg.next() * 0.4
            let lng = 139.5 + lcg.next() * 0.5
            manager.registerEntity(
                MarkerEntity(
                    marker: nil,
                    state: MarkerState(position: GeoPoint(latitude: lat, longitude: lng)),
                    visible: true,
                    isRendered: true,
                    tiling: true
                )
            )
        }
        return manager
    }

    private func tileXY(zoom: Int) -> (Int, Int) {
        let n = Double(1 << zoom)
        let lat = 35.68 * .pi / 180
        return (
            Int((139.75 + 180.0) / 360.0 * n),
            Int((1.0 - log(tan(lat) + 1.0 / cos(lat)) / .pi) / 2.0 * n)
        )
    }

    func testSeamShot() throws {
        let live = manager(144_183)

        // declutter を切った対照も回す。
        //
        // 間引きが無ければタイルごとの判断は入らず、継ぎ目の食い違いは原理的に
        // 起きない。それでも `cutRuns` が数えるなら、それは物差しの偽陽性 --
        // アイコンの右端がたまたま境界に落ちた場合で、ピンは横より縦に長いので
        // 縦の継ぎ目にだけ出る。残った数をどう読むかの基準になる。
        for (zoom, declutter) in [(11, 14), (12, 14), (13, 14), (11, 0), (12, 0)] {
            let render = MarkerTileRenderer<AnyObject>(
                markerManager: live,
                tileSize: tileSize,
                cacheSizeBytes: 8 * 1024 * 1024,
                // わざと小さくする。
                //
                // サンプルと同じ大きさ（0.7 x 画面倍率）で焼くと、declutter を
                // 入れてもピンが重なって**タイルが赤一色**になり、1 個が半分に
                // 切れていても画素に出ない。実際にそれで 1 度見えなかった。
                // 間引きが効く条件は密度のほうなので、そこは 144,183 本のまま、
                // 絵だけ疎にする。
                iconScaleCallback: { _, _ in 0.2 },
                declutterPx: declutter
            )
            let (cx, cy) = tileXY(zoom: zoom)

            let side = tileSize * 2
            UIGraphicsBeginImageContextWithOptions(CGSize(width: side, height: side), true, 1.0)
            UIColor.white.setFill()
            UIRectFill(CGRect(x: 0, y: 0, width: side, height: side))
            var drawn = 0
            for dx in 0..<2 {
                for dy in 0..<2 {
                    guard let data = render.renderTile(
                        request: TileRequest(x: cx + dx, y: cy + dy, z: zoom)
                    ), let tile = UIImage(data: data) else { continue }
                    tile.draw(in: CGRect(
                        x: dx * tileSize, y: dy * tileSize,
                        width: tileSize, height: tileSize
                    ))
                    drawn += 1
                }
            }
            let stitched = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            XCTAssertEqual(drawn, 4, "z=\(zoom) d=\(declutter) で 4 枚そろわなかった")
            guard let stitched, let cg = stitched.cgImage else { return XCTFail("貼り合わせに失敗") }

            // 継ぎ目で断ち切られているアイコンを数える。
            //
            // またいでいるマーカーが両方のタイルに描かれていれば、境界の左右の
            // 列はどちらも絵になる。片方だけに描かれていると、片側が絵でもう
            // 片側が余白になり、**まっすぐな縦の縁**がそこにできる。アイコンの
            // 右端がたまたま境界に落ちた場合もそうなるが、そちらはピンの丸みに
            // 沿うので 1 行か 2 行で終わる。4 行以上続いたものだけ数える。
            let cutRuns = Self.straightEdgeRuns(cg, tileSize: tileSize)
            print("SEAMSHOT z=\(zoom) declutter=\(declutter) cutRuns=\(cutRuns.vertical)v \(cutRuns.horizontal)h")

            let whole = XCTAttachment(image: stitched)
            whole.name = "seam-z\(zoom)-d\(declutter)-2x2"
            whole.lifetime = .keepAlways
            add(whole)

            // 継ぎ目に沿った帯を丸ごと拡大する。
            //
            // 交点まわりだけを切り出すと、継ぎ目の長さの 1 割しか見えない。
            // z=11 で食い違うのはタイル 1 枚あたり数十個なので、そこに 1 個も
            // 入らずに「切れていない」と読めてしまう。継ぎ目の全長を細長く
            // 取って拡大すれば、またいでいるマーカーが一度に並ぶ。
            let band = 96
            let scale = 4
            for (name, crop) in [
                ("vertical", CGRect(x: tileSize - band / 2, y: tileSize / 2,
                                    width: band, height: tileSize)),
                ("horizontal", CGRect(x: tileSize / 2, y: tileSize - band / 2,
                                      width: tileSize, height: band)),
            ] {
                guard let piece = cg.cropping(to: crop) else { continue }
                let size = CGSize(width: crop.width * CGFloat(scale),
                                  height: crop.height * CGFloat(scale))
                UIGraphicsBeginImageContextWithOptions(size, true, 1.0)
                let context = UIGraphicsGetCurrentContext()
                context?.interpolationQuality = .none
                UIImage(cgImage: piece).draw(in: CGRect(origin: .zero, size: size))
                // 継ぎ目そのものに線を引く。どこが境界かを画の中で示す。
                context?.setStrokeColor(UIColor.blue.withAlphaComponent(0.5).cgColor)
                context?.setLineWidth(1.0)
                if name == "vertical" {
                    context?.move(to: CGPoint(x: size.width / 2, y: 0))
                    context?.addLine(to: CGPoint(x: size.width / 2, y: size.height))
                } else {
                    context?.move(to: CGPoint(x: 0, y: size.height / 2))
                    context?.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                }
                context?.strokePath()
                let magnified = UIGraphicsGetImageFromCurrentImageContext()
                UIGraphicsEndImageContext()
                if let magnified {
                    let shot = XCTAttachment(image: magnified)
                    shot.name = "seam-z\(zoom)-d\(declutter)-\(name)-x\(scale)"
                    shot.lifetime = .keepAlways
                    add(shot)
                }
            }
        }
    }

    /// 継ぎ目の左右（上下）で絵と余白が分かれている、4 以上の連続。
    private static func straightEdgeRuns(
        _ image: CGImage,
        tileSize: Int
    ) -> (vertical: Int, horizontal: Int) {
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return (0, 0) }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        // 背景は白で塗ってあるので、絵かどうかは「白でない」で見る。
        func inked(_ x: Int, _ y: Int) -> Bool {
            let at = (y * width + x) * 4
            return pixels[at] > 250 && pixels[at + 1] < 200 || pixels[at + 1] < 200
        }
        func runs(_ pairs: [(Bool, Bool)]) -> Int {
            var total = 0
            var run = 0
            for (near, far) in pairs {
                if near != far {
                    run += 1
                } else {
                    if run >= 4 { total += 1 }
                    run = 0
                }
            }
            if run >= 4 { total += 1 }
            return total
        }
        let vertical = runs((0..<height).map { (inked(tileSize - 1, $0), inked(tileSize, $0)) })
        let horizontal = runs((0..<width).map { (inked($0, tileSize - 1), inked($0, tileSize)) })
        return (vertical, horizontal)
    }
}
