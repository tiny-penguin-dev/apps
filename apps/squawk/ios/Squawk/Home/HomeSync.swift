import Foundation
@preconcurrency import HomeKit
import SquawkKit
import UIKit

/// The only code that writes to HomeKit. Turns planned Home steps into automations the
/// Home hub runs (an action set plus a trigger, named like "Squawk · Wake up · 6:30"),
/// and runs "When you're up" straight from the phone.
///
/// It remembers which automations it made. Each sync removes the ones that are no longer
/// planned or have changed, and adds the missing ones, so editing an alarm updates its
/// automations, deleting it removes them, and one changed in the Home app comes back.
///
/// Every action set shows up as a scene in the Home app, so steps that set the same
/// lights, plugs and blinds share one, and an action set goes once nothing needs it.
///
/// HomeKit only takes changes while the app is in the foreground. In the background
/// (a reschedule from "I'm up" or Snooze on the lock screen) it answers "Request not
/// handled", so a sync stops there and says it didn't finish; `HomeAccess` runs it again
/// the next time the app is active.
@MainActor
final class HomeSync {
    /// What Squawk made for one planned step.
    private struct Made: Codable {
        var fingerprint: String
        var trigger: UUID
    }

    /// v2 shares action sets. Starting over with a new key replaces the automations made
    /// with one action set each.
    private static let madeKey = "home.automations.v2"
    /// Squawk's action sets, by what they do (`setKey`).
    private static let setsKey = "home.actionSets"
    private var syncing = false
    /// The newest plan asked for while a sync was running.
    private var next: (plan: [PlannedHomeStep], home: HMHome)?

    /// Makes the home's automations match the plan. A plan asked for during a sync
    /// replaces any older waiting one and runs right after. Returns false when the app
    /// left the foreground before the home matched the plan.
    @discardableResult
    func sync(_ plan: [PlannedHomeStep], in home: HMHome) async -> Bool {
        next = (plan, home)
        if syncing { return true }
        syncing = true
        defer { syncing = false }
        while let job = next {
            next = nil
            guard Self.canWrite, await syncOnce(job.plan, in: job.home) else {
                next = nil
                return false
            }
        }
        return true
    }

    /// HomeKit refuses changes from an app that isn't in the foreground.
    static var canWrite: Bool {
        UIApplication.shared.applicationState == .active
    }

    /// One pass. Returns false if it stopped because the app went to the background.
    private func syncOnce(_ plan: [PlannedHomeStep], in home: HMHome) async -> Bool {
        var made = load()
        var sets = loadSets().filter { _, id in home.actionSets.contains { $0.uniqueIdentifier == id } }
        let wanted = Dictionary(plan.map { ($0.id.uuidString, $0) }, uniquingKeysWith: { a, _ in a })

        // Remove what's no longer planned, has changed, or was deleted in the Home app.
        for (id, record) in made {
            let trigger = home.triggers.first { $0.uniqueIdentifier == record.trigger }
            if let step = wanted[id], step.fingerprint == record.fingerprint, trigger != nil { continue }
            if let trigger { try? await home.removeTrigger(trigger) }
            made[id] = nil
        }
        // Anything else named like Squawk's that it no longer knows about.
        let known = Set(made.values.map(\.trigger))
        for trigger in home.triggers where trigger.name.hasPrefix(HomePlanner.namePrefix) && !known.contains(trigger.uniqueIdentifier) {
            try? await home.removeTrigger(trigger)
        }
        // Action sets no planned step needs, and Squawk's that it no longer knows about.
        let wantedSets = Set(plan.compactMap(Self.setKey))
        sets = sets.filter { wantedSets.contains($0.key) }
        let keptSets = Set(sets.values)
        for set in home.actionSets where set.name.hasPrefix(HomePlanner.namePrefix) && !keptSets.contains(set.uniqueIdentifier) {
            try? await home.removeActionSet(set)
        }
        saveSets(sets)

        // Add what's missing.
        for step in plan where made[step.id.uuidString] == nil {
            guard Self.canWrite else { save(made); return false }
            do {
                made[step.id.uuidString] = try await add(step, to: home, sets: &sets)
            } catch let error where Self.isBackground(error) {
                // Not a real failure: the app left the foreground. The next sync adds it.
                save(made)
                saveSets(sets)
                return false
            } catch {
                Telemetry.count("home.sync_failed", ["reason": reason(error)])
                Telemetry.report(error)
            }
            save(made)
            saveSets(sets)
        }
        save(made)
        saveSets(sets)
        return true
    }

