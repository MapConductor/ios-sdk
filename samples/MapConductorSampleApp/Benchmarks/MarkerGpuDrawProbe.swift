import Metal
import UIKit
import XCTest

/// マーカータイルの描画を GPU に載せたら何 ms になるかを、本実装の前に測る。
///
/// 実機の内訳（`TilePhaseProbe`）では、ズーム 11 のタイル 1 枚 143ms のうち
/// 115ms が問い合わせ以外 -- 準備と描画だった。そこが本題なので、同じ枚数の
/// アイコンを CPU（CoreGraphics）と GPU（Metal）で貼って比べる。
///
/// `MetalTileRasterizer`（ios-vectortile）と同じ骨格を使う: オフスクリーンへ
/// 描いて読み戻し、PNG 化は core の Rust エンコーダに渡す。違うのは中身で、
/// あちらは単色の三角形、こちらはテクスチャ付きのクアッドをインスタンスで
/// 並べる -- 同じ絵を位置だけ変えて 1 万〜2 万回、GPU がいちばん得意な形。
final class MarkerGpuDrawProbe: XCTestCase {

    private static let shader = """
    #include <metal_stdlib>
    using namespace metal;

    struct Instance { float2 centre; float radius; float pad; };

    struct VertexOut {
        float4 position [[position]];
        float2 uv;
    };

    vertex VertexOut icon_vertex(uint vid [[vertex_id]],
                                 uint iid [[instance_id]],
                                 constant Instance *instances [[buffer(0)]],
                                 constant float &extent [[buffer(1)]]) {
        // 三角形 2 枚ぶんの 6 頂点を id から組み立てる。頂点バッファは要らない。
        const float2 corners[6] = { float2(-1,-1), float2(1,-1), float2(-1,1),
                                    float2(1,-1),  float2(1,1),  float2(-1,1) };
        float2 corner = corners[vid];
        Instance inst = instances[iid];
        float2 px = inst.centre + corner * inst.radius;
        float2 unit = px / extent;

        VertexOut out;
        out.position = float4(unit.x * 2.0 - 1.0, 1.0 - unit.y * 2.0, 0.0, 1.0);
        out.uv = corner * 0.5 + 0.5;
        return out;
    }

    fragment float4 icon_fragment(VertexOut in [[stage_in]],
                                  texture2d<float> atlas [[texture(0)]],
                                  sampler smp [[sampler(0)]]) {
        return atlas.sample(smp, in.uv);
    }
    """

    private func ms(_ body: () -> Void) -> Double {
        let t = DispatchTime.now().uptimeNanoseconds
        body()
        return Double(DispatchTime.now().uptimeNanoseconds - t) / 1_000_000
    }

