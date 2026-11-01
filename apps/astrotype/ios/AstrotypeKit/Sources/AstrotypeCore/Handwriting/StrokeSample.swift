import Foundation

/// One point of a stroke, in box units: the writing pad is 1×1 with (0,0)
/// at the bottom-left and y pointing up. `t` is in seconds (see each use).
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

/// One recording: the strokes of a few words plus what they were meant to say.
/// This is the format shared by the training screen, the keyboard, the upload
/// and the Python tools (`ml/samples.py`). See `SAMPLES.md`.
///
/// Version 1 held one word written as a single stroke (`points`); reading one
/// gives a sample with that one stroke.
public struct StrokeSample: Codable, Identifiable, Hashable, Sendable {
    public static let currentVersion = 2

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
    /// The words written, lowercase a–z separated by single spaces.
    public var label: String
    public var labelSource: LabelSource
    /// Each stroke is touch down to lift. `t` is seconds since the first
    /// stroke's touch down, so the gaps between strokes are the lifts.
    public var strokes: [[StrokePoint]]
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
    /// The text shown to the writer, when prompted.
    public var prompt: String?
    /// What the model read at the time, best first.
    public var recognized: [String]?

    public init(
        id: UUID = UUID(),
        label: String,
        labelSource: LabelSource,
        strokes: [[StrokePoint]],
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
        self.strokes = strokes
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

    enum CodingKeys: String, CodingKey {
        case version, id, label, labelSource, strokes, points, padWidth, padHeight, writer, session
        case device, system, app, createdAt, prompt, recognized
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        id = try c.decode(UUID.self, forKey: .id)
        label = try c.decode(String.self, forKey: .label)
        labelSource = try c.decode(LabelSource.self, forKey: .labelSource)
        if let strokes = try c.decodeIfPresent([[StrokePoint]].self, forKey: .strokes) {
            self.strokes = strokes
        } else {
            strokes = [try c.decode([StrokePoint].self, forKey: .points)]
        }
        padWidth = try c.decode(Double.self, forKey: .padWidth)
        padHeight = try c.decode(Double.self, forKey: .padHeight)
        writer = try c.decode(String.self, forKey: .writer)
        session = try c.decode(String.self, forKey: .session)
        device = try c.decode(String.self, forKey: .device)
        system = try c.decode(String.self, forKey: .system)
        app = try c.decode(String.self, forKey: .app)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        prompt = try c.decodeIfPresent(String.self, forKey: .prompt)
        recognized = try c.decodeIfPresent([String].self, forKey: .recognized)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        try c.encode(id, forKey: .id)
        try c.encode(label, forKey: .label)
        try c.encode(labelSource, forKey: .labelSource)
        if version >= 2 {
            try c.encode(strokes, forKey: .strokes)
        } else {
            try c.encode(strokes.first ?? [], forKey: .points)
        }
        try c.encode(padWidth, forKey: .padWidth)
        try c.encode(padHeight, forKey: .padHeight)
        try c.encode(writer, forKey: .writer)
        try c.encode(session, forKey: .session)
        try c.encode(device, forKey: .device)
        try c.encode(system, forKey: .system)
        try c.encode(app, forKey: .app)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(prompt, forKey: .prompt)
        try c.encodeIfPresent(recognized, forKey: .recognized)
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
