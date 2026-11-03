import Foundation

// The morning summary on Good morning: today's weather and the first calendar event
// (features/morning-summary/FEATURE.md). The rules live here; the app reads the weather
// from WeatherKit and the events from EventKit through `WeatherSource` and `AgendaSource`.
//
// ```swift
// let weather = try await withTimeout(seconds: 5) { try await weatherSource.today() }
// let agenda = Agenda(events: try await agendaSource.today(), now: .now)
// settings.shouldOffer   // show "Add the weather and your day"?
// ```

// MARK: Weather

/// Today's weather, as the Today card shows it.
public struct SummaryWeather: Equatable, Sendable {
    /// An SF Symbol for the current conditions, like "cloud.rain.fill".
    public var symbol: String
    /// A short description for VoiceOver, like "Light rain".
    public var condition: String
    /// Temperatures in degrees Celsius. Use `now`, `high` and `low` to show them, so
    /// they follow the phone's units.
    public var nowCelsius: Double
    public var highCelsius: Double
    public var lowCelsius: Double
    /// The one thing worth knowing today, if anything.
    public var note: WeatherNote?
    /// The weather provider's mark and data sources link, which must show with the weather.
    public var credit: WeatherCredit?

    public init(
        symbol: String, condition: String, nowCelsius: Double, highCelsius: Double, lowCelsius: Double,
        note: WeatherNote? = nil, credit: WeatherCredit? = nil
    ) {
        self.symbol = symbol
        self.condition = condition
        self.nowCelsius = nowCelsius
        self.highCelsius = highCelsius
        self.lowCelsius = lowCelsius
        self.note = note
        self.credit = credit
    }

    public var now: Measurement<UnitTemperature> { .init(value: nowCelsius, unit: .celsius) }
    public var high: Measurement<UnitTemperature> { .init(value: highCelsius, unit: .celsius) }
    public var low: Measurement<UnitTemperature> { .init(value: lowCelsius, unit: .celsius) }
}

/// The weather provider's mark (light and dark) and its legal page. Apple's WeatherKit
/// requires both next to the weather.
public struct WeatherCredit: Equatable, Sendable {
    public var lightMark: URL
    public var darkMark: URL
    public var legalPage: URL

    public init(lightMark: URL, darkMark: URL, legalPage: URL) {
        self.lightMark = lightMark
        self.darkMark = darkMark
        self.legalPage = legalPage
    }
}

/// One hour of the forecast: just what `WeatherNote` needs.
public struct HourForecast: Equatable, Sendable {
    public enum Precipitation: Equatable, Sendable { case none, rain, snow }

    /// The start of the hour.
    public var date: Date
    /// 0 to 1.
    public var precipitationChance: Double
    public var precipitation: Precipitation
    public var windKmh: Double

    public init(date: Date, precipitationChance: Double = 0, precipitation: Precipitation = .none, windKmh: Double = 0) {
        self.date = date
        self.precipitationChance = precipitationChance
        self.precipitation = precipitation
        self.windKmh = windKmh
    }
}

/// The one line under the temperature: "Rain from 3 PM", "Snow now", "Windy today".
public enum WeatherNote: Equatable, Sendable {
    /// Rain from this time. A time at or before now means it's raining now.
    case rain(from: Date)
    case snow(from: Date)
    case windy

    /// Rain or snow is likely from this chance up.
    public static let likelyChance = 0.5
    /// Windy from this speed up (a strong breeze).
    public static let windyKmh = 40.0

    /// The note for the rest of today: rain or snow first (from the first hour it's
    /// likely), then wind. Nil when today is calm and dry.
    public static func pick(from hours: [HourForecast], now: Date, calendar: Calendar = .current) -> WeatherNote? {
        guard let thisHour = calendar.dateInterval(of: .hour, for: now)?.start,
              let tomorrow = calendar.dateInterval(of: .day, for: now)?.end else { return nil }
        let today = hours
            .filter { $0.date >= thisHour && $0.date < tomorrow }
            .sorted { $0.date < $1.date }
        if let wet = today.first(where: { $0.precipitation != .none && $0.precipitationChance >= likelyChance }) {
            return wet.precipitation == .snow ? .snow(from: wet.date) : .rain(from: wet.date)
        }
        if today.contains(where: { $0.windKmh >= windyKmh }) { return .windy }
        return nil
    }
}

/// Where the weather comes from (WeatherKit in the app, a fake in tests and previews).
public protocol WeatherSource: Sendable {
    /// Whether Squawk may read the location the weather needs.
    @MainActor var access: SourceAccess { get }
    /// Shows the iOS prompt if it hasn't been shown. True when allowed afterwards.
    @MainActor func requestAccess() async -> Bool
    /// Today's weather where you are.
    func today() async throws -> SummaryWeather
}

// MARK: Calendar

