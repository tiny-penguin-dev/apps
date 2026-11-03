import Foundation
#if canImport(Darwin)
import Darwin
#endif
#if os(iOS)
import os
#endif

/// One reading of a process's memory: what iOS counts against its limit (the physical
/// footprint) and how much more it can use before iOS ends it.
///
///     let now = MemoryReading.current()   // nil off iOS and macOS
///     now?.footprintMB                    // 23.4
public struct MemoryReading: Codable, Sendable, Equatable {
    /// What we keep the keyboard extension under (CLAUDE.md, BUILD.md). iOS's real limit
    /// is a little higher and differs by phone; `limitMB` says what it is right now.
    public static let budgetMB = 40.0

    /// The memory iOS counts against the process (its physical footprint), in MB.
    public var footprintMB: Double
    /// How much more it can use before iOS ends it, in MB. Zero where iOS doesn't say.
    public var headroomMB: Double

    public init(footprintMB: Double, headroomMB: Double) {
        self.footprintMB = footprintMB
        self.headroomMB = headroomMB
    }

    /// The limit iOS is holding the process to: what it uses plus what is left. Nil
    /// where iOS doesn't say (not iOS, or no limit).
    public var limitMB: Double? { headroomMB > 0 ? footprintMB + headroomMB : nil }

    /// How much of the 40 MB budget is in use, 0 to 1 and past it.
    public var budgetFraction: Double { footprintMB / Self.budgetMB }

    /// This process's memory now. Nil on Linux, where only the tools and tests run.
    public static func current() -> MemoryReading? {
        #if canImport(Darwin)
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.stride / MemoryLayout<natural_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO),
                      UnsafeMutableRawPointer(pointer).assumingMemoryBound(to: integer_t.self), &count)
        }
        guard result == KERN_SUCCESS else { return nil }
        #if os(iOS)
        let headroom = Double(os_proc_available_memory()) / 1_048_576
        #else
        let headroom = 0.0
        #endif
        return MemoryReading(footprintMB: Double(info.phys_footprint) / 1_048_576, headroomMB: headroom)
        #else
        return nil
        #endif
    }

    /// The keyboard's stats overlay: "23.4/40 MB · peak 25.1 · 31 left", small enough
    /// to sit in a corner of the keys.
    public func overlay(peakMB: Double) -> String {
        var text = "\(Self.mb(footprintMB))/\(Int(Self.budgetMB)) MB · peak \(Self.mb(max(peakMB, footprintMB)))"
        if headroomMB > 0 { text += " · \(Int(headroomMB.rounded(.down))) left" }
        return text
    }

    /// One decimal, like "23.4".
    public static func mb(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}

/// What the keyboard extension last saw of its own memory, for the app's Debug page
/// (Settings → Debug). The extension writes it to the App Group whenever it has Full
/// Access; it stays on the phone and is never sent (`KeyboardHealth` is what goes to
/// Sentry, and only with sharing on).
///
///     var debug = store.load() ?? KeyboardDebug()
///     debug.loaded(at: now)
///     debug.shown(at: now, reading: reading)
///     if debug.sample(reading, at: now) { store.save(debug) }
public struct KeyboardDebug: Codable, Sendable, Equatable {
    public static let version = 1

