#if canImport(UIKit)
import AstrotypeCore
import Metal
import QuartzCore
import UIKit

/// The Metal side of the effects (features/customization "Letters on Metal"): one
/// device, queue and pair of pipelines, made off the main thread the first time an
/// effect asks for them (`load`) and shared by the sky and the letters. The shaders
/// are `Shaders/KeyboardShaders.metal`, which Xcode compiles into the package's
/// resource bundle (`library`), so the phone neither loads the Metal compiler nor
/// compiles them on each launch; a build that only copied the file there gets them
/// compiled from it on the phone. Either way it runs off the main thread: the keys
/// open drawn by Core Animation and move to Metal once it is there
/// (Gabriel, 7 Nov 2026: "metal doesn't need to be a loading blocker"). `shared` stays
/// nil when the phone can't run Metal; the effects then keep to Core Animation.
@MainActor
final class MetalKeyboard: @unchecked Sendable {
    /// Made by `load`; nil until then, and for good when `unavailable`.
    private(set) static var shared: MetalKeyboard?
    /// Whether `shared` was made: Metal is in memory from then on.
    private(set) static var loaded = false
    /// Whether making it was tried and failed.
    private(set) static var unavailable = false
    /// How long the shaders took to load, in ms, for the open timings; 0 until done.
    private(set) static var loadMillis = 0
    /// Whether the shaders were compiled on the phone, the bundle's compiled library
    /// being missing; for the open timings.
    private(set) static var compiledOnPhone = false
    private static var loading = false
    private static var waiting: [@MainActor () -> Void] = []

    let device: any MTLDevice
    let queue: any MTLCommandQueue
    let sky: any MTLRenderPipelineState
    let letters: any MTLRenderPipelineState
    let keys: any MTLRenderPipelineState

    /// Makes `shared` off the main thread and calls `ready` on it once it is there (at
    /// once when it already is). Nothing is called when the phone can't run Metal.
    static func load(then ready: @escaping @MainActor () -> Void) {
        if shared != nil { ready(); return }
        guard !unavailable else { return }
        waiting.append(ready)
        guard !loading else { return }
        loading = true
        let started = CACurrentMediaTime()
        Task.detached(priority: .userInitiated) {
            let made = MetalKeyboard()
            await MainActor.run {
                loadMillis = max(1, Int((CACurrentMediaTime() - started) * 1000))
                compiledOnPhone = made?.compiledOnPhone ?? false
                loading = false
                shared = made
                loaded = made != nil
                unavailable = made == nil
                let callbacks = waiting
                waiting = []
                if made != nil { for callback in callbacks { callback() } }
            }
        }
    }

    /// Whether this one's shaders were compiled on the phone.
    private let compiledOnPhone: Bool

    private nonisolated init?() {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
        do {
            let (library, compiledOnPhone) = try Self.library(for: device)
            self.compiledOnPhone = compiledOnPhone
            sky = try Self.pipeline(device, library, vertex: "sky_vertex", fragment: "sky_fragment")
            letters = try Self.pipeline(device, library, vertex: "letter_vertex", fragment: "letter_fragment")
            keys = try Self.pipeline(device, library, vertex: "key_vertex", fragment: "key_fragment")
        } catch {
            return nil
        }
        self.device = device
        self.queue = queue
    }

    /// The shaders, from this package target's resource bundle in the app's or the
    /// extension's resources: `default.metallib`, which Xcode compiles from
    /// `Shaders/KeyboardShaders.metal`, or else that file itself, compiled here (true in
    /// the result). The bundle is looked up by hand rather than through
    /// `Bundle.module`, which stops the process when it is missing.
    private nonisolated static func library(for device: any MTLDevice) throws -> (any MTLLibrary, compiledOnPhone: Bool) {
        var urls: [URL] = []
        for resources in [Bundle.main, Bundle(for: MetalKeyboard.self)].compactMap(\.resourceURL) {
            let url = resources.appendingPathComponent("AstrotypeKit_AstrotypeUI.bundle", isDirectory: true)
            if !urls.contains(url) { urls.append(url) }
        }
        let bundles = urls.compactMap { Bundle(url: $0) }
        for bundle in bundles {
            if let library = try? device.makeDefaultLibrary(bundle: bundle) { return (library, false) }
        }
        for bundle in bundles {
            guard let file = bundle.url(forResource: "KeyboardShaders", withExtension: "metal") else { continue }
            let source = try String(contentsOf: file, encoding: .utf8)
            return (try device.makeLibrary(source: source, options: nil), true)
        }
        throw ShadersMissing()
    }

