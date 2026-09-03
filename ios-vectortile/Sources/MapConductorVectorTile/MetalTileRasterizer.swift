import Foundation
import Metal

/// Draws a tessellated tile on the GPU and returns PNG bytes.
///
/// The counterpart of the Android GL shell, and the same shape: the renderer
/// hands over triangles in tile coordinates, this draws them offscreen, and the
/// native encoder turns the pixels into PNG. Metal rather than OpenGL ES
/// because ES has been deprecated on iOS since 12.
///
/// Everything runs on one serial queue. Metal objects are safe to use from
/// several threads, but a tile is a short burst of work against one command
/// queue and one pipeline, and serialising it keeps the GPU from being handed
/// interleaved tiles that only contend for the same resources.
public final class MetalTileRasterizer {

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let queue = DispatchQueue(label: "com.mapconductor.vectortile.metal")

    /// Multisample count for the offscreen target. Anti-aliasing comes from
    /// MSAA rather than per-vertex coverage, which keeps the shader trivial —
    /// the same trade the GL path makes.
    private static let sampleCount = 4

    private let tileSize: Int
    private var colorTexture: MTLTexture?
    private var resolveTexture: MTLTexture?

    /// Vertex and fragment stages.
    ///
    /// Positions arrive in tile units (0..extent) and are mapped to clip space
    /// here, so the geometry never has to be rescaled on the CPU.
    ///
    /// Unlike the GL path there is no deliberate flip: tile y grows downward,
    /// Metal clip space has y up, and `getBytes` reads row 0 as the top — so
    /// mapping y=0 to clip y=+1 already lands the tile the right way up.
    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct VertexIn {
        float2 position [[attribute(0)]];
        float4 color    [[attribute(1)]];
    };

    struct VertexOut {
        float4 position [[position]];
        float4 color;
    };

    vertex VertexOut tile_vertex(VertexIn in [[stage_in]],
                                 constant float &extent [[buffer(1)]]) {
        float2 unit = in.position / extent;
        VertexOut out;
        out.position = float4(unit.x * 2.0 - 1.0, 1.0 - unit.y * 2.0, 0.0, 1.0);
        out.color = in.color;
        return out;
    }