/// A calendar event, as much of it as the Today card needs.
public struct AgendaEvent: Equatable, Sendable {
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool

    public init(title: String, start: Date, end: Date, isAllDay: Bool = false) {
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
    }
}

/// What the calendar half of the Today card says.
public enum Agenda: Equatable, Sendable {
    /// "Nothing on the calendar today."
    case empty
    /// "9:30 · Standup", "and 3 more". `started` is true when it's already on.
    case next(AgendaEvent, started: Bool, more: Int)

    /// The next timed event today that hasn't ended, and how many more follow it.
    /// All-day events are left out.
    public init(events: [AgendaEvent], now: Date, calendar: Calendar = .current) {
        let endOfDay = calendar.dateInterval(of: .day, for: now)?.end ?? now
        let left = events
            .filter { !$0.isAllDay && $0.end > now && $0.start < endOfDay }
            .sorted { ($0.start, $0.title) < ($1.start, $1.title) }
        guard let first = left.first else {
            self = .empty
            return
        }
        self = .next(first, started: first.start <= now, more: left.count - 1)
    }
}

/// Where the events come from (EventKit in the app, a fake in tests and previews).
public protocol AgendaSource: Sendable {
    /// Whether Squawk may read the calendar.
    @MainActor var access: SourceAccess { get }
    /// Shows the iOS prompt if it hasn't been shown. True when allowed afterwards.
    @MainActor func requestAccess() async -> Bool
    /// Today's events, from every calendar.
    func today() async throws -> [AgendaEvent]
}

/// Whether Squawk may use a source.
public enum SourceAccess: Equatable, Sendable {
    case notAsked
    case allowed
    /// Turned off in iOS Settings, or not allowed on this device.
    case denied
}

// MARK: Settings

/// Which halves of the summary are on, and whether Good morning still offers it.
/// Saved in UserDefaults by the app.
public struct SummarySettings: Codable, Equatable, Sendable {
    public var weather = false
    public var calendar = false
    /// "Not now" on the offer card hides it for good.
    public var offerDismissed = false
    /// How many mornings the offer card has shown.
    public var offersShown = 0

    /// The offer shows on this many mornings at most.
    public static let maxOffers = 3

    public init(weather: Bool = false, calendar: Bool = false, offerDismissed: Bool = false, offersShown: Int = 0) {
        self.weather = weather
        self.calendar = calendar
        self.offerDismissed = offerDismissed
        self.offersShown = offersShown
    }

    public var isOn: Bool { weather || calendar }

    /// True while Good morning should show "Add the weather and your day".
    public var shouldOffer: Bool {
        !isOn && !offerDismissed && offersShown < Self.maxOffers
    }
}

// MARK: Timeout

/// The operation timed out (see `withTimeout`).
public struct TimedOut: Error, Equatable {
    public init() {}
}

/// Runs `operation`, and throws `TimedOut` if it takes longer than `seconds`. Used so a
/// slow weather request never holds up Good morning.
public func withTimeout<T: Sendable>(
    seconds: Double, _ operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw TimedOut()
        }
        defer { group.cancelAll() }
        guard let result = try await group.next() else { throw TimedOut() }
        return result
    }
}

// MARK: Fakes

/// A weather source with set answers, for tests and previews. Nil weather fails.
@MainActor
public final class FakeWeatherSource: WeatherSource {
    public var access: SourceAccess
    /// What the "iOS prompt" answers.
    public var answer: SourceAccess = .allowed
    public var weather: SummaryWeather?
    public var delay: Double

    public init(access: SourceAccess = .allowed, weather: SummaryWeather? = .preview, delay: Double = 0) {
        self.access = access
        self.weather = weather
        self.delay = delay
    }

    public func requestAccess() async -> Bool {
        if access == .notAsked { access = answer }
        return access == .allowed
    }

    public func today() async throws -> SummaryWeather {
        if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
        guard let weather else { throw TimedOut() }
        return weather
    }
}

/// A calendar with set events, for tests and previews.
@MainActor
public final class FakeAgendaSource: AgendaSource {
    public var access: SourceAccess
    /// What the "iOS prompt" answers.
    public var answer: SourceAccess = .allowed
    public var events: [AgendaEvent]

    public init(access: SourceAccess = .allowed, events: [AgendaEvent] = []) {
        self.access = access
        self.events = events
    }

    public func requestAccess() async -> Bool {
        if access == .notAsked { access = answer }
        return access == .allowed
    }

    public func today() async throws -> [AgendaEvent] { events }
}

extension SummaryWeather {
    /// A rainy 12° morning, for previews.
    public static let preview = SummaryWeather(
        symbol: "cloud.drizzle.fill", condition: "Drizzle",
        nowCelsius: 12, highCelsius: 16, lowCelsius: 9,
        note: .rain(from: Calendar.current.date(bySettingHour: 15, minute: 0, second: 0, of: Date()) ?? Date())
    )
}
