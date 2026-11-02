import AlarmKit
import AppIntents
import SquawkKit
import SwiftUI

/// Context carried with each AlarmKit alarm. AlarmKit needs it Codable, Hashable and Sendable.
struct SquawkAlarmMetadata: AlarmMetadata {
    var alarmID: String
    var ringID: String
    var isLastRing: Bool
}

/// Turns Squawk's plan into AlarmKit alarms. AlarmKit owns the ringing: full screen on
/// the lock screen, through silent mode and Focus. Nothing else in the app talks to it.
@MainActor
final class AlarmKitScheduler: RingScheduler {
    static let shared = AlarmKitScheduler()

    // AlarmManager is a process-wide singleton that AlarmKit leaves non-Sendable, but
    // it is safe to use from any thread.
    nonisolated(unsafe) private let manager = AlarmManager.shared

    private init() {}

    var access: AlarmAccess {
        switch manager.authorizationState {
        case .authorized: .allowed
        case .denied: .denied
        case .notDetermined: .notAsked
        @unknown default: .notAsked
        }
    }

    func requestAccess() async -> Bool {
        if manager.authorizationState == .authorized { return true }
        do {
            return try await manager.requestAuthorization() == .authorized
        } catch {
            Telemetry.report(error)
            return false
        }
    }

    /// Only touches what changed: alarms no longer planned (or planned differently) are
    /// cancelled, and new ones are scheduled soonest first. Everything else stays as it
    /// is, so a re-plan never leaves a gap with nothing scheduled, and a ring that's
    /// going off isn't cancelled just because something else changed.
    func replaceAll(with plan: [PlannedRing]) async -> Int {
        guard manager.authorizationState == .authorized else { return 0 }
        let wanted = Dictionary(plan.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let existing = Set(((try? manager.alarms) ?? []).map(\.id))
        var made = loadScheduled().filter { existing.contains($0.key) }

        for id in existing {
            if let ring = wanted[id], made[id] == Self.fingerprint(ring) { continue }
            try? manager.cancel(id: id)
            made[id] = nil
        }

        let now = Date()
        let missing = wanted.values
            .filter { made[$0.id] == nil }
            .sorted { ($0.nextFire(after: now) ?? .distantFuture) < ($1.nextFire(after: now) ?? .distantFuture) }
        var failures = 0
        for ring in missing {
            if await schedule(ring) {
                made[ring.id] = Self.fingerprint(ring)
            } else {
                failures += 1
            }
        }
        saveScheduled(made)
        return failures
    }

    // MARK: What's scheduled

    /// What each scheduled AlarmKit alarm was made from, so a re-plan can tell what
    /// changed. Kept on disk because snoozes re-plan from a fresh background launch.
    private static let scheduledKey = "alarmkit.scheduled"

    private static func fingerprint(_ ring: PlannedRing) -> String {
        "\(ring.schedule)|\(ring.title)|\(ring.sound.fileName)|\(ring.color.hex)|\(ring.alarmID)|\(ring.isLastRing)|\(ring.needsCheck)"
    }

    private func loadScheduled() -> [UUID: String] {
        let stored = UserDefaults.standard.dictionary(forKey: Self.scheduledKey) as? [String: String] ?? [:]
        return Dictionary(stored.compactMap { key, value in UUID(uuidString: key).map { ($0, value) } },
                          uniquingKeysWith: { a, _ in a })
    }

    private func saveScheduled(_ made: [UUID: String]) {
        UserDefaults.standard.set(Dictionary(uniqueKeysWithValues: made.map { ($0.key.uuidString, $0.value) }),
                                  forKey: Self.scheduledKey)
    }

    /// Builds the AlarmKit configuration off the main actor, so the non-Sendable
    /// configuration never crosses actors.
    private nonisolated func schedule(_ ring: PlannedRing) async -> Bool {
        // With a wake-up check, Stop only quiets this ring (the next one comes in 30 s),
        // so it's honestly labeled "Snooze". The check itself happens in the app.
        let stopButton = ring.needsCheck
            ? AlarmButton(text: "Snooze", textColor: .white, systemImageName: "zzz")
            : AlarmButton(text: "Stop", textColor: .white, systemImageName: "stop.fill")
        // A second button makes iOS show tap buttons instead of "slide to stop".
        let upButton = ring.needsCheck
            ? AlarmButton(text: "I'm up", textColor: .white, systemImageName: "checkmark.circle.fill")
            : AlarmButton(text: "I'm up", textColor: .white, systemImageName: "sun.max.fill")
        let alert = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: ring.title),
            stopButton: stopButton,
            secondaryButton: upButton,
            secondaryButtonBehavior: .custom
        )
        let metadata = SquawkAlarmMetadata(
            alarmID: ring.alarmID.uuidString, ringID: ring.ringID.uuidString, isLastRing: ring.isLastRing
        )
        let attributes = AlarmAttributes(
            presentation: AlarmPresentation(alert: alert),
            metadata: metadata,
            tintColor: Color(hex: ring.color.hex)
        )
        let id = ring.alarmID.uuidString
        let configuration = ring.needsCheck
            ? AlarmManager.AlarmConfiguration.alarm(
                schedule: Self.schedule(for: ring.schedule),
                attributes: attributes,
                stopIntent: SquawkStopIntent(alarmID: id),
                secondaryIntent: SquawkOpenCheckIntent(alarmID: id),
                sound: .named(ring.sound.fileName)
            )
            : AlarmManager.AlarmConfiguration.alarm(
                schedule: Self.schedule(for: ring.schedule),
                attributes: attributes,
                stopIntent: SquawkStopIntent(alarmID: id),
                secondaryIntent: SquawkUpIntent(alarmID: id),
                sound: .named(ring.sound.fileName)
            )
        do {
            _ = try await manager.schedule(id: ring.id, configuration: configuration)
            return true
        } catch {
            Telemetry.report(error)
            return false
        }
    }

    private nonisolated static func schedule(for schedule: PlannedRing.Schedule) -> AlarmKit.Alarm.Schedule {
        switch schedule {
        case .once(let date):
            return .fixed(date)
        case .weekly(let time, let days):
            return .relative(AlarmKit.Alarm.Schedule.Relative(
                time: AlarmKit.Alarm.Schedule.Relative.Time(hour: time.hour, minute: time.minute),
                repeats: .weekly(days.map(\.localeWeekday))
            ))
        }
    }
}

