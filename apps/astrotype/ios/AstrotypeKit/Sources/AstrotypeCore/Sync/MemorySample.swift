import Foundation

/// One reading of the keyboard's memory, taken once a second while it shows and shared
/// by everything that wants one: the stats overlay, the Debug page's file, the health
/// numbers sent to Sentry, and the typing log (`TypingEvent.Kind.memory`). Holds nothing
/// typed.
public struct MemorySample: Codable, Sendable, Equatable {
    /// The physical footprint iOS counts, in MB.
    public var mb: Double
    /// How much more before iOS ends the keyboard, in MB; 0 where iOS doesn't say.
    public var left: Double
    /// Bytes in use by malloc, in MB (our objects); nil where it can't be read.
    public var heap: Double?
    public var layers: Int
    public var views: Int
    public var metal: Bool
    public var counts: LiveCount.Counts
    /// Where the rest ("other") sits: graphics, Core ML, compressed. Nil where it can't be read.
    public var split: MemorySplit?
    /// The biggest kinds of memory by region (`MemoryRegions.line`), on the readings
    /// that walk the regions (show, hide, warnings, the overlay every few seconds).
    public var regions: String?

    public init(reading: MemoryReading, heapMB: Double?, layers: Int = 0, views: Int = 0, metal: Bool = false,
                counts: LiveCount.Counts = LiveCount.now, split: MemorySplit? = nil) {
        mb = Self.round(reading.footprintMB)
        left = Self.round(reading.headroomMB)
        heap = heapMB.map(Self.round)
        self.split = split.map { $0.rounded() }
        self.layers = layers
        self.views = views
        self.metal = metal
        self.counts = counts
    }

    public var reading: MemoryReading { MemoryReading(footprintMB: mb, headroomMB: left) }

    /// For the log's timeline: "52.1 MB · heap 40.2 · 125 left · 130 layers · 1 keyboard · 2 models · ...".
    public var line: String {
        var parts = ["\(MemoryReading.mb(mb)) MB"]
        if let heap { parts.append("heap \(MemoryReading.mb(heap))") }
        if let split, !split.line.isEmpty { parts.append(split.line) }
        if left > 0 { parts.append("\(Int(left.rounded())) left") }
        if let regions, !regions.isEmpty { parts.append("[\(regions)]") }
        parts.append("\(layers) layers")
        if metal { parts.append("metal") }
        parts.append(counts.line)
        return parts.joined(separator: " · ")
    }

    fileprivate static func round(_ value: Double) -> Double { (value * 10).rounded() / 10 }
}

/// The parts of the footprint that aren't malloc, in MB, from the kernel's ledgers
/// (`MemoryReading.split()`). Tells which kind of memory "other" is growing in.
public struct MemorySplit: Codable, Sendable, Equatable {
    /// Metal textures and buffers, IOSurfaces (layer backing stores, drawables).
    public var graphics: Double
    /// Core ML and the Neural Engine.
    public var neural: Double
    public var media: Double
    /// Memory the kernel compressed; still counted against the limit.
    public var compressed: Double

    public init(graphics: Double = 0, neural: Double = 0, media: Double = 0, compressed: Double = 0) {
        self.graphics = graphics
        self.neural = neural
        self.media = media
        self.compressed = compressed
    }

    func rounded() -> MemorySplit {
        MemorySplit(graphics: MemorySample.round(graphics), neural: MemorySample.round(neural),
                    media: MemorySample.round(media),
                    compressed: MemorySample.round(compressed))
    }

    /// "gfx 31.2 · zip 2.1", leaving out the parts that are empty.
    public var line: String {
        [("gfx", graphics), ("ml", neural), ("media", media), ("zip", compressed)]
            .filter { $0.1 >= 0.1 }
            .map { "\($0.0) \(MemoryReading.mb($0.1))" }
            .joined(separator: " · ")
    }
}

/// When a once-a-second reading goes into the typing log: every `interval` seconds, at
/// once when memory jumps by `jumpMB` or more, and when one of the live counts changes
/// (a keyboard made or freed, a dictionary load, a sync starting or ending).
public struct MemoryLogPacer: Sendable {
    public static let interval: Double = 10
    public static let jumpMB = 5.0

    private var lastTime: Double?
    private var lastMB: Double?
    private var lastCounts: LiveCount.Counts?

    public init() {}

    /// Why `sample` should be logged now ("tick", "jump", "count"), or nil to skip it.
    /// A reason counts as logged.
    public mutating func reason(for sample: MemorySample, at time: Double) -> String? {
        let why: String?
        if let lastTime, let lastMB, let lastCounts {
            if sample.counts != lastCounts { why = "count" }
            else if abs(sample.mb - lastMB) >= Self.jumpMB { why = "jump" }
            else if time - lastTime >= Self.interval { why = "tick" }
            else { why = nil }
        } else {
            why = "tick"
        }
        if why != nil { logged(sample, at: time) }
        return why
    }

    /// A reading logged for its own reason (shown, hidden, a memory warning).
    public mutating func logged(_ sample: MemorySample, at time: Double) {
        lastTime = time
        lastMB = sample.mb
        lastCounts = sample.counts
    }
}
