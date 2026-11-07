#if canImport(UIKit)
import AstrotypeCore
import Metal
import QuartzCore
import UIKit

/// The Metal side of the effects (features/customization "Letters on Metal"): one
/// device, queue and pair of pipelines, made off the main thread the first time an
/// effect asks for them (`load`) and shared by the sky and the letters. The shaders are
/// compiled from source here, so the package needs no metallib; that takes a few hundred
/// ms, so the keys open drawn by Core Animation and move to Metal once it is there
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
    /// How long the shaders took to compile, in ms, for the open timings; 0 until done.
    private(set) static var loadMillis = 0
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

    private nonisolated init?() {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
        do {
            let library = try device.makeLibrary(source: Self.source, options: nil)
            sky = try Self.pipeline(device, library, vertex: "sky_vertex", fragment: "sky_fragment")
            letters = try Self.pipeline(device, library, vertex: "letter_vertex", fragment: "letter_fragment")
            keys = try Self.pipeline(device, library, vertex: "key_vertex", fragment: "key_fragment")
        } catch {
            return nil
        }
        self.device = device
        self.queue = queue
    }

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
    nonisolated static let source = """
    #include <metal_stdlib>
    using namespace metal;

    // x * x: pow of a negative number is undefined in Metal.
    static float sq(float x) { return x * x; }
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

    static float3 rainbow(float h) { return 0.5 + 0.5 * cos(6.2832 * (h + float3(0.0, 0.33, 0.67))); }

    fragment float4 sky_fragment(SkyOut in [[stage_in]], constant float4 &info [[buffer(0)]]) {
        float2 uv = in.uv;
        float2 r = info.xy;
        float t = info.z;
        int mode = int(info.w + 0.5);
        float aspect = r.x / max(r.y, 1.0);
        float2 p = (uv - 0.5) * float2(aspect, 1.0);
        float3 col = float3(0.0);
        // Opacity without colour, for the black hole's dark middle.
        float dark = 0.0;
        if (mode == 0) {
            // Aurora: four bands that sway.
            for (int i = 0; i < 4; i++) {
                float fi = float(i);
                float w = 0.62 - fi * 0.1 + sin(uv.x * (2.5 + fi) + t * 0.6 + fi * 1.7) * 0.09 + sin(uv.x * 7.0 + t * 1.2 + fi) * 0.025;
                float b = exp(-sq((uv.y - w) * (8.0 + fi * 2.0)));
                col += b * mix(float3(0.18, 0.95, 0.62), float3(0.55, 0.35, 1.0), fi / 3.0) * (0.65 + 0.35 * sin(uv.x * 30.0 + t * 2.4 + fi * 3.0));
            }
        } else if (mode == 1) {
            // Starfield: three layers of stars flying out.
            for (int l = 0; l < 3; l++) {
                float z = fract(t * 0.3 + float(l) / 3.0);
                float s = mix(18.0, 3.0, z);
                float2 g = p * s;
                float2 id = floor(g);
                float2 f = fract(g) - 0.5;
                float k = hash2(id + float(l) * 7.0);
                float d = length(f - (float2(k, fract(k * 13.0)) - 0.5) * 0.7);
                col += float3(0.9, 0.85, 1.0) * (1.0 - smoothstep(0.0, 0.09, d)) * smoothstep(0.0, 0.3, z) * (1.0 - smoothstep(0.75, 1.0, z)) * step(0.55, k);
            }
            col += float3(0.45, 0.15, 0.75) * 0.25 * max(0.0, 1.0 - length(p));
        } else if (mode == 2) {
            // Ice: caustics.
            float2 q0 = uv * 6.0;
            float2 q = q0;
            float c = 1.0;
            for (int n = 0; n < 4; n++) {
                float tt = t * 0.6 * (1.0 - 3.5 / float(n + 1));
                q = q0 + float2(cos(tt - q.x) + sin(tt + q.y), sin(tt - q.y) + cos(tt + q.x));
                float2 v = float2(q0.x * 0.005 / (sin(q.x + tt) + 1e-4), q0.y * 0.005 / (cos(q.y + tt) + 1e-4));
                c += 1.0 / max(length(v), 1e-4);
            }
            c /= 4.0;
            c = 1.17 - pow(abs(c), 1.4);
            float v = pow(abs(c), 8.0);
            col = float3(0.2, 0.75, 0.95) * clamp(v, 0.0, 1.0) * 0.9 + float3(0.05, 0.2, 0.35) * 0.6;
        } else if (mode == 3) {
            // Retro grid: a neon floor racing in under a striped sun, with scanlines.
            float horizon = 0.42;
            if (uv.y > horizon) {
                float2 d = (uv - float2(0.5, horizon + 0.2)) * float2(aspect, 1.0);
                float sun = 1.0 - smoothstep(0.17, 0.18, length(d));
                float cut = step(0.0, sin((uv.y - horizon) * 70.0 + t * 3.0)) + step(horizon + 0.2, uv.y);
                col += sun * min(cut, 1.0) * mix(float3(1.0, 0.15, 0.55), float3(1.0, 0.85, 0.2), smoothstep(horizon, horizon + 0.38, uv.y));
                col += float3(0.4, 0.05, 0.55) * (1.0 - smoothstep(horizon, 1.0, uv.y)) * 0.5;
            } else {
                float depth = 1.0 / max(horizon - uv.y, 0.002);
                float x = (uv.x - 0.5) * depth * 0.5;
                float z = depth * 0.25 + t * 2.5;
                float gx = abs(fract(x) - 0.5);
                float gz = abs(fract(z) - 0.5);
                float lx = smoothstep(0.5 - 1.5 * fwidth(x), 0.5, gx);
                float lz = smoothstep(0.5 - 1.5 * fwidth(z), 0.5, gz);
                float fade = 1.0 - exp(-(horizon - uv.y) * 10.0);
                col += float3(1.0, 0.2, 0.9) * max(lx, lz) * fade;
                col += float3(0.25, 0.0, 0.4) * (1.0 - uv.y / horizon) * 0.4;
            }
            col *= 0.8 + 0.2 * step(0.5, fract(uv.y * r.y * 0.25));
        } else if (mode == 4) {
            // Glitch: torn bands, blocks of split colour, a rolling bar and noise.
            float tt = floor(t * 15.0);
            float band = floor(uv.y * 24.0);
            float n = hash2(float2(band, tt));
            float shift = n > 0.8 ? (hash1(band + tt) - 0.5) * 0.25 : 0.0;
            float2 q = float2(uv.x + shift, uv.y);
            float b = hash2(floor(q * float2(18.0, 10.0)) + tt * 0.37);
            float3 split = mix(float3(1.0, 0.1, 0.35), float3(0.1, 0.9, 1.0), step(0.5, hash1(b * 91.0)));
            col += step(0.93, b) * split * 0.8;
            col += float3(0.2, 1.0, 0.6) * 0.15 * step(0.5, fract(uv.y * r.y * 0.25 + t * 20.0)) * step(0.7, n);
            col += float3(0.7, 0.9, 1.0) * 0.3 * exp(-sq((uv.y - fract(t * 0.7)) * 30.0));
            col += hash2(floor(uv * r * 0.5) + tt) * 0.07;
        } else if (mode == 5) {
            // Prism: a rainbow that swirls out from the middle.
            float ang = atan2(p.y, p.x);
            float d = length(p);
            float h = ang / 6.2832 + d * 1.5 - t * 0.5 + 0.1 * sin(d * 10.0 - t * 3.0);
            float rays = 0.6 + 0.4 * sin(ang * 8.0 + t * 2.0);
            col = rainbow(h) * rays * (0.45 + 0.25 * sin(d * 12.0 - t * 4.0));
        } else if (mode == 6) {
            // Black hole: a glowing disk and stars spiralling in, round a dark middle.
            float d = length(p);
            float ang = atan2(p.y, p.x);
            float tw = ang + 0.9 / (d + 0.08) + t * 1.4;
            float disk = pow(0.5 + 0.5 * sin(tw * 3.0 + log(d + 1e-3) * 6.0 + t * 4.0), 3.0);
            float glow = disk * smoothstep(0.1, 0.22, d) * exp(-d * 2.5);
            float ring = exp(-sq((d - 0.16) * 16.0));
            col += float3(1.0, 0.55, 0.2) * glow * 1.2 + float3(1.0, 0.85, 0.6) * ring * 0.9 + float3(0.5, 0.25, 1.0) * glow * 0.4;
            float2 g = float2((ang + 0.6 / (d + 0.1)) * 3.82, log(d + 1e-3) * 5.0 + t * 3.0);
            float2 f = fract(g) - 0.5;
            float k = hash2(floor(g));
            float streak = (1.0 - smoothstep(0.0, 0.1, abs(f.x))) * (1.0 - smoothstep(0.05, 0.45, abs(f.y))) * step(0.72, k);
            col += float3(0.85, 0.9, 1.0) * streak * smoothstep(0.12, 0.3, d);
            float core = 1.0 - smoothstep(0.1, 0.135, d);
            col *= 1.0 - core;
            dark = core * 0.92;
        } else if (mode == 7) {
            // Ripples: slow rings spreading on still water, breathing.
            float w = 0.0;
            for (int i = 0; i < 3; i++) {
                float fi = float(i);
                float2 c = float2(sin(t * 0.2 + fi * 2.1) * 0.5 * aspect, cos(t * 0.17 + fi * 1.3) * 0.25);
                float d = length(p - c);
                w += sin(d * 26.0 - t * 2.2 + fi) * exp(-d * 2.2);
            }
            float3 tint = mix(float3(0.25, 0.8, 0.72), float3(0.62, 0.52, 1.0), 0.5 + 0.5 * sin(t * 0.3 + p.x * 2.0));
            float breathe = 0.5 + 0.5 * sin(t * 0.8);
            col = tint * (0.08 + 0.07 * breathe) + tint * smoothstep(0.4, 1.0, w * 0.5 + 0.5) * 0.35;
        } else {
            // Candy clouds: pink and lilac swirls with hearts floating up.
            float pl = sin(p.x * 5.0 + t * 1.3) + sin(p.y * 6.0 - t * 1.7) + sin((p.x + p.y) * 4.0 + t * 2.1);
            float3 pink = float3(1.0, 0.35, 0.7);
            float3 lilac = float3(0.75, 0.45, 1.0);
            col = mix(pink, lilac, 0.5 + 0.5 * sin(pl)) * 0.32;
            for (int l = 0; l < 2; l++) {
                float fl = float(l);
                float2 g = p * (5.0 + fl * 3.0) - float2(0.0, t * (1.2 + fl * 0.6));
                float2 id = floor(g);
                float k = hash2(id + fl * 13.0);
                float2 f = fract(g) - 0.5 - (float2(k, fract(k * 7.0)) - 0.5) * 0.3;
                float hx = f.x * 3.0;
                float hy = f.y * 3.0 + 0.15;
                float q = hx * hx + hy * hy - 1.0;
                float v = q * q * q - hx * hx * hy * hy * hy;
                float heart = 1.0 - smoothstep(-0.02, 0.04, v);
                col += heart * step(0.6, k) * mix(pink, float3(1.0), 0.35) * 0.75;
            }
        }
        // The keys don't reach the screen's edges, so the sky fades out before its own
        // edges instead of looking cut off (Gabriel, 7 Nov 2026).
        float edge = smoothstep(0.0, 0.12, uv.x) * smoothstep(0.0, 0.12, 1.0 - uv.x) * smoothstep(0.0, 0.16, uv.y) * smoothstep(0.0, 0.12, 1.0 - uv.y);
        col = clamp(col, 0.0, 1.0) * edge;
        float a = max(max(col.r, max(col.g, col.b)), dark * edge);
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
        float2 g;
        float4 cellRect;
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
                float ring = exp(-sq((d - front) / 40.0)) * exp(-t.z * 2.5);
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
        } else if (mode == 5) {
            // Pixel: the letter hops in steps like an 8-bit sprite and grows blockier.
            float e = exp(-age * 5.0) * hit;
            float hop = floor(max(0.0, sin(age * 12.0)) * exp(-age * 3.0) * 4.0 + 0.5) / 4.0;
            local.y -= hop * 0.35 * size.y * hit;
            local *= 1.0 + floor(e * 4.0) / 4.0 * 0.3;
            fx = e;
        } else if (mode == 6) {
            // Disco: the letter spins once, jumps, and flashes through the rainbow.
            float spin = smoothstep(0.0, 0.45, age) * 6.2832 * hit;
            float cs = cos(spin);
            float sn = sin(spin);
            local = float2(local.x * cs - local.y * sn, local.x * sn + local.y * cs);
            local *= 1.0 + 0.45 * exp(-age * 6.0) * hit;
            local.y -= sin(min(age * 9.0, 3.1416)) * 0.3 * size.y * hit;
            fx = exp(-age * 4.0) * hit;
        } else if (mode == 7) {
            // Warp: the letter stretches out from the middle at speed; at the top level
            // every letter leans in and turns, falling into the black hole.
            float e = exp(-age * 5.0) * hit;
            float2 sc = u.info0.xy * 0.5;
            float2 v = centre - sc;
            float2 dir = v / max(length(v), 1.0);
            local += dir * dot(local, dir) * 1.4 * e + dir * e * size.y * 0.5;
            if (level >= 4.0) {
                float pull = 0.5 + 0.5 * sin(time * 1.4 + seed * 6.283);
                float ang = 0.035 * pull;
                float2 rv = float2(v.x * cos(ang) - v.y * sin(ang), v.x * sin(ang) + v.y * cos(ang));
                local += rv * (1.0 - 0.04 * pull) - v;
                local *= 1.0 - 0.12 * pull;
            }
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
        if (mode == 6) {
            float glow = clamp(fx + (level >= 2.0 ? 0.35 : 0.0) + (level >= 4.0 ? 0.3 : 0.0), 0.0, 1.0);
            c.rgb = mix(c.rgb, rainbow(time * 0.8 + centre.x * 0.004 + seed), glow);
        } else if (mode == 7) {
            c.rgb = mix(c.rgb, float3(0.7, 0.85, 1.0), fx * 0.6);
        }
        o.color = c;
        o.fx = fx;
        o.g = g;
        o.cellRect = inst.uv;
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
        if (mode == 5) {
            // Pixel: sample the glyph on a coarse grid with hard edges.
            float n = mix(20.0, 7.0, clamp(in.fx, 0.0, 1.0));
            float2 gq = (floor(in.g * n) + 0.5) / n;
            c = step(0.45, atlas.sample(s, mix(in.cellRect.xy, in.cellRect.zw, gq)).r);
        }
        float a = c * in.color.a;
        return float4(in.color.rgb * a, a);
    }

    // Key effects: one quad per key, a little bigger than the key for its glow, and a
    // rounded-rectangle distance in the fragment so the effect hugs the key's shape.
    struct KeyOut {
        float4 position [[position]];
        float2 local;
        float2 halfSize;
        float2 world;
        float2 info;
        float2 centre;
    };

    vertex KeyOut key_vertex(uint vid [[vertex_id]], uint iid [[instance_id]],
                             constant LetterUniforms &u [[buffer(0)]],
                             const device LetterInstance *instances [[buffer(1)]]) {
        LetterInstance inst = instances[iid];
        float ox = (vid == 1 || vid == 3 || vid == 4) ? 1.0 : 0.0;
        float oy = (vid == 2 || vid == 4 || vid == 5) ? 1.0 : 0.0;
        float2 hs = inst.rect.zw * 0.5;
        float2 centre = inst.rect.xy + hs;
        float2 local = (float2(ox, oy) * 2.0 - 1.0) * (hs + 12.0);
        float2 pos = centre + local;
        KeyOut o;
        o.position = float4(pos.x / u.info0.x * 2.0 - 1.0, 1.0 - pos.y / u.info0.y * 2.0, 0.0, 1.0);
        o.local = local;
        o.halfSize = hs;
        o.world = pos;
        o.info = inst.extra.xy;
        o.centre = centre;
        return o;
    }

    static float roundBox(float2 p, float2 b, float r) {
        float2 q = abs(p) - b + r;
        return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
    }

    fragment float4 key_fragment(KeyOut in [[stage_in]], constant LetterUniforms &u [[buffer(0)]]) {
        float2 q = in.local;
        float2 hs = in.halfSize;
        float radius = min(u.info1.w, min(hs.x, hs.y));
        float d = roundBox(q, hs, radius);
        float inside = 1.0 - smoothstep(-0.75, 0.75, d);
        float border = 1.0 - smoothstep(0.6, 2.0, abs(d));
        float halo = exp(-max(d, 0.0) / 4.0) * step(0.0, d);
        float time = u.info0.z;
        float level = u.info0.w;
        int mode = int(u.info1.z + 0.5);
        float age = in.info.x;
        float seed = in.info.y;
        float hit = age < 3.0 ? 1.0 : 0.0;
        float3 col = float3(0.0);
        if (mode == 1) {
            // Neon: the hit key's outline flares; with flow, lights chase round every key.
            float e = exp(-age * 3.0) * hit;
            float3 neon = mix(float3(1.0, 0.17, 0.84), float3(0.13, 0.9, 1.0), step(0.5, fract(seed * 7.0)));
            float march = step(0.55, fract(atan2(q.y, q.x) / 6.2832 * 4.0 - time * 1.5 + seed));
            float ambient = (level >= 2.0 ? 0.35 : 0.0) + (level >= 4.0 ? 0.35 : 0.0);
            float k = max(e * 1.3, ambient * march);
            float scan = step(0.5, fract(q.y * 0.5 + time * 6.0));
            col = neon * (border * k + halo * 0.7 * k) + neon * inside * e * 0.35 * scan;
        } else if (mode == 2) {
            // Glitch: the outline splits red and cyan, blocks inside corrupt, slices tear.
            float e = exp(-age * 4.0) * hit;
            if (level >= 3.0 && hash1(seed * 17.0 + floor(time * 9.0)) > 0.93) { e = max(e, 0.75); }
            float tt = floor(time * 24.0);
            float2 off = float2(hash1(tt + seed * 5.0) - 0.5, (hash1(tt * 1.3 + seed) - 0.5) * 0.4) * 10.0 * e;
            float slice = step(0.75, hash1(floor((q.y + hs.y) / 4.0) + tt + seed * 3.0)) * e;
            float2 qs = q + float2(slice * 6.0, 0.0);
            float red = 1.0 - smoothstep(0.6, 2.0, abs(roundBox(qs - off, hs, radius)));
            float cyan = 1.0 - smoothstep(0.6, 2.0, abs(roundBox(qs + off, hs, radius)));
            float b = hash2(floor((q + hs) / float2(5.0, 3.0)) + tt * 0.71 + seed * 11.0);
            float blocks = inside * step(1.0 - 0.35 * e, b);
            float3 bc = mix(float3(1.0, 0.12, 0.31), float3(0.1, 0.9, 1.0), step(0.5, fract(b * 13.0)));
            bc = mix(bc, float3(1.0), step(0.85, fract(b * 29.0)));
            col = float3(1.0, 0.12, 0.31) * red * e + float3(0.1, 0.9, 1.0) * cyan * e + bc * blocks * 0.85 + inside * slice * 0.25;
        } else if (mode == 3) {
            // Holo foil: a rainbow sheen drifts over the keys; a hit key flares and shines.
            float e = exp(-age * 2.5) * hit;
            float amount = e + (level >= 2.0 ? 0.2 : 0.0) + (level >= 4.0 ? 0.2 : 0.0);
            float h = in.world.x * 0.004 + in.world.y * 0.006 - time * 0.35 + seed * 0.2;
            float band = 0.5 + 0.5 * sin((q.x - q.y) * 0.18 + time * 3.0);
            float sweep = exp(-sq((q.x + q.y) / max(hs.x + hs.y, 1.0) - (age * 3.0 - 1.0)) * 6.0) * hit;
            col = rainbow(h) * inside * amount * 0.45 * band + rainbow(h + 0.5) * border * amount * 0.9 + float3(1.0) * inside * sweep * 0.5;
        } else if (mode == 4) {
            // Warp: stars rush out of a hit key; at the top each key's edge facing the
            // black hole burns.
            float e = exp(-age * 2.5) * hit;
            float amb = level >= 3.0 ? 0.3 : 0.0;
            float r = length(q) / max(length(hs), 1.0);
            float ang = atan2(q.y, q.x);
            float2 g = float2(ang * 3.82, log(r + 0.02) * 3.0 - time * 5.0);
            float2 f = fract(g) - 0.5;
            float k = hash2(floor(g) + seed * 7.0);
            float star = (1.0 - smoothstep(0.0, 0.1, abs(f.x))) * (1.0 - smoothstep(0.05, 0.45, abs(f.y))) * step(0.68, k);
            col = float3(0.8, 0.9, 1.0) * star * inside * max(e, amb) + float3(0.45, 0.65, 1.0) * (border + halo * 0.5) * e;
            if (level >= 4.0) {
                float2 toward = u.info0.xy * 0.5 - in.centre;
                float facing = dot(normalize(q + 0.0001), normalize(toward + 0.0001));
                float burn = smoothstep(0.2, 1.0, facing) * (0.6 + 0.4 * sin(time * 4.0 + seed * 6.0));
                col += float3(1.0, 0.55, 0.2) * (border + halo * 0.8) * burn;
            }
        } else if (mode == 5) {
            // Ripple: soft rings run out from each touch through the keys.
            float3 tint = mix(float3(0.45, 0.9, 0.8), float3(0.72, 0.62, 1.0), 0.5 + 0.5 * sin(time * 0.6 + in.world.x * 0.01));
            float ring = 0.0;
            int n = int(u.info1.y + 0.5);
            for (int i = 0; i < 4; i++) {
                if (i >= n) { break; }
                float4 t = u.touches[i];
                float dd = distance(in.world, t.xy);
                ring += exp(-sq((dd - t.z * 240.0) / 16.0)) * exp(-t.z * 1.6);
            }
            float e = exp(-age * 2.0) * hit;
            float breathe = level >= 3.0 ? 0.18 * (0.5 + 0.5 * sin(time * 1.3 + seed * 6.283)) : 0.0;
            col = tint * (inside * (ring * 0.3 + e * 0.2) + border * (ring * 0.7 + e * 0.5 + breathe) + halo * breathe);
        } else if (mode == 6) {
            // Candy gloss: a shine sweeps the hit key, a pink glow, sparkles inside.
            float e = exp(-age * 2.5) * hit;
            float amb = (level >= 2.0 ? 0.3 : 0.0) + (level >= 4.0 ? 0.25 : 0.0);
            float3 pink = mix(float3(1.0, 0.31, 0.64), float3(0.77, 0.55, 1.0), 0.5 + 0.5 * sin(time * 1.5 + seed * 6.0));
            float sweep = exp(-sq((q.x * 0.8 + q.y * 0.6) / max(hs.x, 1.0) - (age * 4.0 - 1.5)) * 5.0) * hit;
            float2 g = (q + hs) / 7.0;
            float2 f = fract(g) - 0.5;
            float k = hash2(floor(g) + seed * 3.0 + floor(time * 2.0));
            float tw = (1.0 - smoothstep(0.0, 0.05, abs(f.x))) * (1.0 - smoothstep(0.0, 0.35, abs(f.y)))
                     + (1.0 - smoothstep(0.0, 0.05, abs(f.y))) * (1.0 - smoothstep(0.0, 0.35, abs(f.x)));
            float sparkle = inside * tw * step(0.82, k) * max(e, level >= 3.0 ? 0.6 : 0.0);
            col = pink * (border + halo * 0.8) * max(e, amb) + float3(1.0) * inside * sweep * 0.55 + float3(1.0, 0.9, 0.95) * sparkle;
        }
        col = clamp(col, 0.0, 1.0);
        float a = max(col.r, max(col.g, col.b));
        return float4(col, a);
    }
    """
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
/// both, so a second full-size drawable isn't needed. The keys hide their own labels while this draws (`KeyView.lettersElsewhere`).
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

    func render(keys: [(key: Key, letter: Character, frame: CGRect, ink: UIColor)], frames: [(key: Key, frame: CGRect)],
                time: TimeInterval, level: Int, style: KeyStyle) {
        hits = hits.filter { time - $0.value.time < 3 }
        touches.removeAll { time - $0.time >= 1.5 }
        var instances: [Instance] = []
        if mode != .none, atlas != nil, style.shape.showsLetters {
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
            left: Self.rgba(style.thumb(.left)), right: Self.rgba(style.thumb(.right)))
        let buffer = instances.isEmpty ? nil : Self.instanceBuffer(instances, device: metal.device, ring: &buffers, next: &next)
        let keyBuffer = keyInstances.isEmpty ? nil : Self.instanceBuffer(keyInstances, device: metal.device, ring: &keyBuffers, next: &keyNext)
        let pipeline = metal.letters
        let keyPipeline = metal.keys
        let atlas = self.atlas
        let keyCount = keyInstances.count
        metal.draw(on: layer) { encoder in
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
