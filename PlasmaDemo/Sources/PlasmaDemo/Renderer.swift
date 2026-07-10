//
//  Renderer.swift
//  PlasmaDemo
//
//  Owns the Metal pipeline, the scrolltext texture and the per-frame draw.
//

import AppKit
import MetalKit
import CoreText
import QuartzCore

/// Must match the `Uniforms` struct in Shaders.swift (Metal side).
struct Uniforms {
    var time: Float
    var pad: Float = 0
    var resolution: SIMD2<Float>
    var textSize: SIMD2<Float>
}

let scrollText = "*** PLASMA DEMO *** GREETINGS FROM JUNIE ... " +
                 "A CLASSIC SINE-SUM PLASMA WITH A BOUNCING RAINBOW SCROLLER, " +
                 "WRITTEN IN SWIFT AND METAL FOR MACOS ... " +
                 "GREETINGS TO ALL DEMOSCENERS OUT THERE ... PRESS ESC TO EXIT ... WRAP!"

enum RendererError: Error {
    case textureCreationFailed
    case commandQueueCreationFailed
}

final class Renderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    let queue: MTLCommandQueue
    let pipeline: MTLRenderPipelineState
    let textTexture: MTLTexture
    private let startTime = CACurrentMediaTime()

    init(device: MTLDevice, pixelFormat: MTLPixelFormat) throws {
        self.device = device
        guard let queue = device.makeCommandQueue() else {
            throw RendererError.commandQueueCreationFailed
        }
        self.queue = queue

        let library = try device.makeLibrary(source: shaderSource, options: nil)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "fullscreenVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "plasmaFragment")
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        self.pipeline = try device.makeRenderPipelineState(descriptor: descriptor)

        self.textTexture = try Renderer.makeTextTexture(device: device, text: scrollText)
        super.init()
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let passDescriptor = view.currentRenderPassDescriptor,
              let commandBuffer = queue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor)
        else { return }

        var uniforms = Uniforms(
            time: Float(CACurrentMediaTime() - startTime),
            resolution: SIMD2(Float(view.drawableSize.width),
                              Float(view.drawableSize.height)),
            textSize: SIMD2(Float(textTexture.width),
                            Float(textTexture.height))
        )

        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.setFragmentTexture(textTexture, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    // MARK: - Scrolltext texture

    /// Renders the scroll message into a single-channel (r8Unorm) texture
    /// using CoreText. The font size is reduced automatically if the line
    /// would exceed the Metal texture width limit.
    static func makeTextTexture(device: MTLDevice, text: String) throws -> MTLTexture {
        let maxTextureWidth: CGFloat = 16000
        var fontSize: CGFloat = 96
        var line: CTLine!
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        var width: CGFloat = 0

        while true {
            let font = NSFont(name: "Menlo-Bold", size: fontSize)
                ?? NSFont.boldSystemFont(ofSize: fontSize)
            let attributes: [NSAttributedString.Key: Any] = [
                kCTFontAttributeName as NSAttributedString.Key: font,
                kCTForegroundColorFromContextAttributeName as NSAttributedString.Key: true,
            ]
            let attributed = NSAttributedString(string: text, attributes: attributes)
            line = CTLineCreateWithAttributedString(attributed)
            width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
            if width + 32 <= maxTextureWidth || fontSize < 12 { break }
            fontSize *= 0.8
        }

        let texWidth = Int(ceil(width)) + 32
        let texHeight = Int(ceil(ascent + descent)) + 16

        guard let context = CGContext(
            data: nil,
            width: texWidth,
            height: texHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            throw RendererError.textureCreationFailed
        }

        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.textPosition = CGPoint(x: 16, y: descent + 8)
        CTLineDraw(line, context)

        guard let data = context.data else {
            throw RendererError.textureCreationFailed
        }

        // CGBitmapContext memory is already top-down (row 0 is the visual
        // top), so copy rows straight across — just compact bytesPerRow.
        let bytesPerRow = context.bytesPerRow
        var pixels = [UInt8](repeating: 0, count: texWidth * texHeight)
        pixels.withUnsafeMutableBytes { dst in
            for row in 0..<texHeight {
                let src = data.advanced(by: row * bytesPerRow)
                _ = memcpy(dst.baseAddress!.advanced(by: row * texWidth), src, texWidth)
            }
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm,
            width: texWidth,
            height: texHeight,
            mipmapped: false
        )
        descriptor.usage = .shaderRead

        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw RendererError.textureCreationFailed
        }
        pixels.withUnsafeBytes { bytes in
            texture.replace(
                region: MTLRegionMake2D(0, 0, texWidth, texHeight),
                mipmapLevel: 0,
                withBytes: bytes.baseAddress!,
                bytesPerRow: texWidth
            )
        }
        return texture
    }
}
