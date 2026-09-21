import MapConductorCore
import UIKit
import XCTest

/// 同じタイルを GPU と CPU で描いて、画素で突き合わせる。
///
/// 「格子（=CPU 描画）だと切れない、消す（=GPU 描画）と切れる」という観測の
/// 直接検証。理屈で経路を追うのではなく、両方の絵を並べて差分を見る。
/// アイコンは実物と同じ 101 種・10pt にして、GPU 側のアトラスも実物と同じ
/// 構成（≈101 セル）で組ませる。
///
/// 差が出たタイルは PNG を添付で残す。実機でしか意味がない（シミュレータの
/// Metal は別物）。
final class GpuCpuTileDiff: XCTestCase {

    private struct Lcg {
        private var seed: UInt64 = 12345
        mutating func next() -> Double {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(seed >> 11) / Double(UInt64(1) << 53)
        }
    }

    private func icons(_ count: Int) -> [ImageIcon] {
        (0..<count).map { at in
            let hue = CGFloat(at) / CGFloat(count)
            let size = CGSize(width: 20, height: 20)
            let image = UIGraphicsImageRenderer(size: size).image { context in
                UIColor(hue: hue, saturation: 0.8, brightness: 0.85, alpha: 1).setFill()
                context.cgContext.fillEllipse(in: CGRect(origin: .zero, size: size))
                UIColor.black.withAlphaComponent(0.6).setStroke()
                context.cgContext.setLineWidth(1.5)
                context.cgContext.strokeEllipse(in: CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1))
            }
            return ImageIcon(image: image, iconSize: 10)
        }
    }

    private func manager(_ count: Int) -> MarkerManager<AnyObject> {
        let manager = MarkerManager<AnyObject>.defaultManager(minMarkerCount: 1)
        let palette = icons(101)
        var lcg = Lcg()
        for at in 0..<count {
            let lat = 35.5 + lcg.next() * 0.4
            let lng = 139.5 + lcg.next() * 0.5
            manager.registerEntity(
                MarkerEntity(
                    marker: nil,
                    state: MarkerState(
                        position: GeoPoint(latitude: lat, longitude: lng),
                        id: String(at),
                        icon: palette[at % palette.count]
                    ),
                    visible: true,
                    isRendered: true,
                    tiling: true
                )
            )
        }
        return manager
    }

    private func rgba(_ png: Data) -> [UInt8]? {
        guard let image = UIImage(data: png)?.cgImage else { return nil }
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        guard let context = CGContext(
            data: &pixels, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return pixels
    }

    func testGpuMatchesCpu() throws {
        let live = manager(144_183)
        let scale = Double(UIScreen.main.scale)
        let callback: (MarkerState, Int) -> Double = { _, z in
            (z > 15 ? 1.4 : (z > 13 ? 1.0 : (z > 11 ? 0.7 : 0.5))) * scale
        }
        func makeRenderer() -> MarkerTileRenderer<AnyObject> {
            MarkerTileRenderer(
                markerManager: live,
                tileSize: 512,
                cacheSizeBytes: 32 * 1024 * 1024,
                iconScaleCallback: callback,
                declutterPx: 14
            )
        }
        // GPU 側を先に作る（env なし）。CPU 側は env を立ててから作る --
        // どちらを使うかは renderer ごとに最初の 1 回で決まる。
        let gpuSide = makeRenderer()
        setenv("MAPCONDUCTOR_MARKER_TILE_CPU", "1", 1)
        let cpuSide = makeRenderer()
        unsetenv("MAPCONDUCTOR_MARKER_TILE_CPU")

        var tiles = 0
        var mismatched = 0
        for z in [13, 14, 15, 16] {
            let n = Double(1 << z)
            let latRad = 35.68 * Double.pi / 180
            let cx = Int((139.75 + 180.0) / 360.0 * n)
            let cy = Int((1.0 - log(tan(latRad) + 1.0 / cos(latRad)) / .pi) / 2.0 * n)
            for dx in -2...2 {
                for dy in -2...2 {
                    let request = TileRequest(x: cx + dx, y: cy + dy, z: z)
                    let gpu = gpuSide.renderTile(request: request)
                    let cpu = cpuSide.renderTile(request: request)
                    tiles += 1
                    if gpu == nil, cpu == nil { continue }
                    guard let gpu, let cpu,
                          let gpuPixels = rgba(gpu), let cpuPixels = rgba(cpu),
                          gpuPixels.count == cpuPixels.count
                    else {
                        mismatched += 1
                        print("GPUDIFF z=\(z) x=\(cx + dx) y=\(cy + dy) one side nil or size mismatch")
                        continue
                    }
                    // ニアレストサンプリングの丸めで 1 段ずれる画素は許す。
                    // 数十 px 以上まとまって違うなら絵として別物。
                    var bad = 0
                    for at in stride(from: 0, to: gpuPixels.count, by: 4) {
                        let da = abs(Int(gpuPixels[at]) - Int(cpuPixels[at]))
                        let db = abs(Int(gpuPixels[at + 2]) - Int(cpuPixels[at + 2]))
                        let dalpha = abs(Int(gpuPixels[at + 3]) - Int(cpuPixels[at + 3]))
                        if da > 40 || db > 40 || dalpha > 40 { bad += 1 }
                    }
                    let badShare = Double(bad) / Double(gpuPixels.count / 4)
                    if bad > 500 {
                        mismatched += 1
                        print(String(format: "GPUDIFF z=%d x=%d y=%d badPx=%d (%.2f%%)",
                                     z, cx + dx, cy + dy, bad, badShare * 100))
                        for (name, data) in [("gpu", gpu), ("cpu", cpu)] {
                            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
                            attachment.name = "diff-z\(z)-\(cx + dx)-\(cy + dy)-\(name)"
                            attachment.lifetime = .keepAlways
                            add(attachment)
                        }
                    }
                }
            }
        }
        print("GPUDIFF total=\(tiles) mismatched=\(mismatched)")
        XCTAssertEqual(mismatched, 0, "GPU と CPU の絵が \(mismatched)/\(tiles) 枚で食い違う")
    }

    /// 同じ比較を**6 並列**で。実アプリはタイルサーバの 6 レーンから同時に
    /// 描かせるので、逐次で一致しても並列で壊れるなら（共有バッファの
    /// 上書き・アトラスの取り違え・padding の競合）ここで出る。
    /// 正解は逐次 CPU の絵。
    func testGpuMatchesCpuUnderConcurrency() throws {
        let live = manager(144_183)
        let scale = Double(UIScreen.main.scale)
        let callback: (MarkerState, Int) -> Double = { _, z in
            (z > 15 ? 1.4 : (z > 13 ? 1.0 : (z > 11 ? 0.7 : 0.5))) * scale
        }
        func makeRenderer() -> MarkerTileRenderer<AnyObject> {
            MarkerTileRenderer(
                markerManager: live,
                tileSize: 512,
                cacheSizeBytes: 64 * 1024 * 1024,
                iconScaleCallback: callback,
                declutterPx: 14
            )
        }
        let gpuSide = makeRenderer()
        setenv("MAPCONDUCTOR_MARKER_TILE_CPU", "1", 1)
        let cpuSide = makeRenderer()
        unsetenv("MAPCONDUCTOR_MARKER_TILE_CPU")

        var requests: [TileRequest] = []
        for z in [13, 14, 15, 16] {
            let n = Double(1 << z)
            let latRad = 35.68 * Double.pi / 180
            let cx = Int((139.75 + 180.0) / 360.0 * n)
            let cy = Int((1.0 - log(tan(latRad) + 1.0 / cos(latRad)) / .pi) / 2.0 * n)
            for dx in -2...2 {
                for dy in -2...2 {
                    requests.append(TileRequest(x: cx + dx, y: cy + dy, z: z))
                }
            }
        }
        // 正解（逐次 CPU）。
        var reference: [Int: Data?] = [:]
        for (at, request) in requests.enumerated() {
            reference[at] = cpuSide.renderTile(request: request)
        }
        // 3 周回す。周回ごとにキャッシュを捨て、毎回ナマの並列描画にする。
        var mismatched = 0
        for round in 0..<3 {
            gpuSide.clear()
            var results = [Data?](repeating: nil, count: requests.count)
            let lock = NSLock()
            DispatchQueue.concurrentPerform(iterations: requests.count) { at in
                let png = gpuSide.renderTile(request: requests[at])
                lock.lock(); results[at] = png; lock.unlock()
            }
            for (at, request) in requests.enumerated() {
                let expected = reference[at] ?? nil
                let actual = results[at]
                if expected == nil, actual == nil { continue }
                guard let expected, let actual,
                      let want = rgba(expected), let got = rgba(actual), want.count == got.count
                else {
                    mismatched += 1
                    print("GPUDIFF-C round=\(round) z=\(request.z) x=\(request.x) y=\(request.y) nil/size mismatch")
                    continue
                }
                var bad = 0
                for index in stride(from: 0, to: want.count, by: 4) {
                    if abs(Int(want[index]) - Int(got[index])) > 40
                        || abs(Int(want[index + 2]) - Int(got[index + 2])) > 40
                        || abs(Int(want[index + 3]) - Int(got[index + 3])) > 40 { bad += 1 }
                }
                if bad > 500 {
                    mismatched += 1
                    print("GPUDIFF-C round=\(round) z=\(request.z) x=\(request.x) y=\(request.y) badPx=\(bad)")
                    for (name, data) in [("gpu", actual), ("cpu", expected)] {
                        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
                        attachment.name = "cdiff-r\(round)-z\(request.z)-\(request.x)-\(request.y)-\(name)"
                        attachment.lifetime = .keepAlways
                        add(attachment)
                    }
                }
            }
        }
        print("GPUDIFF-C total=\(requests.count * 3) mismatched=\(mismatched)")
        XCTAssertEqual(mismatched, 0, "並列 GPU の絵が \(mismatched) 枚で逐次 CPU と食い違う")
    }
}