    /// Neither the compiled shaders nor their file is in the bundle.
    private struct ShadersMissing: Error {}

    private nonisolated static func pipeline(_ device: any MTLDevice, _ library: any MTLLibrary, vertex: String,
                                 fragment: String) throws -> any MTLRenderPipelineState {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: vertex)
        descriptor.fragmentFunction = library.makeFunction(name: fragment)
        let colour = descriptor.colorAttachments[0]!
        colour.pixelFormat = .bgra8Unorm
        // Premultiplied alpha.
        colour.isBlendingEnabled = true
        colour.sourceRGBBlendFactor = .one
        colour.sourceAlphaBlendFactor = .one
        colour.destinationRGBBlendFactor = .oneMinusSourceAlpha
        colour.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        return try device.makeRenderPipelineState(descriptor: descriptor)
    }

    /// A clear-coloured layer for this device, sized by `layout`.
    func makeLayer() -> CAMetalLayer {
        let layer = CAMetalLayer()
        layer.device = device
        layer.pixelFormat = .bgra8Unorm
        layer.framebufferOnly = true
        layer.isOpaque = false
        layer.maximumDrawableCount = 2
        layer.actions = ["bounds": NSNull(), "position": NSNull(), "frame": NSNull(), "contents": NSNull()]
        return layer
    }

    /// Clear the layer's next drawable, let `draw` encode into it, and show it. False when
    /// nothing was drawn: the layer has no drawable yet (it isn't on screen, or its size
    /// is still zero), so the caller should try again on a later frame.
    @discardableResult
    func draw(on layer: CAMetalLayer, _ draw: (any MTLRenderCommandEncoder) -> Void) -> Bool {
        guard layer.drawableSize.width >= 1, layer.drawableSize.height >= 1, let drawable = layer.nextDrawable(),
              let buffer = queue.makeCommandBuffer() else { return false }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return false }
        draw(encoder)
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
        return true
    }

    static func size(_ layer: CAMetalLayer, bounds: CGRect, scale: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.frame = bounds
        layer.contentsScale = scale
        layer.drawableSize = CGSize(width: max(1, (bounds.width * scale).rounded()), height: max(1, (bounds.height * scale).rounded()))
        CATransaction.commit()
    }
}

/// The sky behind the keys at the top flow level, drawn at half resolution.
@MainActor
final class SkyRenderer {
    let layer: CAMetalLayer
    private let metal: MetalKeyboard
    private let start = CACurrentMediaTime()

    init(metal: MetalKeyboard) {
        self.metal = metal
        layer = metal.makeLayer()
    }

    func layout(_ bounds: CGRect, scale: CGFloat) {
        MetalKeyboard.size(layer, bounds: bounds, scale: max(1, scale / 2))
    }

    func render(time: TimeInterval, kind: EffectsSettings.Sky) {
        let mode: Float = switch kind {
        case .aurora: 0
        case .starfield: 1
        case .ice: 2
        case .retro: 3
        case .glitch: 4
        case .prism: 5
        case .blackHole: 6
        case .ripples: 7
        case .candy: 8
        }
        let size = layer.drawableSize
        var info = SIMD4<Float>(Float(size.width), Float(size.height), Float((time - start).truncatingRemainder(dividingBy: 3600)), mode)
        let pipeline = metal.sky
        metal.draw(on: layer) { encoder in
            encoder.setRenderPipelineState(pipeline)
            encoder.setFragmentBytes(&info, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        }
    }
}

/// The letter keys' labels, drawn with Metal so the letter effects (all but Pop) can
/// bend them, and the key effects under them (`EffectsSettings.Keys`). One layer for
/// both, so a second full-size drawable isn't needed. The keys hide their own labels once a frame of letters is on screen (`KeyEffects.hidesLabels`, `KeyView.lettersElsewhere`).
@MainActor
final class LetterRenderer {
    let layer: CAMetalLayer
    /// The letter effect, or None when the keys draw their own letters.
    var mode: EffectsSettings.Letters = .none
    /// What the keys themselves do (`EffectsSettings.Keys`), drawn under the letters.
    var keyMode: EffectsSettings.Keys = .none

    private struct Uniforms {
        var info0: SIMD4<Float>
        var info1: SIMD4<Float>
        var touches: (SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>)
        var left: SIMD4<Float>
        var right: SIMD4<Float>
        var info2: SIMD4<Float>
    }

    private struct Instance {
        var rect: SIMD4<Float>
        var uv: SIMD4<Float>
        var color: SIMD4<Float>
        var extra: SIMD4<Float>
    }

