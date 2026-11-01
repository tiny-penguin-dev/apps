import Foundation
import Observation
import StackWriteCore

/// The app's state and the only thing its views talk to (docs/building.md §4): which
/// screen is up, how far setup got, whether the keyboard is on, the settings the
/// practice field types with, and the counts that go to telemetry.
@MainActor
@Observable
final class AppModel {
    enum Screen: Equatable {
        case hello, turnOn, sync, tryIt, home
    }

    private(set) var screen: Screen
    private(set) var state: AppState {
        didSet { environment.appStateStore.save(state) }
    }
    /// Whether the StackWrite keyboard is turned on in Settings, as last read.
    private(set) var isKeyboardOn = false
    /// Set once, the moment the keyboard is first seen on: the Turn on screen throws confetti.
    private(set) var celebrateKeyboardOn = false
    /// The keyboard settings the app's practice field uses, saved on every change.
    var keyboardSettings: KeyboardSettings {
        didSet {
            guard keyboardSettings != oldValue else { return }
            environment.settingsStore.save(keyboardSettings)
        }
    }

    @ObservationIgnored private let environment: AppEnvironment

    init(environment: AppEnvironment) {
        self.environment = environment
        var state = environment.appStateStore.load() ?? AppState()
        if state.firstLaunch == nil { state.firstLaunch = environment.now() }
        // The v1 app kept its own flag; people who finished that setup skip this one.
        if !state.onboardingDone, UserDefaults.standard.bool(forKey: "onboarding.done") { state.onboardingDone = true }
        self.state = state
        self.screen = state.onboardingDone ? .home : .hello
        self.keyboardSettings = environment.settingsStore.load() ?? KeyboardSettings()
        environment.appStateStore.save(state)
        refreshKeyboardStatus()
    }

    var now: Date { environment.now() }

    var trial: Trial { Trial(start: state.firstLaunch ?? now) }

    var week: Week { Week(practiceDays: state.practiceDays, now: now) }

    /// The Full Access screen was answered already (its ghost button says Next, not Skip).
    var fullAccessAsked: Bool { state.fullAccessAsked }

    // MARK: Keyboard status

    /// Re-reads whether the keyboard is on; counts `setup.keyboard_on` the first time it is.
    func refreshKeyboardStatus() {
        let on = environment.keyboardStatus.isKeyboardOn()
        guard on != isKeyboardOn || (on && !state.keyboardOnSeen) else { return }
        isKeyboardOn = on
        if on, !state.keyboardOnSeen {
            state.keyboardOnSeen = true
            celebrateKeyboardOn = true
            environment.metrics.count("setup.keyboard_on")
        }
    }

    func openSettings() {
        environment.openSettings()
    }

    // MARK: Setup

    /// The next setup screen, from Hello through to Home.
    func next() {
        switch screen {
        case .hello: screen = .turnOn
        case .turnOn: screen = .sync
        case .sync: screen = .tryIt
        case .tryIt: finishOnboarding()
        case .home: break
        }
    }

    /// Open Settings from the Full Access screen; counted once as `setup.full_access`.
    func openSettingsForFullAccess() {
        answerFullAccess("opened")
        environment.openSettings()
    }

    func skipFullAccess() {
        answerFullAccess("skipped")
        if screen == .sync { screen = .tryIt }
    }

    private func answerFullAccess(_ answer: String) {
        guard !state.fullAccessAsked else { return }
        state.fullAccessAsked = true
        environment.metrics.count("setup.full_access", ["answer": answer])
    }

    /// Home reached: setup never shows again; the time it took is counted once.
    func finishOnboarding() {
        if !state.onboardingDone {
            state.onboardingDone = true
            if let first = state.firstLaunch {
                environment.metrics.duration("onboarding.finished", seconds: now.timeIntervalSince(first))
            }
        }
        screen = .home
    }

    // MARK: Practice

    /// A word typed in the app: ticks today on the week.
    func recordPractice() {
        state.recordPractice(at: now)
    }
}
