import Foundation

/// Whether the Astrotype keyboard is turned on in Settings, read from the list of
/// keyboards iOS keeps in the app's defaults (`AppleKeyboards`), which names a third
/// party keyboard by its extension's bundle identifier. The Turn on screen's chip
/// flips to "On" from this, and Home's banner goes away.
public protocol KeyboardStatusReading: Sendable {
    func isKeyboardOn() -> Bool
}

public enum KeyboardStatus {
    public static let extensionBundleID = "com.tinypenguin.astrotype.keyboard"

    /// Whether `keyboards` (the `AppleKeyboards` list) has the Astrotype keyboard.
    public static func isOn(keyboards: [String], bundleID: String = extensionBundleID) -> Bool {
        keyboards.contains { $0 == bundleID || $0.hasPrefix(bundleID + "@") }
    }
}

public struct UserDefaultsKeyboardStatus: KeyboardStatusReading {
    public init() {}

    public func isKeyboardOn() -> Bool {
        let keyboards = UserDefaults.standard.array(forKey: "AppleKeyboards") as? [String] ?? []
        return KeyboardStatus.isOn(keyboards: keyboards)
    }
}

/// A status the tests set by hand.
public final class FakeKeyboardStatus: KeyboardStatusReading, @unchecked Sendable {
    private let lock = NSLock()
    private var on: Bool

    public init(on: Bool = false) { self.on = on }

    public var isOn: Bool {
        get { lock.lock(); defer { lock.unlock() }; return on }
        set { lock.lock(); defer { lock.unlock() }; on = newValue }
    }

    public func isKeyboardOn() -> Bool { isOn }
}