    /// 14pt の円を 1 枚。実際の街路樹アイコンと同じ大きさ。
    private func iconImage(sizePx: Int) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: sizePx, height: sizePx), format: format).image { ctx in
            UIColor.systemRed.setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x: 0, y: 0, width: sizePx, height: sizePx))
        }
    }

    func testGpuVersusCoreGraphics() throws {
        let tilePx = 768               // プロバイダが使う 256 * scale(3)
        let count = 17_937             // ズーム 11 のタイルに残っていた実数
        let iconPx = 21                // 10dp 相当を密度 2 で
        let half = Float(iconPx) / 2

        var lcg: UInt64 = 99
        func next() -> Float {
            lcg = lcg &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Float(lcg >> 11) / Float(UInt64(1) << 53)
        }
        let centres: [(Float, Float)] = (0..<count).map { _ in
            (next() * Float(tilePx), next() * Float(tilePx))
        }

        let icon = iconImage(sizePx: iconPx)

        // --- CPU: CoreGraphics で同じ絵を貼る ---
        let cpuMs = ms {
            let format = UIGraphicsImageRendererFormat.default()
            format.scale = 1
            _ = UIGraphicsImageRenderer(size: CGSize(width: tilePx, height: tilePx), format: format).image { _ in
                for c in centres {
                    icon.draw(in: CGRect(x: CGFloat(c.0 - half), y: CGFloat(c.1 - half),
                                         width: CGFloat(iconPx), height: CGFloat(iconPx)))
                }
            }
        }

        // --- GPU: Metal のインスタンス描画 ---
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else {
            throw XCTSkip("Metal が使えない")
        }
        let library = try device.makeLibrary(source: Self.shader, options: nil)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "icon_vertex")
        descriptor.fragmentFunction = library.makeFunction(name: "icon_fragment")
        let attachment = descriptor.colorAttachments[0]!
        attachment.pixelFormat = .rgba8Unorm
        attachment.isBlendingEnabled = true
        attachment.rgbBlendOperation = .add
        attachment.sourceRGBBlendFactor = .sourceAlpha
        attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
        attachment.alphaBlendOperation = .add
        attachment.sourceAlphaBlendFactor = .one
        attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        let pipeline = try device.makeRenderPipelineState(descriptor: descriptor)

        // アイコンを 1 枚のテクスチャへ。実際は種ごとのアトラスになる。
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: iconPx, height: iconPx, mipmapped: false)
        textureDescriptor.usage = .shaderRead
        let texture = device.makeTexture(descriptor: textureDescriptor)!
        var iconPixels = [UInt8](repeating: 0, count: iconPx * iconPx * 4)
        iconPixels.withUnsafeMutableBytes { raw in
            let ctx = CGContext(data: raw.baseAddress, width: iconPx, height: iconPx,
                                bitsPerComponent: 8, bytesPerRow: iconPx * 4,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(icon.cgImage!, in: CGRect(x: 0, y: 0, width: iconPx, height: iconPx))
        }
        texture.replace(region: MTLRegionMake2D(0, 0, iconPx, iconPx), mipmapLevel: 0,
                        withBytes: iconPixels, bytesPerRow: iconPx * 4)

        let sampler = device.makeSamplerState(descriptor: {
            let d = MTLSamplerDescriptor(); d.minFilter = .linear; d.magFilter = .linear; return d
        }())!

        var instances = centres.map { SIMD4<Float>($0.0, $0.1, half, 0) }
        let instanceBuffer = device.makeBuffer(bytes: &instances,
                                               length: MemoryLayout<SIMD4<Float>>.stride * count,
                                               options: .storageModeShared)!
        let targetDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: tilePx, height: tilePx, mipmapped: false)
        targetDescriptor.usage = [.renderTarget, .shaderRead]
        let target = device.makeTexture(descriptor: targetDescriptor)!

        var extent = Float(tilePx)
        var readback = [UInt8](repeating: 0, count: tilePx * tilePx * 4)

        // 1 回目はシェーダの準備が乗るので、2 回目を採る。
        var gpuMs = 0.0
        for pass in 0..<2 {
            gpuMs = ms {
                let renderPass = MTLRenderPassDescriptor()
                renderPass.colorAttachments[0].texture = target
                renderPass.colorAttachments[0].loadAction = .clear
                renderPass.colorAttachments[0].storeAction = .store
                renderPass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)

                let buffer = queue.makeCommandBuffer()!
                let encoder = buffer.makeRenderCommandEncoder(descriptor: renderPass)!
                encoder.setRenderPipelineState(pipeline)
                encoder.setVertexBuffer(instanceBuffer, offset: 0, index: 0)
                encoder.setVertexBytes(&extent, length: MemoryLayout<Float>.size, index: 1)
                encoder.setFragmentTexture(texture, index: 0)
                encoder.setFragmentSamplerState(sampler, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6,
                                       instanceCount: count)
                encoder.endEncoding()
                buffer.commit()
                buffer.waitUntilCompleted()

                readback.withUnsafeMutableBytes { raw in
                    target.getBytes(raw.baseAddress!, bytesPerRow: tilePx * 4,
                                    from: MTLRegionMake2D(0, 0, tilePx, tilePx), mipmapLevel: 0)
                }
            }
            _ = pass
        }

        print(String(format: "GPUDRAW icons=%d tile=%d cpu=%.1fms gpu=%.1fms speedup=%.1fx",
                     count, tilePx, cpuMs, gpuMs, cpuMs / max(gpuMs, 0.001)))
        XCTAssertGreaterThan(cpuMs, 0)
    }
}