private extension Weekday {
    var localeWeekday: Locale.Weekday {
        switch self {
        case .monday: .monday
        case .tuesday: .tuesday
        case .wednesday: .wednesday
        case .thursday: .thursday
        case .friday: .friday
        case .saturday: .saturday
        case .sunday: .sunday
        }
    }
}

/// Runs when a ring's Stop (or, with a wake-up check, Snooze) is tapped. AlarmKit stops
/// the ring itself, and the next ring still comes.
struct SquawkStopIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop Squawk alarm"
    static let description = IntentDescription("Stops a ringing Squawk alarm.")

    @Parameter(title: "Alarm ID")
    var alarmID: String

    init() {}

    init(alarmID: String) {
        self.alarmID = alarmID
    }

    func perform() async throws -> some IntentResult {
        // With a wake-up check this was a Snooze: re-plan so the next repeats are there.
        await AlarmsModel.shared.ringStopped(alarmID: alarmID)
        return .result()
    }
}

/// Runs when "I'm up" is tapped: stops this ring and cancels the rest of the morning.
struct SquawkUpIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "I'm up"
    static let description = IntentDescription("Stops a Squawk alarm and cancels the rest of this morning's rings.")

    @Parameter(title: "Alarm ID")
    var alarmID: String

    init() {}

    init(alarmID: String) {
        self.alarmID = alarmID
    }

    func perform() async throws -> some IntentResult {
        await AlarmsModel.shared.imUp(alarmID: alarmID)
        return .result()
    }
}

/// "I'm up" on an alarm with a wake-up check: opens Squawk to the check screen.
struct SquawkOpenCheckIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Open wake-up check"
    static let description = IntentDescription("Opens Squawk to turn off the alarm with its wake-up check.")
    static let openAppWhenRun = true

    @Parameter(title: "Alarm ID")
    var alarmID: String

    init() {}

    init(alarmID: String) {
        self.alarmID = alarmID
    }

    func perform() async throws -> some IntentResult {
        // The app shows the check when it comes to the front (AlarmsModel.refresh).
        .result()
    }
}
