import Foundation

/// The two-week Pro trial that starts on first launch (PRODUCT.md §6). `ProStatus.from`
/// turns it and the App Store's answer into what the person may use (`Entitlement`).
public struct Trial: Codable, Sendable, Equatable {
    public static let days = 14

    public var start: Date

    public init(start: Date) { self.start = start }

    public var end: Date { start.addingTimeInterval(TimeInterval(Self.days) * 86_400) }

    /// Whole days left, rounded up, never below zero: 14 on the first day, 1 on the last.
    public func daysLeft(now: Date) -> Int {
        max(0, Int((end.timeIntervalSince(now) / 86_400).rounded(.up)))
    }

    public func isOver(now: Date) -> Bool { now >= end }
}
