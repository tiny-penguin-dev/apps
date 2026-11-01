import SquawkKit

/// What the app needs from the system alarm service. The real one is AlarmKit
/// (`AlarmKitScheduler`); previews use `PreviewScheduler`.
@MainActor
protocol RingScheduler: AnyObject {
    var access: AlarmAccess { get }
    /// Shows the iOS "allow alarms" prompt if it hasn't been answered yet.
    func requestAccess() async -> Bool
    /// Replaces every scheduled ring with this plan. Returns how many failed.
    func replaceAll(with plan: [PlannedRing]) async -> Int
}

enum AlarmAccess: Equatable {
    case notAsked, allowed, denied
}

/// Does nothing, for previews.
@MainActor
final class PreviewScheduler: RingScheduler {
    var access: AlarmAccess = .allowed
    func requestAccess() async -> Bool { true }
    func replaceAll(with plan: [PlannedRing]) async -> Int { 0 }
}
