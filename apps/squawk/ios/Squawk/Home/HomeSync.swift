import Foundation
@preconcurrency import HomeKit
import SquawkKit

/// The only code that writes to HomeKit. Turns planned Home steps into automations the
/// Home hub runs (an action set plus a trigger, named like "Squawk · Wake up · 6:30"),
/// and runs "When you're up" straight from the phone.
///
/// It remembers which automations it made. Each sync removes the ones that are no longer
/// planned or have changed, and adds the missing ones, so editing an alarm updates its
/// automations, deleting it removes them, and one changed in the Home app comes back.
@MainActor
final class HomeSync {
    /// What Squawk made for one planned step.
    private struct Made: Codable {
        var fingerprint: String
        var trigger: UUID
        var actionSet: UUID?
    }

    private static let madeKey = "home.automations"
    private var syncing = false
    private var again = false

    /// Makes the home's automations match the plan.
    func sync(_ plan: [PlannedHomeStep], in home: HMHome) async {
        if syncing { again = true; return }
        syncing = true
        defer { syncing = false }
        repeat {
            again = false
            await syncOnce(plan, in: home)
        } while again
    }

    private func syncOnce(_ plan: [PlannedHomeStep], in home: HMHome) async {
        var made = load()
        let wanted = Dictionary(plan.map { ($0.id.uuidString, $0) }, uniquingKeysWith: { a, _ in a })

        // Remove what's no longer planned, has changed, or was deleted in the Home app.
        for (id, record) in made {
            let trigger = home.triggers.first { $0.uniqueIdentifier == record.trigger }
            if let step = wanted[id], step.fingerprint == record.fingerprint, trigger != nil { continue }
            await remove(trigger: trigger, actionSet: record.actionSet, from: home)
            made[id] = nil
        }
        // Anything else named like Squawk's that it no longer knows about.
        let known = Set(made.values.map(\.trigger))
        for trigger in home.triggers where trigger.name.hasPrefix(HomePlanner.namePrefix) && !known.contains(trigger.uniqueIdentifier) {
            await remove(trigger: trigger, actionSet: nil, from: home)
        }
        let knownSets = Set(made.values.compactMap(\.actionSet))
        for set in home.actionSets where set.name.hasPrefix(HomePlanner.namePrefix) && !knownSets.contains(set.uniqueIdentifier) {
            try? await home.removeActionSet(set)
        }

        // Add what's missing.
        for step in plan where made[step.id.uuidString] == nil {
            do {
                made[step.id.uuidString] = try await add(step, to: home)
            } catch {
                Telemetry.count("home.sync_failed", ["reason": reason(error)])
                Telemetry.report(error)
            }
            save(made)
        }
        save(made)
    }

    private func remove(trigger: HMTrigger?, actionSet: UUID?, from home: HMHome) async {
        var sets = trigger?.actionSets.filter { $0.name.hasPrefix(HomePlanner.namePrefix) } ?? []
        if let actionSet, let set = home.actionSets.first(where: { $0.uniqueIdentifier == actionSet }), !sets.contains(set) {
            sets.append(set)
        }
        if let trigger { try? await home.removeTrigger(trigger) }
        for set in sets { try? await home.removeActionSet(set) }
    }

    private func add(_ step: PlannedHomeStep, to home: HMHome) async throws -> Made {
        let name = uniqueName(step.name, in: home)
        // Scenes from the Home app run as they are; everything else goes in one action set.
        let scenes = step.actions.filter { $0.kind == .scene }.flatMap(\.targets).compactMap { target in
            home.actionSets.first { $0.uniqueIdentifier == target.id }
        }
        let writes = step.actions.filter { $0.kind != .scene }.flatMap { Self.writes(for: $0, in: home) }

        var ownSet: HMActionSet?
        if !writes.isEmpty {
            let set = try await home.addActionSet(withName: name)
            ownSet = set
            for write in writes {
                try await set.addAction(write)
            }
        }
        let sets = (ownSet.map { [$0] } ?? []) + scenes
        guard !sets.isEmpty else { throw HomeSyncError.nothingToRun }

        let trigger: HMTrigger
        switch step.schedule {
        case .once(let date):
            trigger = HMTimerTrigger(name: name, fireDate: date, recurrence: nil)
        case .weekly(let time, let days):
            trigger = HMEventTrigger(
                name: name,
                events: [HMCalendarEvent(fire: DateComponents(hour: time.hour, minute: time.minute))],
                end: nil,
                recurrences: days.map { DateComponents(weekday: $0.calendarWeekday) },
                predicate: nil
            )
        }
        do {
            try await home.addTrigger(trigger)
            for set in sets { try await trigger.addActionSet(set) }
            try await trigger.enable(true)
        } catch {
            if let ownSet { try? await home.removeActionSet(ownSet) }
            if home.triggers.contains(trigger) { try? await home.removeTrigger(trigger) }
            throw error
        }
        return Made(fingerprint: step.fingerprint, trigger: trigger.uniqueIdentifier, actionSet: ownSet?.uniqueIdentifier)
    }

