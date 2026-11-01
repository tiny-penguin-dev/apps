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

    func replaceAll(with plan: [PlannedRing]) async -> Int {
        guard manager.authorizationState == .authorized else { return 0 }
        for alarm in (try? manager.alarms) ?? [] {
            try? manager.cancel(id: alarm.id)
        }
        var failures = 0
        for ring in plan {
            let scheduled = await schedule(ring)
            if !scheduled { failures += 1 }
        }
        return failures
    }

    /// Builds the AlarmKit configuration off the main actor, so the non-Sendable
    /// configuration never crosses actors.
    private nonisolated func schedule(_ ring: PlannedRing) async -> Bool {
        let stopButton = AlarmButton(text: "Stop", textColor: .white, systemImageName: "stop.fill")
        // A second button makes iOS show tap buttons instead of "slide to stop".
        let upButton = AlarmButton(text: "I'm up", textColor: .white, systemImageName: "sun.max.fill")
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
        let intent = SquawkStopIntent(alarmID: ring.alarmID.uuidString)
        let configuration = AlarmManager.AlarmConfiguration.alarm(
            schedule: Self.schedule(for: ring.schedule),
            attributes: attributes,
            stopIntent: intent,
            secondaryIntent: SquawkStopIntent(alarmID: ring.alarmID.uuidString),
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

/// Runs when a ring's Stop or "I'm up" is tapped. AlarmKit stops the ring itself;
/// the mornings log and wake-up checks hook in here in later phases.
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
        .result()
    }
}
