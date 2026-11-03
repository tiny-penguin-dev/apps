import CoreLocation
import EventKit
import SquawkKit
import WeatherKit

/// Today's weather from Apple's WeatherKit, for your rough location ("while using the
/// app", approximate). The location goes to Apple for the forecast and nowhere else.
@MainActor
final class LiveWeatherSource: NSObject, WeatherSource, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var accessWaiters: [CheckedContinuation<Void, Never>] = []
    private var locationWaiters: [CheckedContinuation<CLLocation, Error>] = []

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyReduced
    }

    var access: SourceAccess {
        switch manager.authorizationStatus {
        case .notDetermined: .notAsked
        case .authorizedWhenInUse, .authorizedAlways: .allowed
        default: .denied
        }
    }

    func requestAccess() async -> Bool {
        if access == .notAsked {
            await withCheckedContinuation { continuation in
                accessWaiters.append(continuation)
                manager.requestWhenInUseAuthorization()
            }
        }
        return access == .allowed
    }

    func today() async throws -> SummaryWeather {
        let location = try await currentLocation()
        let service = WeatherService.shared
        let (current, daily, hourly) = try await service.weather(for: location, including: .current, .daily, .hourly)
        let day = daily.first
        let hours = hourly.map { hour in
            HourForecast(
                date: hour.date,
                precipitationChance: hour.precipitationChance,
                precipitation: Self.kind(of: hour.precipitation),
                windKmh: hour.wind.speed.converted(to: .kilometersPerHour).value
            )
        }
        let credit = try? await service.attribution
        return SummaryWeather(
            symbol: current.symbolName,
            condition: current.condition.description,
            nowCelsius: current.temperature.converted(to: .celsius).value,
            highCelsius: (day?.highTemperature ?? current.temperature).converted(to: .celsius).value,
            lowCelsius: (day?.lowTemperature ?? current.temperature).converted(to: .celsius).value,
            note: WeatherNote.pick(from: hours, now: Date()),
            credit: credit.map {
                WeatherCredit(lightMark: $0.combinedMarkLightURL, darkMark: $0.combinedMarkDarkURL, legalPage: $0.legalPageURL)
            }
        )
    }

    private static func kind(of precipitation: Precipitation) -> HourForecast.Precipitation {
        switch precipitation {
        case .none: .none
        case .snow: .snow
        default: .rain
        }
    }

    /// A location from the last hour, or a fresh one.
    private func currentLocation() async throws -> CLLocation {
        if let last = manager.location, abs(last.timestamp.timeIntervalSinceNow) < 3600 {
            return last
        }
        return try await withCheckedThrowingContinuation { continuation in
            locationWaiters.append(continuation)
            manager.requestLocation()
        }
    }

    // MARK: CLLocationManagerDelegate (called on the main thread, where the manager was made)

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated {
            guard access != .notAsked else { return }
            let waiters = accessWaiters
            accessWaiters = []
            waiters.forEach { $0.resume() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        MainActor.assumeIsolated {
            let waiters = locationWaiters
            locationWaiters = []
            waiters.forEach { $0.resume(returning: location) }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        MainActor.assumeIsolated {
            let waiters = locationWaiters
            locationWaiters = []
            waiters.forEach { $0.resume(throwing: error) }
        }
    }
}

/// Today's events from every calendar on the phone, read with EventKit. Squawk never
/// changes the calendar.
@MainActor
final class LiveAgendaSource: AgendaSource {
    private let store = EKEventStore()

    var access: SourceAccess {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined: .notAsked
        case .fullAccess: .allowed
        default: .denied
        }
    }

    func requestAccess() async -> Bool {
        if access == .notAsked {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                store.requestFullAccessToEvents { _, _ in continuation.resume() }
            }
            store.reset()
        }
        return access == .allowed
    }

    func today() async throws -> [AgendaEvent] {
        guard access == .allowed, let day = Calendar.current.dateInterval(of: .day, for: Date()) else { return [] }
        let predicate = store.predicateForEvents(withStart: day.start, end: day.end, calendars: nil)
        return store.events(matching: predicate).map { event in
            AgendaEvent(title: event.title ?? "Busy", start: event.startDate, end: event.endDate, isAllDay: event.isAllDay)
        }
    }
}