    fragment float4 tile_fragment(VertexOut in [[stage_in]]) {
        return in.color;
    }
    """

    /// Builds a rasterizer, or returns nil where Metal is unavailable — the
    /// simulator on an Intel host, or a device that refuses the pipeline. The
    /// caller is expected to fall back to CPU rendering rather than fail.
    public static func createOrNull(tileSize: Int) -> MetalTileRasterizer? {
        try? MetalTileRasterizer(tileSize: tileSize)
    }

    public init(tileSize: Int) throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw VectorTileError.renderFailed(MvtStatus.renderFailed)
        }
        guard let commandQueue = device.makeCommandQueue() else {
            throw VectorTileError.renderFailed(MvtStatus.renderFailed)
        }
        self.device = device
        self.commandQueue = commandQueue
        self.tileSize = tileSize

        let library = try device.makeLibrary(source: Self.shaderSource, options: nil)

        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float2
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        vertexDescriptor.attributes[1].format = .float4
        vertexDescriptor.attributes[1].offset = MemoryLayout<Float>.size * 2
        vertexDescriptor.attributes[1].bufferIndex = 0
        vertexDescriptor.layouts[0].stride =
            MemoryLayout<Float>.size * TessellatedTile.vertexStride

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "tile_vertex")
        descriptor.fragmentFunction = library.makeFunction(name: "tile_fragment")
        descriptor.vertexDescriptor = vertexDescriptor
        descriptor.rasterSampleCount = Self.sampleCount

        let attachment = descriptor.colorAttachments[0]!
        attachment.pixelFormat = .rgba8Unorm
        attachment.isBlendingEnabled = true
        attachment.rgbBlendOperation = .add
        attachment.alphaBlendOperation = .add
        attachment.sourceRGBBlendFactor = .sourceAlpha
        attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
        // Alpha blends separately from colour on purpose. Using source alpha as
        // the alpha factor too would pull the stored alpha *down* every time a
        // translucent layer is drawn — a 0.10-alpha layer leaves 0.91 behind —
        // and anything that then treats the pixels as premultiplied divides the
        // colour back out and blows highlights to white. With `one` the
        // destination alpha saturates and the readback is exact.
        attachment.sourceAlphaBlendFactor = .one
        attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha

        self.pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
    }

    /// Draws `tile` and encodes the result as PNG, or returns nil if the GPU
    /// work fails. Blocks until the tile is done.
    public func renderPng(_ tile: TessellatedTile) -> Data? {
        queue.sync { drawAndEncode(tile) }
    }

    private func targets() throws -> (color: MTLTexture, resolve: MTLTexture) {
        if let colorTexture, let resolveTexture {
            return (colorTexture, resolveTexture)
        }
        let resolveDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: tileSize, height: tileSize,
            mipmapped: false
        )
        resolveDescriptor.usage = [.renderTarget, .shaderRead]
        resolveDescriptor.storageMode = .shared

        let multisampleDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: tileSize, height: tileSize,
            mipmapped: false
        )
        multisampleDescriptor.textureType = .type2DMultisample
        multisampleDescriptor.sampleCount = Self.sampleCount
        multisampleDescriptor.usage = [.renderTarget]
        multisampleDescriptor.storageMode = .private

        guard let color = device.makeTexture(descriptor: multisampleDescriptor),
              let resolve = device.makeTexture(descriptor: resolveDescriptor) else {
            throw VectorTileError.renderFailed(MvtStatus.renderFailed)
        }
        colorTexture = color
        resolveTexture = resolve
        return (color, resolve)
    }

    private func drawAndEncode(_ tile: TessellatedTile) -> Data? {
        guard let (color, resolve) = try? targets() else { return nil }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = color
        pass.colorAttachments[0].resolveTexture = resolve
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .multisampleResolve
        let background = tile.background
        pass.colorAttachments[0].clearColor = MTLClearColor(
            red: Double(background?.r ?? 0),
            green: Double(background?.g ?? 0),
            blue: Double(background?.b ?? 0),
            alpha: Double(background?.a ?? 0)
        )

        guard let buffer = commandQueue.makeCommandBuffer(),
              let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else {
            return nil
        }

        let vertexFloats = tile.vertexFloatCount
        if vertexFloats > 0, tile.extent > 0 {
            let uploaded: MTLBuffer? = tile.withVertices { vertices in
                guard let base = vertices.baseAddress else { return nil }
                return device.makeBuffer(
                    bytes: base,
                    length: vertexFloats * MemoryLayout<Float>.size,
                    options: .storageModeShared
                )
            }
            guard let uploaded else {
                encoder.endEncoding()
                return nil
            }

            encoder.setRenderPipelineState(pipeline)
            encoder.setVertexBuffer(uploaded, offset: 0, index: 0)
            var extent = tile.extent
            encoder.setVertexBytes(&extent, length: MemoryLayout<Float>.size, index: 1)

            // One draw call per batch, to preserve painter's order.
            for index in 0..<tile.batchCount {
                let batch = tile.batch(index)
                guard batch.vertexCount > 0 else { continue }
                encoder.drawPrimitives(
                    type: .triangle,
                    vertexStart: batch.firstVertex,
                    vertexCount: batch.vertexCount
                )
            }
        }

        encoder.endEncoding()
        buffer.commit()
        buffer.waitUntilCompleted()
        guard buffer.error == nil else { return nil }

        let bytesPerRow = tileSize * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * tileSize)
        pixels.withUnsafeMutableBytes { raw in
            resolve.getBytes(
                raw.baseAddress!,
                bytesPerRow: bytesPerRow,
                from: MTLRegionMake2D(0, 0, tileSize, tileSize),
                mipmapLevel: 0
            )
        }

        return pixels.withUnsafeBytes { raw in
            try? VectorTileRenderer.encodePng(
                rgba: raw, width: UInt32(tileSize), height: UInt32(tileSize)
            )
        }
    }
}
