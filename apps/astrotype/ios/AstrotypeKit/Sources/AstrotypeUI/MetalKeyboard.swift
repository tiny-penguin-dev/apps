#if canImport(UIKit)
import AstrotypeCore
import Metal
import QuartzCore
import UIKit

/// The Metal side of the effects (features/customization "Letters on Metal"): one
/// device, queue and pair of pipelines, made the first time an effect needs them and
/// shared by the sky and the letters. The shaders are compiled from source here, so the
/// package needs no metallib. `nil` when the phone can't run Metal; the effects then
/// fall back to Core Animation.
@MainActor
final class MetalKeyboard {
    static let shared: MetalKeyboard? = MetalKeyboard()
    /// Whether `shared` was made: Metal is in memory from then on.
    private(set) static var loaded = false

    let device: any MTLDevice
    let queue: any MTLCommandQueue
    let sky: any MTLRenderPipelineState
    let letters: any MTLRenderPipelineState

    private init?() {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
        do {
            let library = try device.makeLibrary(source: Self.source, options: nil)
            sky = try Self.pipeline(device, library, vertex: "sky_vertex", fragment: "sky_fragment")
            letters = try Self.pipeline(device, library, vertex: "letter_vertex", fragment: "letter_fragment")
        } catch {
            return nil
        }
        self.device = device
        self.queue = queue
        Self.loaded = true
    }

