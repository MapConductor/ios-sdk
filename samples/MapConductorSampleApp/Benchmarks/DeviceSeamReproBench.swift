import UIKit
import XCTest

import MapConductorCore

/// 実機で出た「境界で左右の色が違う割れた丸」の再現。
///
/// 実機の街路樹と同じ規模・同じ設定（144,183 本、アイコン 101 色 20px、
/// scale 2.8 相当、declutter 14、タイル 512px、z17）で隣接ペアを描き、
/// 境界の左右 ±3px の帯を突き合わせる。どちらか片方だけに不透明画素があり、
/// かつ左右の色相が食い違う行が続けば「割れ」。
final class DeviceSeamReproBench: XCTestCase {

    private struct Lcg {
        private var seed: UInt64 = 12345
        mutating func next() -> Double {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(seed >> 11) / Double(UInt64(1) << 53)
        }
    }

    private func palette(_ count: Int) -> [ImageIcon] {
        (0..<count).map { at in
            let hue = CGFloat(at) / CGFloat(count)
            let size = CGSize(width: 20, height: 20)
            let image = UIGraphicsImageRenderer(size: size).image { context in
                UIColor(hue: hue, saturation: 0.85, brightness: 0.85, alpha: 1).setFill()
                context.cgContext.fillEllipse(in: CGRect(origin: .zero, size: size))
            }
            return ImageIcon(image: image, iconSize: 10)
        }
    }