    // MARK: When you're up

    /// Runs "When you're up" now, from the phone.
    func run(_ actions: [HomeAction], in home: HMHome) async {
        for action in actions {
            do {
                if action.kind == .scene {
                    for target in action.targets {
                        if let set = home.actionSets.first(where: { $0.uniqueIdentifier == target.id }) {
                            try await home.executeActionSet(set)
                        }
                    }
                } else {
                    for write in Self.writes(for: action, in: home) {
                        try await write.characteristic.writeValue(write.targetValue)
                    }
                }
            } catch {
                Telemetry.count("home.run_failed", ["reason": reason(error)])
            }
        }
        if !actions.isEmpty { Telemetry.count("morning.up_actions", ["count": String(min(actions.count, 9))]) }
    }

    // MARK: Building actions

    /// The characteristic writes that set one Home thing, for every service it targets
    /// that's still in the home.
    static func writes(for action: HomeAction, in home: HMHome) -> [HMCharacteristicWriteAction<NSNumber>] {
        let services = home.accessories.flatMap(\.services)
        var result: [HMCharacteristicWriteAction<NSNumber>] = []
        for target in action.targets {
            guard let service = services.first(where: { $0.uniqueIdentifier == target.id }) else { continue }
            func write(_ type: String, _ value: NSNumber) {
                guard let characteristic = service.characteristics.first(where: { $0.characteristicType == type }) else { return }
                result.append(HMCharacteristicWriteAction(characteristic: characteristic, targetValue: value))
            }
            let setting = action.setting
            switch action.kind {
            case .light:
                write(HMCharacteristicTypePowerState, NSNumber(value: setting.isOn))
                guard setting.isOn else { break }
                if let brightness = setting.brightness {
                    write(HMCharacteristicTypeBrightness, NSNumber(value: min(max(brightness, 1), 100)))
                }
                if let warmth = setting.warmth,
                   let color = service.characteristics.first(where: { $0.characteristicType == HMCharacteristicTypeColorTemperature }) {
                    write(HMCharacteristicTypeColorTemperature, NSNumber(value: mireds(warmth: warmth, metadata: color.metadata)))
                }
            case .plug:
                write(HMCharacteristicTypePowerState, NSNumber(value: setting.isOn))
            case .blinds:
                write(HMCharacteristicTypeTargetPosition, NSNumber(value: min(max(setting.position ?? 100, 0), 100)))
            case .scene:
                break
            }
        }
        return result
    }

    /// Warmth (0 warm, 100 daylight) as a color temperature in mireds, within what the
    /// light supports. Higher mireds are warmer.
    static func mireds(warmth: Int, metadata: HMCharacteristicMetadata?) -> Int {
        let warmest = metadata?.maximumValue?.intValue ?? 454
        let coolest = metadata?.minimumValue?.intValue ?? 153
        let t = Double(min(max(warmth, 0), 100)) / 100
        return Int((Double(warmest) - t * Double(warmest - coolest)).rounded())
    }

    /// HomeKit wants each automation's name to be unique in the home.
    private func uniqueName(_ name: String, in home: HMHome) -> String {
        let taken = Set(home.triggers.map(\.name) + home.actionSets.map(\.name))
        var candidate = name
        var n = 2
        while taken.contains(candidate) {
            candidate = "\(name) (\(n))"
            n += 1
        }
        return candidate
    }

    private func reason(_ error: Error) -> String {
        if let error = error as? HMError { return "hm\(error.code.rawValue)" }
        if error is HomeSyncError { return "nothing" }
        return "other"
    }

    // MARK: Memory

    private func load() -> [String: Made] {
        guard let data = UserDefaults.standard.data(forKey: Self.madeKey),
              let made = try? JSONDecoder().decode([String: Made].self, from: data) else { return [:] }
        return made
    }

    private func save(_ made: [String: Made]) {
        if let data = try? JSONEncoder().encode(made) {
            UserDefaults.standard.set(data, forKey: Self.madeKey)
        }
    }
}

enum HomeSyncError: Error {
    /// The step's lights or scenes are no longer in the home.
    case nothingToRun
}
