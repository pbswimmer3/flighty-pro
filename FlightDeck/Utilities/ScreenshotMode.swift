import SwiftUI

/// Launch-argument harness for cloud screenshots (see scripts/capture_screens.py
/// and the `screenshots` workflow in codemagic.yaml).
///
/// Inert unless the app is launched with `-FDScreenshot <scene>`. In that mode:
/// Demo Mode is forced on, no permission prompt is ever shown, and the root
/// view jumps straight to the requested scene.
///
/// To add a scene: add a case, give it a `tab` (or `.none` if it needs a
/// standalone screen), and handle it in `ScreenshotRoot.body` if standalone.
enum ScreenshotMode {

    enum Scene: String, CaseIterable {
        case flights, detail, tracking, passport, airports, airportTraffic, delays, connection, settings
        // `forecast` is deliberately absent: FlightDetailView has no scroll
        // anchor for the forecast card, and adding one means editing a view.

        /// Tab to select, or nil when the scene is a standalone screen.
        var tab: Int? {
            switch self {
            case .flights: 0
            case .passport: 1
            case .connection: 3
            case .settings: 4
            case .detail, .tracking, .airports, .airportTraffic, .delays: nil
            }
        }
    }

    /// The requested scene, parsed once from the process arguments.
    static let scene: Scene? = {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-FDScreenshot"), i + 1 < args.count else { return nil }
        return Scene(rawValue: args[i + 1])
    }()

    static var isActive: Bool { scene != nil }

    /// Scenes that read the Passport stats get ~10 extra past flights.
    static var seedsPastFlights: Bool { scene == .passport || scene == .delays }

    /// Call right after the store is built. In-memory only, screenshot mode only.
    @MainActor
    static func seed(_ store: FlightStore) {
        guard seedsPastFlights else { return }
        store.seedScreenshotFlights(DemoFlightProvider.screenshotPastFlights())
    }

    /// Call once at startup, before the stores are built.
    static func prepare() {
        guard isActive else { return }
        UserDefaults.standard.set(true, forKey: "demoMode")
    }
}

/// Standalone screens for scenes that are normally reached by tapping.
struct ScreenshotRoot: View {
    let scene: ScreenshotMode.Scene
    @EnvironmentObject private var store: FlightStore

    private var inAir: Flight? {
        store.flights.first { $0.effectivePhase.isAirborne } ?? store.flights.first
    }

    var body: some View {
        NavigationStack {
            switch scene {
            case .detail:
                if let f = inAir { FlightDetailView(flightID: f.id) }
            case .tracking:
                if let f = inAir { TrackingScene(flight: f) }
            case .airports:
                if let a = AirportDatabase.shared.airport(iata: "JFK") { AirportDetailView(airport: a) }
            case .airportTraffic:
                if let a = AirportDatabase.shared.airport(iata: "JFK") { AirportTrafficView(airport: a) }
            case .delays:
                DelayTrackerView(stats: store.passport())
            default:
                EmptyView()
            }
        }
    }
}

private struct TrackingScene: View {
    let flight: Flight
    @StateObject private var tracker = AircraftTracker()

    var body: some View {
        FlightTrackingMapView(flight: flight, tracker: tracker, initialScope: .route)
            .onAppear { if let cs = flight.callSign { tracker.start(callSign: cs) } }
    }
}
