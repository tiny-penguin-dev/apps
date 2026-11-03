import Foundation
import Observation
import SquawkKit

/// The morning summary on Good morning: which halves are on, asking for the permissions,
/// and loading today's weather and first event (features/morning-summary/FEATURE.md).
/// A Pro feature; losing Pro hides the card but keeps the settings.
@MainActor
@Observable
final class MorningSummaryModel {
    private(set) var settings: SummarySettings
    /// Today's weather, once loaded. Nil when off, not allowed, or it didn't load in time.
    private(set) var weather: SummaryWeather?
    /// Today's first event, once loaded. Nil when off or not allowed.
    private(set) var agenda: Agenda?
    /// Whether iOS lets Squawk use each source, refreshed with `refreshAccess()`.
    private(set) var weatherAccess: SourceAccess = .notAsked
    private(set) var calendarAccess: SourceAccess = .notAsked
    /// True while the offer card is asking for permissions.
    private(set) var turningOn = false

    private let weatherSource: any WeatherSource
    private let agendaSource: any AgendaSource
    private let defaults: UserDefaults?
    @ObservationIgnored private var offerCountedOn: LocalDate?

    /// A slow weather request is dropped after this long, so Good morning never waits.
    static let weatherTimeout = 6.0
    private static let key = "summary.settings"

    init(weather: any WeatherSource, agenda: any AgendaSource, defaults: UserDefaults? = .standard) {
        self.weatherSource = weather
        self.agendaSource = agenda
        self.defaults = defaults
        settings = defaults?.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode(SummarySettings.self, from: $0) } ?? SummarySettings()
        refreshAccess()
    }

    /// The app's one summary model, on WeatherKit and EventKit.
    static let shared = MorningSummaryModel(weather: LiveWeatherSource(), agenda: LiveAgendaSource())

    static func preview(
        _ settings: SummarySettings = SummarySettings(weather: true, calendar: true),
        events: [AgendaEvent] = MorningSummaryModel.previewEvents
    ) -> MorningSummaryModel {
        let model = MorningSummaryModel(weather: FakeWeatherSource(), agenda: FakeAgendaSource(events: events), defaults: nil)
        model.settings = settings
        return model
    }

    static var previewEvents: [AgendaEvent] {
        let start = Calendar.current.date(bySettingHour: 9, minute: 30, second: 0, of: Date()) ?? Date()
        return [
            AgendaEvent(title: "Standup", start: start, end: start.addingTimeInterval(900)),
            AgendaEvent(title: "Lunch with Sam", start: start.addingTimeInterval(3 * 3600), end: start.addingTimeInterval(4 * 3600)),
        ]
    }

    /// True when the Today card has something to show.
    var hasSomething: Bool { weather != nil || agenda != nil }

    // MARK: Loading

    /// Loads today's weather and first event, each half as soon as it's ready. Does
    /// nothing without Pro or with both halves off.
    func load(access: ProAccess) async {
        refreshAccess()
        guard access.allows(.summary), settings.isOn else {
            weather = nil
            agenda = nil
            return
        }
        await withDiscardingTaskGroup { group in
            group.addTask { await self.loadWeather() }
            group.addTask { await self.loadAgenda() }
        }
        Telemetry.count("summary.shown", [
            "weather": weather == nil ? "no" : "yes",
            "event": agenda.map { $0 == .empty ? "none" : "yes" } ?? "off",
        ])
    }

    private func loadWeather() async {
        guard settings.weather, weatherAccess == .allowed else {
            weather = nil
            return
        }
        let source = weatherSource
        do {
            weather = try await withTimeout(seconds: Self.weatherTimeout) { try await source.today() }
        } catch {
            weather = nil
            Telemetry.count("summary.weather_failed", ["reason": error is TimedOut ? "timeout" : "error"])
            if !(error is TimedOut) { Telemetry.report(error) }
        }
    }

    private func loadAgenda() async {
        guard settings.calendar, calendarAccess == .allowed else {
            agenda = nil
            return
        }
        let events = (try? await agendaSource.today()) ?? []
        agenda = Agenda(events: events, now: Date())
    }

    /// Reads whether iOS still allows each source (it can change in iOS Settings).
    func refreshAccess() {
        weatherAccess = weatherSource.access
        calendarAccess = agendaSource.access
    }

    // MARK: Offer

    /// Counts a morning the offer card showed, once a day.
    func countOffer() {
        let today = LocalDate(Date())
        guard settings.shouldOffer, offerCountedOn != today else { return }
        offerCountedOn = today
        settings.offersShown += 1
        save()
    }

    /// "Not now" on the offer card: it doesn't come back.
    func dismissOffer() {
        settings.offerDismissed = true
        save()
        Telemetry.count("summary.declined", ["part": "offer"])
    }

    /// "Turn it on" on the offer card: asks for location, then the calendar, turns on
    /// whichever is allowed, and loads.
    func turnOn(access: ProAccess) async {
        turningOn = true
        defer { turningOn = false }
        _ = await setWeather(true)
        _ = await setCalendar(true)
        if !settings.isOn {
            settings.offerDismissed = true
            save()
        }
        await load(access: access)
    }

    // MARK: Switches

    /// Turns the weather half on (asking for location the first time) or off. Returns
    /// whether it's on afterwards.
    @discardableResult
    func setWeather(_ on: Bool) async -> Bool {
        var allowed = false
        if on { allowed = await weatherSource.requestAccess() }
        refreshAccess()
        settings.weather = allowed
        save()
        if on { Telemetry.count(allowed ? "summary.enabled" : "summary.declined", ["part": "weather"]) }
        if !allowed { weather = nil }
        return allowed
    }

    /// Turns the calendar half on (asking for the calendar the first time) or off.
    /// Returns whether it's on afterwards.
    @discardableResult
    func setCalendar(_ on: Bool) async -> Bool {
        var allowed = false
        if on { allowed = await agendaSource.requestAccess() }
        refreshAccess()
        settings.calendar = allowed
        save()
        if on { Telemetry.count(allowed ? "summary.enabled" : "summary.declined", ["part": "calendar"]) }
        if !allowed { agenda = nil }
        return allowed
    }

    private func save() {
        guard let defaults, let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