    private let metal: MetalKeyboard
    private let start = CACurrentMediaTime()
    private var atlas: (any MTLTexture)?
    private var glyphs: [Character: SIMD4<Float>] = [:]
    /// One glyph's cell, in points.
    private var cell = CGSize.zero
    private var hits: [Key: (time: TimeInterval, seed: Float)] = [:]
    private var touches: [(point: CGPoint, time: TimeInterval)] = []
    private var buffers: [any MTLBuffer] = []
    private var next = 0
    private var keyBuffers: [any MTLBuffer] = []
    private var keyNext = 0
    private var prepared: (letters: [Character], font: UIFont, scale: CGFloat)?

    init(metal: MetalKeyboard) {
        self.metal = metal
        layer = metal.makeLayer()
    }

    func layout(_ bounds: CGRect, scale: CGFloat) {
        MetalKeyboard.size(layer, bounds: bounds, scale: scale)
    }

    /// Drop the atlas (the keys draw their own letters).
    func dropLetters() {
        prepared = nil
        glyphs = [:]
        atlas = nil
    }

    /// Draw the letters into the atlas, once for each set of letters, font and scale.
    func prepare(letters: [Character], font: UIFont, scale: CGFloat) {
        if let prepared, prepared.letters == letters, prepared.font == font, prepared.scale == scale, atlas != nil { return }
        prepared = (letters, font, scale)
        glyphs = [:]
        atlas = nil
        guard !letters.isEmpty else { return }
        let side = ceil(font.lineHeight * 1.7)
        let px = Int((side * scale).rounded(.up))
        let columns = max(1, Int(Double(letters.count).squareRoot().rounded(.up)))
        let rows = (letters.count + columns - 1) / columns
        let width = columns * px, height = rows * px
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return }
        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        // UIKit draws top down: row 0 in memory is the top, as Metal reads it.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)
        UIGraphicsPushContext(context)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white]
        let cellPoints = CGFloat(px) / scale
        for (i, letter) in letters.enumerated() {
            let column = i % columns, row = i / columns
            let string = String(letter) as NSString
            let size = string.size(withAttributes: attributes)
            let origin = CGPoint(x: CGFloat(column) * cellPoints + (cellPoints - size.width) / 2,
                                 y: CGFloat(row) * cellPoints + (cellPoints - size.height) / 2)
            string.draw(at: origin, withAttributes: attributes)
            glyphs[letter] = SIMD4(Float(column * px) / Float(width), Float(row * px) / Float(height),
                                   Float((column + 1) * px) / Float(width), Float((row + 1) * px) / Float(height))
        }
        UIGraphicsPopContext()
        guard let data = context.data else { return }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = .shaderRead
        guard let texture = metal.device.makeTexture(descriptor: descriptor) else { return }
        texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: data, bytesPerRow: context.bytesPerRow)
        atlas = texture
        cell = CGSize(width: cellPoints, height: cellPoints)
    }

    private var duration: TimeInterval { mode == .liquid || keyMode != .none ? 1.6 : 1.0 }

    func hit(_ key: Key, at point: CGPoint, time: TimeInterval) {
        hits[key] = (time, Float.random(in: 0...1))
        touches.append((point, time))
        if touches.count > 4 { touches.removeFirst(touches.count - 4) }
    }

    func isAnimating(time: TimeInterval) -> Bool {
        hits.values.contains { time - $0.time < duration } || touches.contains { time - $0.time < 1.5 }
    }

    /// Whether the last frame left out a letter key, its letter not in the atlas (the
    /// keys changed since `prepare`).
    private(set) var missedLetters = false

    /// Draws the frame; false when the layer had no drawable to draw into (see
    /// `MetalKeyboard.draw`), so the keys' letters are not on screen yet.
    @discardableResult
    func render(keys: [(key: Key, letter: Character, frame: CGRect, ink: UIColor)], frames: [(key: Key, frame: CGRect)],
                time: TimeInterval, level: Int, style: KeyStyle, power: Float = 1) -> Bool {
        hits = hits.filter { time - $0.value.time < 3 }
        touches.removeAll { time - $0.time >= 1.5 }
        var instances: [Instance] = []
        missedLetters = false
        if mode != .none, style.shape.showsLetters, atlas == nil, !keys.isEmpty { missedLetters = true }
        if mode != .none, atlas != nil, style.shape.showsLetters {
            instances.reserveCapacity(keys.count)
            for key in keys {
                guard let uv = glyphs[key.letter] else {
                    missedLetters = true
                    continue
                }
                let rect = SIMD4<Float>(Float(key.frame.midX - cell.width / 2), Float(key.frame.midY - cell.height / 2),
                                        Float(cell.width), Float(cell.height))
                let hit = hits[key.key]
                let age = hit.map { Float(time - $0.time) } ?? 99
                let seed = hit?.seed ?? Float(abs(sin(Double(key.frame.minX) * 12.9898 + Double(key.frame.minY) * 78.233)))
                instances.append(Instance(rect: rect, uv: uv, color: Self.rgba(key.ink), extra: SIMD4(age, seed, 0, 0)))
            }
        }
        let touchList = touches.suffix(4).map { SIMD4<Float>(Float($0.point.x), Float($0.point.y), Float(time - $0.time), 0) }
        func touch(_ i: Int) -> SIMD4<Float> { i < touchList.count ? touchList[i] : .zero }
        let modeValue: Float = switch mode {
        case .none, .pop: 0
        case .jelly: 1
        case .wave: 2
        case .glitch: 3
        case .liquid: 4
        case .pixel: 5
        case .disco: 6
        case .warp: 7
        }
        let keyModeValue: Float = switch keyMode {
        case .none: 0
        case .neon: 1
        case .glitch: 2
        case .prism: 3
        case .warp: 4
        case .ripple: 5
        case .candy: 6
        }
        var keyInstances: [Instance] = []
        if keyMode != .none {
            keyInstances.reserveCapacity(frames.count)
            for key in frames {
                let hit = hits[key.key]
                let age = hit.map { Float(time - $0.time) } ?? 99
                let seed = hit?.seed ?? Float(abs(sin(Double(key.frame.minX) * 12.9898 + Double(key.frame.minY) * 78.233)))
                keyInstances.append(Instance(rect: SIMD4(Float(key.frame.minX), Float(key.frame.minY), Float(key.frame.width), Float(key.frame.height)),
                                             uv: .zero, color: .zero, extra: SIMD4(age, seed, 0, 0)))
            }
        }
        var uniforms = Uniforms(
            info0: SIMD4(Float(layer.bounds.width), Float(layer.bounds.height), Float((time - start).truncatingRemainder(dividingBy: 3600)), Float(level)),
            info1: SIMD4(modeValue, Float(touchList.count), keyModeValue, Float(style.shape.corner)),
            touches: (touch(0), touch(1), touch(2), touch(3)),
            left: Self.rgba(style.thumb(.left)), right: Self.rgba(style.thumb(.right)),
            info2: SIMD4(power, 0, 0, 0))
        let buffer = instances.isEmpty ? nil : Self.instanceBuffer(instances, device: metal.device, ring: &buffers, next: &next)
        let keyBuffer = keyInstances.isEmpty ? nil : Self.instanceBuffer(keyInstances, device: metal.device, ring: &keyBuffers, next: &keyNext)
        let pipeline = metal.letters
        let keyPipeline = metal.keys
        let atlas = self.atlas
        let keyCount = keyInstances.count
        return metal.draw(on: layer) { encoder in
            guard uniforms.info0.x > 0 else { return }
            if let keyBuffer {
                encoder.setRenderPipelineState(keyPipeline)
                encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
                encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
                encoder.setVertexBuffer(keyBuffer, offset: 0, index: 1)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: keyCount)
            }
            guard let buffer, let atlas else { return }
            encoder.setRenderPipelineState(pipeline)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
            encoder.setVertexBuffer(buffer, offset: 0, index: 1)
            encoder.setFragmentTexture(atlas, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 216, instanceCount: instances.count)
        }
    }

    /// Three buffers taken in turn, so the GPU never reads one being written.
    private static func instanceBuffer(_ instances: [Instance], device: any MTLDevice, ring buffers: inout [any MTLBuffer],
                                       next: inout Int) -> (any MTLBuffer)? {
        let length = MemoryLayout<Instance>.stride * instances.count
        if buffers.count < 3 || buffers[next].length < length {
            let capacity = max(length, MemoryLayout<Instance>.stride * 64)
            guard let buffer = device.makeBuffer(length: capacity, options: .storageModeShared) else { return nil }
            if buffers.count < 3 { buffers.append(buffer); next = buffers.count - 1 } else { buffers[next] = buffer }
        }
        let buffer = buffers[next]
        next = (next + 1) % 3
        instances.withUnsafeBytes { buffer.contents().copyMemory(from: $0.baseAddress!, byteCount: length) }
        return buffer
    }

    private static func rgba(_ color: UIColor) -> SIMD4<Float> {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return SIMD4(Float(r), Float(g), Float(b), Float(a))
    }
}
#endif
