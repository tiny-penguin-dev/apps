@preconcurrency import HomeKit
import Observation
import SquawkKit

/// Squawk's view of your Home: whether it may use it, whether there's a Home hub, and
/// the lights, plugs, blinds and scenes it can control (features/steps/FEATURE.md,
/// "How Home control works"). Nothing touches HomeKit until someone adds a Home step,
/// since creating the home manager is what shows the iOS permission prompt.
@MainActor
@Observable
final class HomeAccess: NSObject {
    enum Status: Equatable {
        /// Squawk hasn't asked yet.
        case notAsked
        /// Waiting for HomeKit to answer.
        case loading
        case allowed
        /// Turned off in Settings, or not allowed on this device.
        case denied
    }

    private(set) var status: Status = .notAsked
    /// The home Squawk uses: the primary one, or the first.
    private(set) var home: HomeSnapshot?

    /// True when a Home hub (Apple TV or HomePod) can run timed automations.
    var hasHub: Bool { home?.hasHub ?? false }

    @ObservationIgnored private var manager: HMHomeManager?
    @ObservationIgnored private var waiting: [CheckedContinuation<Void, Never>] = []
    @ObservationIgnored let syncer = HomeSync()

    /// Set once Squawk has been allowed, so the next launch connects without asking.
    private static let connectedKey = "home.connected"

    static let shared = HomeAccess()

    override init() {
        super.init()
        if UserDefaults.standard.bool(forKey: Self.connectedKey) { connect() }
    }

    /// Shows the iOS prompt the first time, then waits until HomeKit has loaded.
    func requestAccess() async {
        if manager == nil { connect() }
        await loaded()
    }

    /// Waits until the homes have loaded (or access was refused), for up to 10 seconds.
    func loaded() async {
        guard status == .loading else { return }
        await withCheckedContinuation { continuation in
            waiting.append(continuation)
            Task {
                try? await Task.sleep(for: .seconds(10))
                self.resumeWaiting()
            }
        }
    }

    private func resumeWaiting() {
        let resume = waiting
        waiting = []
        resume.forEach { $0.resume() }
    }

    private func connect() {
        status = .loading
        let manager = HMHomeManager()
        manager.delegate = self
        self.manager = manager
    }

    private func reload() {
        guard let manager else { return }
        let auth = manager.authorizationStatus
        if auth.contains(.determined), !auth.contains(.authorized) {
            status = .denied
            home = nil
        } else if auth.contains(.authorized) {
            let wasAllowed = status == .allowed
            status = .allowed
            home = primaryHome(manager).map(HomeSnapshot.init)
            if !wasAllowed {
                UserDefaults.standard.set(true, forKey: Self.connectedKey)
                Telemetry.count("home.connected", ["hub": hasHub ? "yes" : "no"])
            }
        } else {
            return
        }
        resumeWaiting()
    }

    /// The HomeKit home itself, for syncing and running things.
    func currentHome() -> HMHome? {
        manager.flatMap(primaryHome)
    }

    private func primaryHome(_ manager: HMHomeManager) -> HMHome? {
        manager.homes.first(where: \.isPrimary) ?? manager.homes.first
    }
}

extension HomeAccess: HomeController {
    func sync(_ plan: [PlannedHomeStep]) async {
        await loaded()
        guard status == .allowed, let home = currentHome() else { return }
        await syncer.sync(plan, in: home)
    }

    func runUp(_ actions: [HomeAction]) async {
        guard !actions.isEmpty else { return }
        await loaded()
        guard status == .allowed, let home = currentHome() else { return }
        await syncer.run(actions, in: home)
    }
}

/// What the alarms model needs from Home. The real one is `HomeAccess`; previews have
/// none.
@MainActor
protocol HomeController: AnyObject {
    /// Makes the Home automations match these planned steps.
    func sync(_ plan: [PlannedHomeStep]) async
    /// Runs "When you're up" now.
    func runUp(_ actions: [HomeAction]) async
}

extension HomeAccess: HMHomeManagerDelegate {
    nonisolated func homeManagerDidUpdateHomes(_ manager: HMHomeManager) {
        Task { @MainActor in self.reload() }
    }

    nonisolated func homeManager(_ manager: HMHomeManager, didUpdate status: HMHomeManagerAuthorizationStatus) {
        Task { @MainActor in self.reload() }
    }

    nonisolated func homeManagerDidUpdatePrimaryHome(_ manager: HMHomeManager) {
        Task { @MainActor in self.reload() }
    }
}

/// What Squawk can use in one home, read once so screens don't hold HomeKit objects.
struct HomeSnapshot: Equatable {
    var name: String
    var hasHub: Bool
    var devices: [HomeDevice]
    var scenes: [HomeTarget]

    init(name: String, hasHub: Bool, devices: [HomeDevice], scenes: [HomeTarget]) {
        self.name = name
        self.hasHub = hasHub
        self.devices = devices
        self.scenes = scenes
    }

    init(_ home: HMHome) {
        name = home.name
        hasHub = home.homeHubState == .connected
        devices = home.accessories.flatMap { accessory in
            accessory.services.compactMap { HomeDevice(service: $0, accessory: accessory) }
        }
        .sorted { ($0.target.room, $0.target.name) < ($1.target.room, $1.target.name) }
        scenes = home.actionSets
            .filter { !$0.name.hasPrefix(HomePlanner.namePrefix) && !$0.actions.isEmpty }
            .map { HomeTarget(id: $0.uniqueIdentifier, name: $0.name) }
            .sorted { $0.name < $1.name }
    }

    func devices(_ kind: HomeAction.Kind) -> [HomeDevice] {
        devices.filter { $0.kind == kind }
    }
}

/// A light, plug, switch or blind Squawk can control.
struct HomeDevice: Identifiable, Equatable {
    var target: HomeTarget
    var kind: HomeAction.Kind
    var dimmable: Bool
    var hasColor: Bool

    var id: UUID { target.id }

    init(target: HomeTarget, kind: HomeAction.Kind, dimmable: Bool = false, hasColor: Bool = false) {
        self.target = target
        self.kind = kind
        self.dimmable = dimmable
        self.hasColor = hasColor
    }

    init?(service: HMService, accessory: HMAccessory) {
        let types = Set(service.characteristics.map(\.characteristicType))
        switch service.serviceType {
        case HMServiceTypeLightbulb: kind = .light
        case HMServiceTypeOutlet, HMServiceTypeSwitch: kind = .plug
        case HMServiceTypeWindowCovering: kind = .blinds
        default: return nil
        }
        let name = service.name.isEmpty ? accessory.name : service.name
        target = HomeTarget(id: service.uniqueIdentifier, name: name, room: accessory.room?.name ?? "")
        dimmable = types.contains(HMCharacteristicTypeBrightness)
        hasColor = types.contains(HMCharacteristicTypeColorTemperature)
    }

    /// "Dimmable, color", "On / off".
    var abilities: String {
        switch kind {
        case .light: hasColor ? "Dimmable, color" : dimmable ? "Dimmable" : "On / off"
        case .plug: "On / off"
        case .blinds: "Opens and closes"
        case .scene: ""
        }
    }
}