    public var version = KeyboardDebug.version
    /// When the extension's process last started. A new one while the keyboard was
    /// showing means iOS ended the last one.
    public var loadedAt: Date?
    /// How many times the keyboard came on screen since then.
    public var shows = 0
    /// When the keyboard last came on screen.
    public var shownAt: Date?
    /// When these readings were last taken.
    public var updated: Date?
    /// The last reading.
    public var last: MemoryReading?
    /// The most memory used since the keyboard last came on screen, in MB.
    public var peakMB = 0.0
    /// The least memory left before iOS's limit since then, in MB (0 when iOS doesn't say).
    public var lowestHeadroomMB = 0.0
    /// The most memory used since the process started, in MB.
    public var processPeakMB = 0.0
    /// Memory warnings from iOS since the keyboard last came on screen.
    public var memoryWarnings = 0
    /// Whether the keyboard is on screen, as of the last write. Still true after the
    /// process is gone means it was ended while showing.
    public var showing = false
    /// How many times the process was found ended while the keyboard was showing, and
    /// when it last was (when the next one started).
    public var endedWhileShowing = 0
    public var lastEndedWhileShowing: Date?

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? Self.version
        loadedAt = try c.decodeIfPresent(Date.self, forKey: .loadedAt)
        shows = try c.decodeIfPresent(Int.self, forKey: .shows) ?? 0
        shownAt = try c.decodeIfPresent(Date.self, forKey: .shownAt)
        updated = try c.decodeIfPresent(Date.self, forKey: .updated)
        last = try c.decodeIfPresent(MemoryReading.self, forKey: .last)
        peakMB = try c.decodeIfPresent(Double.self, forKey: .peakMB) ?? 0
        lowestHeadroomMB = try c.decodeIfPresent(Double.self, forKey: .lowestHeadroomMB) ?? 0
        processPeakMB = try c.decodeIfPresent(Double.self, forKey: .processPeakMB) ?? 0
        memoryWarnings = try c.decodeIfPresent(Int.self, forKey: .memoryWarnings) ?? 0
        showing = try c.decodeIfPresent(Bool.self, forKey: .showing) ?? false
        endedWhileShowing = try c.decodeIfPresent(Int.self, forKey: .endedWhileShowing) ?? 0
        lastEndedWhileShowing = try c.decodeIfPresent(Date.self, forKey: .lastEndedWhileShowing)
    }

    /// The extension's process started. Returns whether the one before it was ended
    /// while the keyboard was showing (a crash or iOS's memory limit), which is counted.
    @discardableResult
    public mutating func loaded(at date: Date) -> Bool {
        let wasShowing = showing
        if wasShowing {
            endedWhileShowing += 1
            lastEndedWhileShowing = date
        }
        loadedAt = date
        shows = 0
        processPeakMB = 0
        showing = false
        return wasShowing
    }

    /// The keyboard came on screen: a new session's peak and warnings.
    public mutating func shown(at date: Date, reading: MemoryReading?) {
        shows += 1
        shownAt = date
        showing = true
        memoryWarnings = 0
        peakMB = 0
        lowestHeadroomMB = 0
        if let reading { take(reading, at: date) }
    }

    /// A new reading while the keyboard is up. Returns whether it is worth writing:
    /// memory moved by `step` MB since the last write, or `interval` seconds went by.
    @discardableResult
    public mutating func sample(_ reading: MemoryReading, at date: Date, step: Double = 0.5,
                                interval: TimeInterval = 5) -> Bool {
        let moved = last.map { abs(reading.footprintMB - $0.footprintMB) >= step } ?? true
        let stale = updated.map { date.timeIntervalSince($0) >= interval } ?? true
        guard moved || stale else {
            note(reading) // Peaks still count between writes.
            return false
        }
        take(reading, at: date)
        return true
    }

    /// iOS warned the keyboard about memory.
    public mutating func memoryWarning(at date: Date, reading: MemoryReading?) {
        memoryWarnings += 1
        if let reading { take(reading, at: date) }
    }

    /// The keyboard went away normally.
    public mutating func hidden(at date: Date, reading: MemoryReading?) {
        if let reading { take(reading, at: date) }
        showing = false
    }

    private mutating func take(_ reading: MemoryReading, at date: Date) {
        last = reading
        updated = date
        note(reading)
    }

    private mutating func note(_ reading: MemoryReading) {
        peakMB = max(peakMB, reading.footprintMB)
        processPeakMB = max(processPeakMB, reading.footprintMB)
        if reading.headroomMB > 0 {
            lowestHeadroomMB = lowestHeadroomMB > 0 ? min(lowestHeadroomMB, reading.headroomMB) : reading.headroomMB
        }
    }
}

/// The keyboard's debug readings as a file in the App Group: the extension writes, the
/// app reads.
public struct FileKeyboardDebugStore: Sendable {
    private let file: JSONFile<KeyboardDebug>

    public init(url: URL) {
        file = JSONFile(url)
    }

    public func load() -> KeyboardDebug? { file.read() }
    public func save(_ debug: KeyboardDebug) { file.write(debug) }
}
