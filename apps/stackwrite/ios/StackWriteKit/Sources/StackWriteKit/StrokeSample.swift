import Foundation

/// One point of a stroke, in box units: the writing pad is 1×1 with (0,0)
/// at the bottom-left and y pointing up. `t` is seconds since touch down.
/// Encoded as `[x, y, t]` to keep sample files small.
public struct StrokePoint: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var t: Double

    public init(x: Double, y: Double, t: Double) {
        self.x = x
        self.y = y
        self.t = t
    }

    /// Converts a touch location in the pad's own coordinates (y down) to box
    /// units. A pad that isn't square is normalized by its height, with x centered.
    public init(touch: CGPoint, padSize: CGSize, t: Double) {
        let side = max(padSize.height, 1)
        x = (touch.x - (padSize.width - side) / 2) / side
        y = 1 - touch.y / side
        self.t = t
    }

    public init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        x = try c.decode(Double.self)
        y = try c.decode(Double.self)
        t = try c.decode(Double.self)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        try c.encode(Self.round(x, 1e5))
        try c.encode(Self.round(y, 1e5))
        try c.encode(Self.round(t, 1e4))
    }

    private static func round(_ v: Double, _ scale: Double) -> Double {
        (v * scale).rounded() / scale
    }
}

/// One recorded word: a single stroke plus what it was meant to say.
/// This is the format shared by the training screen, the keyboard, the upload
/// and the Python tools (`ml/samples.py`). See `SAMPLES.md`.
public struct StrokeSample: Codable, Identifiable, Hashable, Sendable {
    public static let currentVersion = 1

    /// How the label is known.
    public enum LabelSource: String, Codable, Sendable {
        /// The writer was asked to write this word (training screen).
        case prompt
        /// The writer picked this word from the suggestions after writing.
        case picked
        /// The keyboard committed its top guess and the writer kept it.
        case committed
    }

    public var version: Int
    public var id: UUID
    /// The word the stroke spells, lowercase a–z.
    public var label: String
    public var labelSource: LabelSource
    public var points: [StrokePoint]
    /// Size of the writing pad in points, for telling pad shapes apart later.
    public var padWidth: Double
    public var padHeight: Double
    /// Random ID per install, so samples from one writer can be grouped.
    public var writer: String
    /// Groups the words written in one sitting.
    public var session: String
    public var device: String
    public var system: String
    public var app: String
    public var createdAt: Date
    /// The phrase the word came from, when it was prompted.
    public var prompt: String?
    /// What the model read at the time, best first.
    public var recognized: [String]?

    public init(
        id: UUID = UUID(),
        label: String,
        labelSource: LabelSource,
        points: [StrokePoint],
        padSize: CGSize,
        writer: String,
        session: String,
        device: String,
        system: String,
        app: String,
        createdAt: Date = Date(),
        prompt: String? = nil,
        recognized: [String]? = nil
    ) {
        version = Self.currentVersion
        self.id = id
        self.label = label
        self.labelSource = labelSource
        self.points = points
        padWidth = padSize.width
        padHeight = padSize.height
        self.writer = writer
        self.session = session
        self.device = device
        self.system = system
        self.app = app
        self.createdAt = createdAt
        self.prompt = prompt
        self.recognized = recognized
    }

    public static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    public static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