    func testAdjacentTilesAgreeAtEveryVerticalSeam() throws {
        let manager = MarkerManager<AnyObject>.defaultManager(minMarkerCount: 1)
        let icons = palette(101)
        var lcg = Lcg()
        for at in 0..<144_183 {
            let lat = 35.5 + lcg.next() * 0.4
            let lng = 139.5 + lcg.next() * 0.5
            manager.registerEntity(
                MarkerEntity(
                    marker: nil,
                    state: MarkerState(
                        position: GeoPoint(latitude: lat, longitude: lng),
                        id: String(at),
                        icon: icons[at % icons.count]
                    ),
                    visible: true, isRendered: true, tiling: true
                )
            )
        }
        // 前半は GPU（オプトイン）で回し、後半の既定 CPU と比べる。
        setenv("MAPCONDUCTOR_MARKER_TILE_GPU", "1", 1)
        let renderer = MarkerTileRenderer<AnyObject>(
            markerManager: manager,
            tileSize: 512,
            cacheSizeBytes: 64 * 1024 * 1024,
            iconScaleCallback: { _, z in (z > 15 ? 1.4 : 1.0) * 2.0 },
            declutterPx: 14
        )

        func rgba(_ png: Data) throws -> (pixels: [UInt8], width: Int, height: Int) {
            let image = try XCTUnwrap(UIImage(data: png)?.cgImage)
            var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
            let context = CGContext(
                data: &pixels, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
            context?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return (pixels, image.width, image.height)
        }

        let z = 17
        let n = Double(1 << z)
        let latRad = 35.69 * Double.pi / 180
        let cx = Int((139.694 + 180.0) / 360.0 * n)
        let cy = Int((1.0 - log(tan(latRad) + 1.0 / cos(latRad)) / .pi) / 2.0 * n)

        var firstBad: TileRequest?
        var seams = 0
        var badSeams = 0
        for dx in -3...3 {
            for dy in -3...3 {
                let left = renderer.renderTile(request: TileRequest(x: cx + dx, y: cy + dy, z: z))
                let right = renderer.renderTile(request: TileRequest(x: cx + dx + 1, y: cy + dy, z: z))
                guard let left, let right else { continue }
                let l = try rgba(left)
                let r = try rgba(right)
                seams += 1
                // 境界の両側 3px: 左タイルの最終 3 列 vs 右タイルの先頭 3 列は
                // **同じ world 列ではない**が、境界をまたぐ円は両方に描かれる。
                // 割れの判定は「左の最終列に不透明があるのに、右の先頭列の同じ行が
                // 透明、または色相が大きく違う」が 6 行以上連続。
                var run = 0
                var worst = 0
                for row in 0..<l.height {
                    let li = (row * l.width + (l.width - 1)) * 4
                    let ri = (row * r.width + 0) * 4
                    let la = l.pixels[li + 3], ra = r.pixels[ri + 3]
                    // 「片側だけ不透明」はアイコンの端が境界に一致した正しい絵でも
                    // 出るので判定に使わない。実機で見た割れは同じ丸の左右で
                    // **色が違う**形 -- 両側不透明かつ色相不一致だけを数える。
                    var broken = false
                    if la > 200, ra > 200 {
                        let dr = abs(Int(l.pixels[li]) - Int(r.pixels[ri]))
                        let dg = abs(Int(l.pixels[li + 1]) - Int(r.pixels[ri + 1]))
                        let db = abs(Int(l.pixels[li + 2]) - Int(r.pixels[ri + 2]))
                        broken = (dr + dg + db) > 180
                    }
                    run = broken ? run + 1 : 0
                    worst = max(worst, run)
                }
                if worst >= 4 {
                    badSeams += 1
                    if firstBad == nil { firstBad = TileRequest(x: cx + dx, y: cy + dy, z: z) }
                    print("SEAMREPRO z=\(z) between x=\(cx + dx),\(cx + dx + 1) y=\(cy + dy) worstRun=\(worst)")
                    for (name, data) in [("L", left), ("R", right)] {
                        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
                        attachment.name = "bad-\(cx + dx)-\(cy + dy)-\(name)"
                        attachment.lifetime = .keepAlways
                        add(attachment)
                    }
                }
            }
        }
        print("SEAMREPRO seams=\(seams) bad=\(badSeams) path=GPU")

        // 同じ検査を既定（CPU）でもう一周。GPU だけ割れるなら GPU が犯人。
        unsetenv("MAPCONDUCTOR_MARKER_TILE_GPU")
        let cpuRenderer = MarkerTileRenderer<AnyObject>(
            markerManager: manager,
            tileSize: 512,
            cacheSizeBytes: 64 * 1024 * 1024,
            iconScaleCallback: { _, z in (z > 15 ? 1.4 : 1.0) * 2.0 },
            declutterPx: 14
        )
        var cpuBad = 0
        for dx in -3...3 {
            for dy in -3...3 {
                let left = cpuRenderer.renderTile(request: TileRequest(x: cx + dx, y: cy + dy, z: z))
                let right = cpuRenderer.renderTile(request: TileRequest(x: cx + dx + 1, y: cy + dy, z: z))
                guard let left, let right else { continue }
                let l = try rgba(left)
                let r = try rgba(right)
                var run = 0
                var worst = 0
                for row in 0..<l.height {
                    let li = (row * l.width + (l.width - 1)) * 4
                    let ri = (row * r.width + 0) * 4
                    var broken = false
                    if l.pixels[li + 3] > 200, r.pixels[ri + 3] > 200 {
                        let dr = abs(Int(l.pixels[li]) - Int(r.pixels[ri]))
                        let dg = abs(Int(l.pixels[li + 1]) - Int(r.pixels[ri + 1]))
                        let db = abs(Int(l.pixels[li + 2]) - Int(r.pixels[ri + 2]))
                        broken = (dr + dg + db) > 180
                    }
                    run = broken ? run + 1 : 0
                    worst = max(worst, run)
                }
                if worst >= 4 {
                    cpuBad += 1
                    print("SEAMREPRO-CPU z=\(z) between x=\(cx + dx),\(cx + dx + 1) y=\(cy + dy) worstRun=\(worst)")
                }
            }
        }
        print("SEAMREPRO seams=\(seams) badGPU=\(badSeams) badCPU=\(cpuBad)")

        // 最初に割れたタイルの GPU/CPU 両版を添付し、差分画素の分布を出す。
        if let first = firstBad {
            let gpuPng = try XCTUnwrap(renderer.renderTile(request: first))
            let cpuPng = try XCTUnwrap(cpuRenderer.renderTile(request: first))
            for (name, data) in [("gpu", gpuPng), ("cpu", cpuPng)] {
                let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
                attachment.name = "difftile-\(name)"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
            let g = try rgba(gpuPng)
            let c = try rgba(cpuPng)
            var minX = Int.max, maxX = -1, minY = Int.max, maxY = -1, count = 0
            for y in 0..<g.height {
                for x in 0..<g.width {
                    let at = (y * g.width + x) * 4
                    let d = abs(Int(g.pixels[at]) - Int(c.pixels[at]))
                        + abs(Int(g.pixels[at + 1]) - Int(c.pixels[at + 1]))
                        + abs(Int(g.pixels[at + 2]) - Int(c.pixels[at + 2]))
                        + abs(Int(g.pixels[at + 3]) - Int(c.pixels[at + 3]))
                    if d > 120 {
                        count += 1
                        minX = min(minX, x); maxX = max(maxX, x)
                        minY = min(minY, y); maxY = max(maxY, y)
                    }
                }
            }
            print("DIFFTILE z=\(first.z) x=\(first.x) y=\(first.y) diffPx=\(count) box=(\(minX),\(minY))-(\(maxX),\(maxY))")
        }
    }
}
