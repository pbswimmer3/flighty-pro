import Foundation
import UserNotifications

/// Flight alerts, delivered without a server.
///
/// The app has no push certificate and no backend — Flighty's alerts are
/// server-pushed, and matching that would need both. What *is* possible, and
/// what this does, is hand iOS the whole schedule up front as local
/// notifications: boarding, gate close, push-back, an hour before landing,
/// touchdown, bags. Those fire on time whether or not the app is running,
/// because the system owns them once they're scheduled.
///
/// The honest gap: **change** alerts (a new delay, a gate move, a
/// cancellation) can only be noticed while the app is awake to refresh. There
/// is no background push to wake it. Settings says so in as many words rather
/// than letting people assume they'll be told about a gate change from their
/// pocket.
@MainActor
final class NotificationService: ObservableObject {
    static let shared = NotificationService()

    @Published private(set) var authorization: UNAuthorizationStatus = .notDetermined
    /// What's currently handed to iOS — surfaced in Settings so the schedule
    /// isn't a black box.
    @Published private(set) var scheduledCount: Int = 0

    /// iOS keeps at most 64 pending local notifications per app and silently
    /// drops the rest. Staying under it deliberately, nearest first, means the
    /// alerts that get dropped are always the ones furthest away.
    private static let maxPending = 56

    /// Every request this app creates is prefixed, so a cleanup can never
    /// touch anything it didn't schedule.
    private static let prefix = "flightdeck."

    private let center = UNUserNotificationCenter.current()
    private let foregroundPresenter = ForegroundPresenter()

    private init() {
        center.delegate = foregroundPresenter
    }

    // MARK: - Authorization

    func refreshAuthorization() async {
        authorization = await center.notificationSettings().authorizationStatus
    }

