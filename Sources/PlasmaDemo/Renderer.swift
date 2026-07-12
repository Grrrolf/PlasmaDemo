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
    var fade: Float
    var resolution: SIMD2<Float>
    var textSize: SIMD2<Float>
    var text2Size: SIMD2<Float>
    var text3Size: SIMD2<Float>
    var text4Size: SIMD2<Float>
    var text5Size: SIMD2<Float>
    var scene: Float
    var sceneTime: Float
}

let scrollText = "*** PLASMA DEMO *** CODED BY JUNIE (POWERED BY GEMINI 3 FLASH PREVIEW AND FABLE 5) ... " +
                 "A CLASSIC SINE-SUM PLASMA WITH A BOUNCING RAINBOW SCROLLER, " +
                 "WRITTEN IN SWIFT AND METAL FOR MACOS ... " +
                 "GREETINGS TO ALL DEMOSCENERS OUT THERE ... PRESS ESC TO EXIT ... WRAP!"

/// Scroll message for the classic tunnel part.
let scrollTextTunnel = "*** PART TWO *** THE INFINITE CHECKERBOARD TUNNEL ... " +
                       "POLAR MAPPING AT ITS FINEST ... A DRIFTING CENTER, " +
                       "A SLOW TWIST, AND COLORS CYCLING INTO THE DEPTHS ... " +
                       "RELAX AND ENJOY THE RIDE ... " +
                       "PRESS SPACE FOR THE NEXT PART ... " +
                       "PRESS ESC TO EXIT ... WRAP!"

/// Scroll message for the Commodore 64 raster bars part.
let scrollText2 = "*** PART THREE *** COMMODORE 64 STYLE RASTER BARS ... " +
                  "REMEMBER THE BREADBIN? EIGHT BARS SWEEPING THE RASTER " +
                  "JUST LIKE BACK IN 1985 ... NO BOUNCE, NO WAVE, JUST PURE " +
                  "OLD-SCHOOL SCROLLING ... CODE BY JUNIE (POWERED BY GEMINI 3 FLASH PREVIEW AND FABLE 5) ... " +
                  "PRESS SPACE FOR THE NEXT PART ... " +
                  "PRESS ESC TO EXIT ... WRAP!"

/// Scroll message for the Starfield and 3D Cube part.
let scrollText4 = "*** PART FOUR *** THE CLASSIC STARFIELD AND ROTATING 3D CUBE ... " +
                  "A TALE AS OLD AS TIME ... PSEUDO-3D IN A FRAGMENT SHADER ... " +
                  "STARS FLYING BY WHILE THE CUBE SPINS IN THE VOID ... " +
                  "PRESS SPACE FOR THE NEXT PART ... " +
                  "PRESS ESC TO EXIT ... WRAP!"

/// Scroll message for the Unlimited Bobs part.
let scrollText5 = "*** PART FIVE *** UNLIMITED BOBS ... " +
                  "THOUSANDS OF COLORFUL SPHERES IN A C64-STYLE SNAKE PATTERN ... " +
                  "A TRADITIONAL STRENGTH TEST FOR THE BLITTER, NOW IN SHADERS ... " +
                  "GROWING QUICKER AND QUICKER UNTIL THE SCREEN IS FULL ... " +
                  "BOBS STAYING ABOVE THE SCROLLER, AS REQUESTED ... " +
                  "AND THIS CONCLUDES OUR DEMO ... FOR NOW! ... " +
                  "PRESS SPACE TO LOOP BACK ... " +
                  "PRESS ESC TO EXIT ... WRAP!"

enum RendererError: Error {
    case textureCreationFailed
    case commandQueueCreationFailed
}

