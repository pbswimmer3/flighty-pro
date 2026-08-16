import Foundation
import CoreLocation

/// One aircraft as reported over ADS-B, normalised out of the adsb.lol wire
/// format so nothing above this layer has to know the API's field names.
///
/// The position here is a *report* — what the aircraft broadcast `fixAge`
/// seconds ago. What gets drawn on the map is an estimate projected forward
/// from it (see `DeadReckoning`), which is why `validAt` matters so much.
struct TrafficReport: Identifiable {
    let hex: String                  // stable identity across polls
    let callsign: String?
    let registration: String?
    let icaoType: String?            // "B77W"
    let coordinate: CLLocationCoordinate2D
    let onGround: Bool
    let altitudeFeet: Int?
    let groundSpeedKts: Double?
    let headingDegrees: Double?      // track (airborne) ?? true_heading (surface)
    let verticalRateFPM: Int?
    let accuracyMetres: Double?      // 95% bound derived from NACp
    let fixAge: TimeInterval         // seen_pos
    let isMLAT: Bool                 // multilaterated — lower confidence
    let distanceNM: Double?          // from the query centre, when searching
    let receivedAt: Date

    /// Key on `hex`, never on callsign: callsigns are absent on some records
    /// and get reused across days.
    var id: String { hex }

    /// The instant this position was actually true. Extrapolation starts here,
    /// *not* at response-receipt time — `seen_pos` is routinely seconds old and
    /// occasionally tens of seconds.
    var validAt: Date { receivedAt.addingTimeInterval(-fixAge) }

    var label: String { callsign ?? registration ?? hex.uppercased() }

    /// Parked at a gate. Worth its own concept: these must never be
    /// extrapolated or they creep across the apron on floating-point noise.
    var isStationary: Bool { (groundSpeedKts ?? 0) < DeadReckoning.Limits.stationaryKts }
}

// MARK: - Wire format

/// Raw adsb.lol aircraft object, shared by `AdsbService` (single callsign) and
/// `TrafficService` (radius search) so the decoding lives in exactly one place.
struct AdsbAircraft: Decodable {
    var hex: String?
    var type: String?               // "adsb_icao", "mlat", "tisb_trackfile"…
    var flight: String?             // callsign, space-padded
    var r: String?                  // registration
    var t: String?                  // ICAO type code
    var lat: Double?
    var lon: Double?
    var alt_baro: FlexibleValue?    // number of feet, or the string "ground"
    var alt_geom: Double?
    var gs: Double?                 // knots
    var track: Double?              // airborne aircraft report this…
    var true_heading: Double?       // …surface aircraft report this instead
    var baro_rate: Double?
    var geom_rate: Double?
    var nac_p: Double?              // navigation accuracy category — position
    var nic: Double?
    var rc: Double?                 // integrity containment radius (NOT accuracy)
    var seen_pos: Double?
    var mlat: [String]?             // which fields were multilaterated
    var tisb: [String]?
    var dst: Double?                // nm from the query centre

    /// `nil` when the record can't be placed on a map.
    func report(receivedAt: Date = .now) -> TrafficReport? {
        guard let hex, let lat, let lon,
              CLLocationCoordinate2DIsValid(CLLocationCoordinate2D(latitude: lat, longitude: lon))
        else { return nil }

        var onGround = false
        var altitude: Int?
        switch alt_baro {
        case .string(let s): onGround = s.caseInsensitiveCompare("ground") == .orderedSame
        case .number(let feet): altitude = Int(feet)
        case nil: break
        }

        let callsign = flight?.trimmingCharacters(in: .whitespaces)

        return TrafficReport(
            hex: hex.lowercased(),
            callsign: (callsign?.isEmpty ?? true) ? nil : callsign,
            registration: r,
            icaoType: t,
            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
            onGround: onGround,
            altitudeFeet: altitude,
            groundSpeedKts: gs,
            // The Phase 0 bug: reading only `track` silently drops heading the
            // moment an aircraft touches down, because surface position
            // messages carry `true_heading` instead.
            headingDegrees: track ?? true_heading,
            verticalRateFPM: (baro_rate ?? geom_rate).map { Int($0) },
            accuracyMetres: Self.accuracyMetres(nacP: nac_p),
            fixAge: seen_pos ?? 0,
            isMLAT: !(mlat?.isEmpty ?? true) || type == "mlat",
            distanceNM: dst,
            receivedAt: receivedAt)
    }

    /// NACp → 95% horizontal accuracy bound in metres.
    ///
    /// Deliberately *not* `rc`: that's the 99.999% integrity containment radius
    /// (typically 186 m), and rendering it as the error circle makes every
    /// target look far fuzzier than it is.
    static func accuracyMetres(nacP: Double?) -> Double? {
        guard let nacP else { return nil }
        switch Int(nacP) {
        case 11: return 3
        case 10: return 10
        case 9: return 30
        case 8: return 92.6
        case 7: return 185.2
        default: return nil   // unknown — render without a confidence radius
        }
    }
}

/// adsb.lol response envelope. Decodes aircraft individually so one malformed
/// record can't blank the whole map.
struct AdsbResponse: Decodable {
    var aircraft: [AdsbAircraft]

    private enum CodingKeys: String, CodingKey { case ac }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try container.decodeIfPresent([Lenient<AdsbAircraft>].self, forKey: .ac) ?? []
        aircraft = raw.compactMap(\.value)
    }
}

/// Decodes to `nil` instead of throwing, so a bad element doesn't fail the array.
struct Lenient<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}