    private static func pipeline(_ device: any MTLDevice, _ library: any MTLLibrary, vertex: String,
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

    /// Clear the layer's next drawable, let `draw` encode into it, and show it.
    func draw(on layer: CAMetalLayer, _ draw: (any MTLRenderCommandEncoder) -> Void) {
        guard layer.drawableSize.width >= 1, layer.drawableSize.height >= 1, let drawable = layer.nextDrawable(),
              let buffer = queue.makeCommandBuffer() else { return }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        draw(encoder)
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }

    static func size(_ layer: CAMetalLayer, bounds: CGRect, scale: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.frame = bounds
        layer.contentsScale = scale
        layer.drawableSize = CGSize(width: max(1, (bounds.width * scale).rounded()), height: max(1, (bounds.height * scale).rounded()))
        CATransaction.commit()
    }

    // MARK: Shaders

    /// Sky: one full-screen triangle; `info` is (width, height, time, kind).
    /// Letters: each letter is a 6×6 grid (216 vertices) bent by the effect, drawn from
    /// a glyph atlas. Uniforms and instances are all float4s so Swift and Metal agree on
    /// the layout.
    static let source = """
    #include <metal_stdlib>
    using namespace metal;

    static float hash1(float n) { return fract(sin(n) * 43758.5453); }
    static float hash2(float2 p) { return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453); }

    struct SkyOut { float4 position [[position]]; float2 uv; };

    vertex SkyOut sky_vertex(uint vid [[vertex_id]]) {
        float2 p = float2(float((vid << 1) & 2), float(vid & 2));
        SkyOut o;
        o.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
        o.uv = p;   // y up, like gl_FragCoord
        return o;
    }

    fragment float4 sky_fragment(SkyOut in [[stage_in]], constant float4 &info [[buffer(0)]]) {
        float2 uv = in.uv;
        float2 r = info.xy;
        float t = info.z;
        float m = info.w;
        float3 col = float3(0.0);
        if (m < 0.5) {
            // Aurora: four bands that sway.
            for (int i = 0; i < 4; i++) {
                float fi = float(i);
                float w = 0.62 - fi * 0.1 + sin(uv.x * (2.5 + fi) + t * 0.35 + fi * 1.7) * 0.09 + sin(uv.x * 7.0 + t * 0.8 + fi) * 0.025;
                float b = exp(-pow((uv.y - w) * (8.0 + fi * 2.0), 2.0));
                col += b * mix(float3(0.18, 0.95, 0.62), float3(0.55, 0.35, 1.0), fi / 3.0) * (0.65 + 0.35 * sin(uv.x * 30.0 + t * 1.6 + fi * 3.0));
            }
        } else if (m < 1.5) {
            // Starfield: three layers of stars flying out.
            float2 p = (uv - 0.5) * float2(r.x / r.y, 1.0);
            for (int l = 0; l < 3; l++) {
                float z = fract(t * 0.12 + float(l) / 3.0);
                float s = mix(18.0, 3.0, z);
                float2 g = p * s;
                float2 id = floor(g);
                float2 f = fract(g) - 0.5;
                float k = hash2(id + float(l) * 7.0);
                float d = length(f - (float2(k, fract(k * 13.0)) - 0.5) * 0.7);
                col += float3(0.9, 0.85, 1.0) * (1.0 - smoothstep(0.0, 0.09, d)) * smoothstep(0.0, 0.3, z) * (1.0 - smoothstep(0.75, 1.0, z)) * step(0.55, k);
            }
            col += float3(0.45, 0.15, 0.75) * 0.25 * max(0.0, 1.0 - length(p));
        } else {
            // Ice: caustics.
            float2 p = uv * 6.0;
            float2 q = p;
            float c = 1.0;
            for (int n = 0; n < 4; n++) {
                float tt = t * 0.4 * (1.0 - 3.5 / float(n + 1));
                q = p + float2(cos(tt - q.x) + sin(tt + q.y), sin(tt - q.y) + cos(tt + q.x));
                float2 v = float2(p.x * 0.005 / (sin(q.x + tt) + 1e-4), p.y * 0.005 / (cos(q.y + tt) + 1e-4));
                c += 1.0 / max(length(v), 1e-4);
            }
            c /= 4.0;
            c = 1.17 - pow(abs(c), 1.4);
            float v = pow(abs(c), 8.0);
            col = float3(0.2, 0.75, 0.95) * clamp(v, 0.0, 1.0) * 0.9 + float3(0.05, 0.2, 0.35) * 0.6;
        }
        col = clamp(col, 0.0, 1.0);
        float a = max(col.r, max(col.g, col.b));
        return float4(col, a);
    }

    struct LetterUniforms {
        float4 info0;      // width, height, time, level
        float4 info1;      // mode, touch count
        float4 touches[4]; // x, y, age
        float4 left;
        float4 right;
    };

    struct LetterInstance {
        float4 rect;   // x, y, width, height in points
        float4 uv;     // the glyph's cell in the atlas
        float4 color;  // straight alpha
        float4 extra;  // age of the last hit, seed
    };

    struct LetterOut {
        float4 position [[position]];
        float2 uv;
        float4 color;
        float fx;
        float uvw;
    };

    vertex LetterOut letter_vertex(uint vid [[vertex_id]], uint iid [[instance_id]],
                                   constant LetterUniforms &u [[buffer(0)]],
                                   const device LetterInstance *instances [[buffer(1)]]) {
        LetterInstance inst = instances[iid];
        uint cell = vid / 6;
        uint corner = vid % 6;
        float ox = (corner == 1 || corner == 3 || corner == 4) ? 1.0 : 0.0;
        float oy = (corner == 2 || corner == 4 || corner == 5) ? 1.0 : 0.0;
        float2 g = float2((float(cell % 6) + ox) / 6.0, (float(cell / 6) + oy) / 6.0);
        float2 size = inst.rect.zw;
        float2 centre = inst.rect.xy + size * 0.5;
        float2 local = (g - 0.5) * size;
        float time = u.info0.z;
        float level = u.info0.w;
        int mode = int(u.info1.x + 0.5);
        float age = inst.extra.x;
        float seed = inst.extra.y;
        float hit = age < 3.0 ? 1.0 : 0.0;
        float fx = 0.0;

        // With flow, the letters bob a little, more at each level.
        if (level >= 2.0) { local.y += sin(time * 3.0 + seed * 6.283) * 0.5 * (level - 1.0); }

        if (mode == 1) {
            // Jelly: squash, wobble and settle.
            float e = exp(-age * 4.5) * sin(age * 26.0) * hit;
            local.x *= 1.0 + 0.32 * e;
            local.y *= 1.0 - 0.28 * e;
            local.x += sin(g.y * 6.283 + age * 24.0) * e * 0.08 * size.x;
            local *= 1.0 + 0.25 * exp(-age * 8.0) * hit;
            fx = abs(e);
        } else if (mode == 2) {
            // Wave: the hit letter ripples, and a ring runs out from each touch.
            float e = exp(-age * 3.0) * hit;
            local.y += sin(g.x * 6.283 - age * 14.0) * 0.12 * size.y * e;
            local.x += sin(g.y * 6.283 - age * 10.0) * 0.05 * size.x * e;
            int n = int(u.info1.y + 0.5);
            for (int i = 0; i < 4; i++) {
                if (i >= n) { break; }
                float4 t = u.touches[i];
                float d = distance(centre, t.xy);
                float front = t.z * 420.0;
                float ring = exp(-pow((d - front) / 40.0, 2.0)) * exp(-t.z * 2.5);
                local.y -= ring * 0.22 * size.y;
                local *= 1.0 + ring * 0.2;
            }
            fx = e;
        } else if (mode == 3) {
            // Glitch: slices jump sideways; at Blizzard letters glitch now and then.
            float e = exp(-age * 5.0) * hit;
            if (level >= 3.0 && hash1(seed * 31.0 + floor(time * 12.0)) > 0.985) { e = max(e, 0.6); }
            float row = float(cell / 6);
            float j = hash1(row * 7.0 + floor(time * 20.0) + seed * 13.0) - 0.5;
            local.x += j * 0.35 * size.x * e;
            fx = e;
        } else if (mode == 4) {
            // Liquid: the bottom drips down, then pulls back.
            float e = smoothstep(0.0, 0.12, age) * (1.0 - smoothstep(0.5, 1.4, age)) * hit;
            float drip = pow(g.y, 2.5);
            local.y += drip * size.y * 0.55 * e * (0.6 + 0.4 * sin(g.x * 12.0 + seed * 6.0));
            local.x += sin(g.y * 5.0 + age * 6.0) * 0.04 * size.x * e;
            local.x *= 1.0 + 0.12 * e * (1.0 - g.y);
            fx = e;
        }

        float2 pos = centre + local;
        LetterOut o;
        o.position = float4(pos.x / u.info0.x * 2.0 - 1.0, 1.0 - pos.y / u.info0.y * 2.0, 0.0, 1.0);
        o.uv = mix(inst.uv.xy, inst.uv.zw, g);
        float4 c = inst.color;
        if (level >= 4.0) {
            // Aurora: the letters shimmer between the thumbs' colours.
            float s = 0.5 + 0.5 * sin(time * 2.2 + centre.x * 0.025 + centre.y * 0.01);
            c.rgb = mix(c.rgb, mix(u.left.rgb, u.right.rgb, s), 0.55);
        }
        o.color = c;
        o.fx = fx;
        o.uvw = inst.uv.z - inst.uv.x;
        return o;
    }

    fragment float4 letter_fragment(LetterOut in [[stage_in]], texture2d<float> atlas [[texture(0)]],
                                    constant LetterUniforms &u [[buffer(0)]]) {
        constexpr sampler s(filter::linear, address::clamp_to_zero);
        int mode = int(u.info1.x + 0.5);
        float c = atlas.sample(s, in.uv).r;
        if (mode == 3 && in.fx > 0.01) {
            float shift = in.fx * 0.12 * in.uvw;
            float cr = atlas.sample(s, in.uv + float2(shift, 0.0)).r;
            float cb = atlas.sample(s, in.uv - float2(shift, 0.0)).r;
            float3 col = in.color.rgb * c + float3(1.0, 0.15, 0.35) * max(cr - c, 0.0) + float3(0.1, 0.85, 1.0) * max(cb - c, 0.0);
            float a = max(c, max(cr, cb));
            return float4(col, a) * in.color.a;
        }
        if (mode == 4) { c = mix(c, smoothstep(0.25, 0.55, c), in.fx); }
        float a = c * in.color.a;
        return float4(in.color.rgb * a, a);
    }
    """
}

/// The sky behind the keys at Aurora, drawn at half resolution.
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

/// The letter keys' labels, drawn with Metal so Jelly, Wave, Glitch and Liquid can bend
/// them. The keys hide their own labels while this draws (`KeyView.lettersElsewhere`).
@MainActor
final class LetterRenderer {
    let layer: CAMetalLayer
    var mode: EffectsSettings.Letters = .none

