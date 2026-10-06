import Foundation
import Combine

/// View-side cache in front of `FlightRouteService`.
///
/// The map draws inside a `Canvas` on a display clock, so it cannot `await`
/// anything mid-frame. This holds resolved routes in published state that a
/// frame can read synchronously, and kicks off the lookup once per callsign.
@MainActor
final class RouteLookup: ObservableObject {
    @Published private(set) var routes: [String: FlightRouteService.Route] = [:]
    /// Callsigns with a request in flight, so the UI can say "looking up…"
    /// instead of "route unknown" for the second it takes.
    @Published private(set) var pending: Set<String> = []

    private var attempted: Set<String> = []

    func route(for callsign: String?) -> FlightRouteService.Route? {
        guard let key = Self.key(callsign) else { return nil }
        return routes[key]
    }

    func isLoading(_ callsign: String?) -> Bool {
        guard let key = Self.key(callsign) else { return false }
        return pending.contains(key)
    }

    /// True once we've asked and come back empty — the difference between
    /// "still loading" and "this callsign isn't in the route table".
    func isUnknown(_ callsign: String?) -> Bool {
        guard let key = Self.key(callsign) else { return true }
        return attempted.contains(key) && !pending.contains(key) && routes[key] == nil
    }

    func lookup(_ callsign: String?) {
        guard let key = Self.key(callsign), !attempted.contains(key) else { return }
        attempted.insert(key)
        pending.insert(key)
        Task {
            let route = await FlightRouteService.shared.route(for: key)
            if let route { routes[key] = route }
            pending.remove(key)
        }
    }

    private static func key(_ callsign: String?) -> String? {
        guard let cleaned = callsign?.uppercased().filter({ $0.isLetter || $0.isNumber }),
              cleaned.count >= 3 else { return nil }
        return cleaned
    }
}