final class Renderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    let queue: MTLCommandQueue
    let pipeline: MTLRenderPipelineState
    let textTexture: MTLTexture
    let textTexture2: MTLTexture
    let textTexture3: MTLTexture
    let textTexture4: MTLTexture
    let textTexture5: MTLTexture
    private let startTime = CACurrentMediaTime()

    // MARK: Demo parts & transition

    /// Number of demo parts (0 = plasma, 1 = tunnel, 2 = C64, 3 = cube, 4 = bobs).
    private let sceneCount = 5
    private var scene = 0
    private var sceneStartTime = CACurrentMediaTime()
    /// When a transition is running, the moment it started; nil otherwise.
    private var transitionStart: CFTimeInterval?
    private var sceneSwitched = false
    /// Duration of the fade-out (and of the fade-in) in seconds.
    private let fadeDuration: CFTimeInterval = 0.7

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
        self.textTexture2 = try Renderer.makeTextTexture(device: device,
                                                         text: scrollText2,
                                                         fontName: "Silom")
        self.textTexture3 = try Renderer.makeTextTexture(device: device, text: scrollTextTunnel)
        self.textTexture4 = try Renderer.makeTextTexture(device: device, text: scrollText4)
        self.textTexture5 = try Renderer.makeTextTexture(device: device, text: scrollText5)
        super.init()
    }

    // MARK: - Part switching

    /// Starts the fade-out -> switch part -> fade-in transition.
    /// Ignored while a transition is already running.
    func advanceScene() {
        guard transitionStart == nil else { return }
        transitionStart = CACurrentMediaTime()
        sceneSwitched = false
    }

    /// Returns the current global brightness (1 = normal, 0 = black) and
    /// flips to the next part at the midpoint of the transition.
    private func updateTransition(now: CFTimeInterval) -> Float {
        guard let start = transitionStart else { return 1 }
        let elapsed = now - start
        if elapsed < fadeDuration {                       // fading out
            return Float(1 - elapsed / fadeDuration)
        }
        if !sceneSwitched {                               // midpoint: swap part
            scene = (scene + 1) % sceneCount
            sceneSwitched = true
            sceneStartTime = now
        }
        if elapsed < fadeDuration * 2 {                   // fading in
            return Float((elapsed - fadeDuration) / fadeDuration)
        }
        transitionStart = nil                             // transition done
        return 1
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let passDescriptor = view.currentRenderPassDescriptor,
              let commandBuffer = queue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor)
        else { return }

        let now = CACurrentMediaTime()
        let fade = updateTransition(now: now)

        var uniforms = Uniforms(
            time: Float(now - startTime),
            fade: fade,
            resolution: SIMD2(Float(view.drawableSize.width),
                              Float(view.drawableSize.height)),
            textSize: SIMD2(Float(textTexture.width),
                            Float(textTexture.height)),
            text2Size: SIMD2(Float(textTexture2.width),
                             Float(textTexture2.height)),
            text3Size: SIMD2(Float(textTexture3.width),
                             Float(textTexture3.height)),
            text4Size: SIMD2(Float(textTexture4.width),
                             Float(textTexture4.height)),
            text5Size: SIMD2(Float(textTexture5.width),
                             Float(textTexture5.height)),
            scene: Float(scene),
            sceneTime: Float(now - sceneStartTime)
        )

        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.setFragmentTexture(textTexture, index: 0)
        encoder.setFragmentTexture(textTexture2, index: 1)
        encoder.setFragmentTexture(textTexture3, index: 2)
        encoder.setFragmentTexture(textTexture4, index: 3)
        encoder.setFragmentTexture(textTexture5, index: 4)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    // MARK: - Scrolltext texture

    /// Renders the scroll message into a single-channel (r8Unorm) texture
    /// using CoreText. The font size is reduced automatically if the line
    /// would exceed the Metal texture width limit.
    static func makeTextTexture(device: MTLDevice,
                                text: String,
                                fontName: String = "Menlo-Bold") throws -> MTLTexture {
        let maxTextureWidth: CGFloat = 16000
        var fontSize: CGFloat = 96
        var line: CTLine!
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        var width: CGFloat = 0

        while true {
            let font = NSFont(name: fontName, size: fontSize)
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