    /// What a step's own action set does, so steps that do the same share one. Nil when
    /// it only runs scenes from the Home app.
    static func setKey(_ step: PlannedHomeStep) -> String? {
        let actions = step.actions.filter { $0.kind != .scene }
        guard !actions.isEmpty else { return nil }
        return actions.map { a in
            "\(a.kind.rawValue)|\(a.targets.map(\.id.uuidString).sorted())|\(a.setting.isOn)|\(a.setting.brightness ?? -1)|\(a.setting.warmth ?? -1)|\(a.setting.position ?? -1)"
        }.sorted().joined(separator: ";")
    }

    private func add(_ step: PlannedHomeStep, to home: HMHome, sets: inout [String: UUID]) async throws -> Made {
        let name = uniqueName(step.name, in: home)
        // Scenes from the Home app run as they are; everything else goes in one action set,
        // shared with other steps that do the same.
        let scenes = step.actions.filter { $0.kind == .scene }.flatMap(\.targets).compactMap { target in
            home.actionSets.first { $0.uniqueIdentifier == target.id }
        }
        let key = Self.setKey(step)
        var ownSet = key.flatMap { sets[$0] }.flatMap { id in home.actionSets.first { $0.uniqueIdentifier == id } }
        var createdSet: HMActionSet?
        let writes = step.actions.filter { $0.kind != .scene }.flatMap { Self.writes(for: $0, in: home) }
        if ownSet == nil, let key, !writes.isEmpty {
            let set = try await home.addActionSet(named: uniqueName(Self.setName(step), in: home))
            createdSet = set
            do {
                for write in writes { try await set.addAction(write) }
            } catch {
                try? await home.removeActionSet(set)
                throw error
            }
            ownSet = set
            sets[key] = set.uniqueIdentifier
        }
        let toRun = (ownSet.map { [$0] } ?? []) + scenes
        guard !toRun.isEmpty else { throw HomeSyncError.nothingToRun }

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
            for set in toRun { try await trigger.addActionSet(set) }
            try await trigger.enable(true)
        } catch {
            if let createdSet, let key {
                try? await home.removeActionSet(createdSet)
                sets[key] = nil
            }
            if home.triggers.contains(trigger) { try? await home.removeTrigger(trigger) }
            throw error
        }
        return Made(fingerprint: step.fingerprint, trigger: trigger.uniqueIdentifier)
    }

    /// A shared action set's name: the step's without its time, "Squawk · Wake up".
    private static func setName(_ step: PlannedHomeStep) -> String {
        var parts = step.name.components(separatedBy: " · ")
        if parts.count > 2 { parts.removeLast() }
        return parts.joined(separator: " · ")
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
            case .scene, .sunrise:
                // Sunrise lights are planned as plain light changes (`Alarm.homeSteps`).
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
        if error is HomeSyncError { return "nothing" }
        if Self.isBackground(error) { return "background" }
        let error = error as NSError
        switch error.domain {
        case HMErrorDomain: return "hm\(error.code)"
        case Self.hmfDomain: return "hmf\(error.code)"
        default: return "other"
        }
    }

    /// HomeKit's internal error domain. Code 2, "Request not handled", is what it
    /// answers when the app isn't in the foreground.
    private static let hmfDomain = "HMFErrorDomain"

    /// True for HomeKit refusing a change because the app isn't in the foreground.
    static func isBackground(_ error: Error) -> Bool {
        let error = error as NSError
        if error.domain == hmfDomain, error.code == 2 { return true }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? Error { return isBackground(underlying) }
        return false
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

    private func loadSets() -> [String: UUID] {
        guard let data = UserDefaults.standard.data(forKey: Self.setsKey),
              let sets = try? JSONDecoder().decode([String: UUID].self, from: data) else { return [:] }
        return sets
    }

    private func saveSets(_ sets: [String: UUID]) {
        if let data = try? JSONEncoder().encode(sets) {
            UserDefaults.standard.set(data, forKey: Self.setsKey)
        }
    }
}

enum HomeSyncError: Error {
    /// The step's lights or scenes are no longer in the home.
    case nothingToRun
}
