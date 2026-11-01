import Foundation

/// One AlarmKit alarm to schedule. The app maps these straight onto AlarmKit.
public struct PlannedRing: Hashable, Sendable {
    public enum Schedule: Hashable, Sendable {
        /// Repeats every week on these days at this time.
        case weekly(TimeOfDay, [Weekday])
        /// Rings once.
        case once(Date)
    }

    /// Stable for the same alarm, ring and day group, so re-planning gives the same ids.
    public let id: UUID
    public let alarmID: UUID
    public let ringID: UUID
    public let schedule: Schedule
    public let title: String
    public let sound: AlarmSound
    public let color: RingColor
    /// True for the alarm's last ring (where wake-up checks will hang off later).
    public let isLastRing: Bool
}

/// Turns saved alarms into the AlarmKit alarms to schedule. This is the one place that
/// decides what rings when (PRODUCT.md 8b), so every feature uses the same path.
public enum AlarmPlanner {
    public static func plan(_ alarms: [Alarm], now: Date, calendar: Calendar = .current) -> [PlannedRing] {
        alarms.filter(\.isOn).flatMap { plan($0, now: now, calendar: calendar) }
    }

    public static func plan(_ alarm: Alarm, now: Date, calendar: Calendar = .current) -> [PlannedRing] {
        let rings = alarm.rings.sorted { $0.offsetMinutes < $1.offsetMinutes }
        let lastID = rings.last?.id
        var result: [PlannedRing] = []

        if let date = alarm.date {
            guard let wake = date.date(at: alarm.time, calendar: calendar) else { return [] }
            for ring in rings {
                let fire = wake.addingTimeInterval(Double(ring.offsetMinutes) * 60)
                guard fire > now else { continue }
                result.append(PlannedRing(
                    id: StableID.make("\(alarm.id)|\(ring.id)|once"),
                    alarmID: alarm.id, ringID: ring.id, schedule: .once(fire),
                    title: alarm.title, sound: ring.sound, color: ring.color, isLastRing: ring.id == lastID
                ))
            }
            return result
        }

        // Each group of days with the same time becomes one weekly alarm per ring.
        for group in alarm.timeGroups {
            for ring in rings {
                let shifted = group.time.minutesAfterMidnight + ring.offsetMinutes
                let dayShift = Int((Double(shifted) / 1440).rounded(.down))
                let time = group.time.adding(minutes: ring.offsetMinutes)
                let days = group.days.map { shift($0, by: dayShift) }.sorted()
                result.append(PlannedRing(
                    id: StableID.make("\(alarm.id)|\(ring.id)|\(group.days.map(\.rawValue))"),
                    alarmID: alarm.id, ringID: ring.id, schedule: .weekly(time, days),
                    title: alarm.title, sound: ring.sound, color: ring.color, isLastRing: ring.id == lastID
                ))
            }
        }
        return result
    }

    static func shift(_ day: Weekday, by delta: Int) -> Weekday {
        let index = ((day.rawValue - 1 + delta) % 7 + 7) % 7
        return Weekday(rawValue: index + 1)!
    }
}

/// Deterministic UUIDs from strings (two FNV-1a hashes), so the same input always
/// gives the same id without needing CryptoKit.
enum StableID {
    static func make(_ string: String) -> UUID {
        let a = fnv(string, seed: 0xcbf29ce484222325)
        let b = fnv(string, seed: 0x84222325cbf29ce4)
        var bytes = [UInt8](repeating: 0, count: 16)
        for i in 0..<8 {
            bytes[i] = UInt8((a >> (8 * UInt64(i))) & 0xFF)
            bytes[i + 8] = UInt8((b >> (8 * UInt64(i))) & 0xFF)
        }
        bytes[6] = (bytes[6] & 0x0F) | 0x50 // version 5 style
        bytes[8] = (bytes[8] & 0x3F) | 0x80 // RFC 4122 variant
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    private static func fnv(_ string: String, seed: UInt64) -> UInt64 {
        var hash = seed
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }
}