    private struct Uniforms {
        var info0: SIMD4<Float>
        var info1: SIMD4<Float>
        var touches: (SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>)
        var left: SIMD4<Float>
        var right: SIMD4<Float>
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
    private var prepared: (letters: [Character], font: UIFont, scale: CGFloat)?

    init(metal: MetalKeyboard) {
        self.metal = metal
        layer = metal.makeLayer()
    }

    func layout(_ bounds: CGRect, scale: CGFloat) {
        MetalKeyboard.size(layer, bounds: bounds, scale: scale)
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

    private var duration: TimeInterval { mode == .liquid ? 1.6 : 1.2 }

    func hit(_ key: Key, at point: CGPoint, time: TimeInterval) {
        hits[key] = (time, Float.random(in: 0...1))
        touches.append((point, time))
        if touches.count > 4 { touches.removeFirst(touches.count - 4) }
    }

    func isAnimating(time: TimeInterval) -> Bool {
        hits.values.contains { time - $0.time < duration } || touches.contains { time - $0.time < 1.5 }
    }

    func render(keys: [(key: Key, letter: Character, frame: CGRect, ink: UIColor)], time: TimeInterval, level: Int,
                style: KeyStyle) {
        hits = hits.filter { time - $0.value.time < 3 }
        touches.removeAll { time - $0.time >= 1.5 }
        var instances: [Instance] = []
        if let _ = atlas, style.shape.showsLetters {
            instances.reserveCapacity(keys.count)
            for key in keys {
                guard let uv = glyphs[key.letter] else { continue }
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
        }
        var uniforms = Uniforms(
            info0: SIMD4(Float(layer.bounds.width), Float(layer.bounds.height), Float((time - start).truncatingRemainder(dividingBy: 3600)), Float(level)),
            info1: SIMD4(modeValue, Float(touchList.count), 0, 0),
            touches: (touch(0), touch(1), touch(2), touch(3)),
            left: Self.rgba(style.thumb(.left)), right: Self.rgba(style.thumb(.right)))
        let buffer = instances.isEmpty ? nil : instanceBuffer(instances)
        let pipeline = metal.letters
        let atlas = self.atlas
        metal.draw(on: layer) { encoder in
            guard let buffer, let atlas, uniforms.info0.x > 0 else { return }
            encoder.setRenderPipelineState(pipeline)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
            encoder.setVertexBuffer(buffer, offset: 0, index: 1)
            encoder.setFragmentTexture(atlas, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 216, instanceCount: instances.count)
        }
    }

    /// Three buffers taken in turn, so the GPU never reads one being written.
    private func instanceBuffer(_ instances: [Instance]) -> (any MTLBuffer)? {
        let length = MemoryLayout<Instance>.stride * instances.count
        if buffers.count < 3 || buffers[next].length < length {
            let capacity = max(length, MemoryLayout<Instance>.stride * 64)
            guard let buffer = metal.device.makeBuffer(length: capacity, options: .storageModeShared) else { return nil }
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