    /// Returns whether alerts are usable afterwards. A second call once the
    /// user has denied does nothing — iOS only ever shows the prompt once, and
    /// the UI sends them to system Settings instead.
    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            await refreshAuthorization()
            return granted
        } catch {
            await refreshAuthorization()
            return false
        }
    }

    var isAuthorized: Bool {
        authorization == .authorized || authorization == .provisional || authorization == .ephemeral
    }

    // MARK: - Scheduled alerts

    /// Rebuild the entire pending schedule from the current flights.
    ///
    /// Idempotent by construction: everything this app scheduled is cleared and
    /// re-derived, so a flight that moved by an hour doesn't leave a stale
    /// boarding alert behind. Cheap enough to call on every store mutation.
    func sync(flights: [Flight], preferences: NotificationPreferences, now: Date = .now) async {
        let pending = await center.pendingNotificationRequests()
        let ours = pending.map(\.identifier).filter { $0.hasPrefix(Self.prefix) }
        if !ours.isEmpty { center.removePendingNotificationRequests(withIdentifiers: ours) }

        guard preferences.isEnabled, isAuthorized else {
            scheduledCount = 0
            return
        }

        let candidates = flights
            .filter { $0.phase != .cancelled }
            .flatMap { scheduledRequests(for: $0, preferences: preferences, now: now) }
            .sorted { $0.date < $1.date }
            .prefix(Self.maxPending)

        for candidate in candidates {
            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: max(candidate.date.timeIntervalSince(now), 1),
                repeats: false)
            let request = UNNotificationRequest(identifier: candidate.identifier,
                                                content: candidate.content,
                                                trigger: trigger)
            try? await center.add(request)
        }
        scheduledCount = candidates.count
    }

    private struct Candidate {
        var identifier: String
        var date: Date
        var content: UNNotificationContent
    }

    private func scheduledRequests(for flight: Flight,
                                   preferences: NotificationPreferences,
                                   now: Date) -> [Candidate] {
        // Nothing further out than a week: iOS's pending budget is small, and
        // a schedule that far ahead will have moved before it fires anyway.
        let horizon = now.addingTimeInterval(7 * 24 * 3600)
        var candidates: [Candidate] = []

        func add(_ alert: FlightAlert, at date: Date, title: String, body: String) {
            guard preferences.allows(alert),
                  date > now.addingTimeInterval(30),
                  date < horizon else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            content.threadIdentifier = flight.id.uuidString   // one thread per flight
            content.interruptionLevel = alert.isTimeSensitive ? .timeSensitive : .active
            candidates.append(Candidate(
                identifier: "\(Self.prefix)\(flight.id.uuidString).\(alert.rawValue)",
                date: date,
                content: content))
        }

        let number = flight.displayNumber
        let route = "\(flight.originIATA) → \(flight.destinationIATA)"
        let gate = flight.departureGate.map { "Gate \($0)" } ?? "Gate not posted yet"
        let departsLocal = Fmt.time(flight.bestDeparture, airportIATA: flight.originIATA)
        let arrivesLocal = Fmt.time(flight.bestArrival, airportIATA: flight.destinationIATA)

        add(.checkIn, at: flight.checkInOpensAt,
            title: "Check in for \(number)",
            body: "\(route) tomorrow, departing \(departsLocal). Check-in should be open now.")

        add(.boarding, at: flight.boardingStartsAt,
            title: "\(number) is boarding",
            body: "\(gate) at \(flight.originIATA). Departs \(departsLocal).")

        add(.gateClose, at: flight.gateClosesAt,
            title: "\(number) doors close soon",
            body: "\(gate) at \(flight.originIATA) closes about now — departure is \(departsLocal).")

        add(.departure, at: flight.bestDeparture,
            title: "\(number) is departing",
            body: "Pushing back from \(flight.originIATA). Lands \(arrivesLocal) at \(flight.destinationIATA).")

        add(.landingSoon, at: flight.bestArrival.addingTimeInterval(-3600),
            title: "\(number) lands in about an hour",
            body: "Arriving \(arrivesLocal) at \(flight.destinationIATA).")

        add(.landing, at: flight.bestArrival,
            title: "\(number) has landed",
            body: "Touchdown at \(flight.destinationIATA)."
                + (flight.arrivalGate.map { " Gate \($0)." } ?? ""))

        add(.bags, at: flight.bagsExpectedAt,
            title: flight.baggageClaim.map { "Bags at claim \($0)" } ?? "Bags should be out",
            body: "\(number) baggage at \(flight.destinationIATA) around now.")

        return candidates
    }

    // MARK: - Change alerts

    /// Deliver immediately. Only reachable while the app is running — see the
    /// note at the top of this file.
    func announce(_ changes: [FlightChange],
                  for flight: Flight,
                  preferences: NotificationPreferences) async {
        guard preferences.isEnabled, isAuthorized else { return }
        for change in changes where preferences.allows(change.alert) {
            let content = UNMutableNotificationContent()
            content.title = change.title
            content.body = change.body
            content.sound = .default
            content.threadIdentifier = flight.id.uuidString
            content.interruptionLevel = change.alert.isTimeSensitive ? .timeSensitive : .active
            // A nil trigger fires as soon as it's accepted; the UUID means two
            // identical changes seconds apart can't collapse into one.
            let request = UNNotificationRequest(
                identifier: "\(Self.prefix)\(flight.id.uuidString).\(change.alert.rawValue).\(UUID().uuidString)",
                content: content,
                trigger: nil)
            try? await center.add(request)
        }
    }

    // MARK: - Diagnostics

    /// Fires in five seconds so there's time to background the app and see it
    /// arrive the way a real alert would.
    func sendTestAlert() async {
        guard isAuthorized else { return }
        let content = UNMutableNotificationContent()
        content.title = "FlightDeck alerts are on"
        content.body = "This is what a boarding or gate-change alert will look like."
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "\(Self.prefix)test.\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false))
        try? await center.add(request)
    }

    func cancelAll() {
        center.removeAllPendingNotificationRequests()
        scheduledCount = 0
    }
}

/// Without a delegate, iOS suppresses notifications while the app is
/// foregrounded — which is exactly when someone sitting on the flight page
/// most wants to see the gate change.
private final class ForegroundPresenter: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async
    -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
}
