import Foundation

/// Carries one day's published timetable for a flight number onto another day.
///
/// Live status feeds only answer reliably about a week either side of today,
/// but people book months ahead. Airlines publish departures as *local clock
/// times* that repeat week to week, so "AS 2187 leaves SNA at 7:59 PM on
/// Tuesdays" this week is the best available statement about a Tuesday in
/// March — until the feed reaches March, at which point the flight is
/// refreshed and the projection disappears.
///
/// Pure value logic, no I/O: the provider fetches the reference day and this
/// decides what the target day looks like.
enum ScheduleProjection {

    /// - Parameters:
    ///   - reference: the flight as the provider returned it for `referenceDay`.
    ///   - referenceDay: the local calendar day that was asked for (Y/M/D).
    ///   - targetDay: the local calendar day the user wants (Y/M/D).
    /// - Returns: a scheduled, unflown copy on `targetDay`, marked projected;
    ///   `nil` if the dates can't be built.
    static func project(_ reference: Flight,
                        from referenceDay: DateComponents,
                        onto targetDay: DateComponents) -> Flight? {
        let originCalendar = calendar(in: reference.originAirport?.timeZone ?? .current)
        let departureLocal = originCalendar.dateComponents([.year, .month, .day, .hour, .minute],
                                                           from: reference.scheduledDeparture)

        // The provider answers "flights on day D" by departure *or* arrival
        // date, so the leg can depart the day before the day asked for. Keep
        // that offset intact.
        guard let departureLead = days(from: referenceDay, to: departureLocal),
              let newDepartureDay = adding(departureLead, to: targetDay),
              let newDeparture = originCalendar.date(from: at(newDepartureDay, like: departureLocal))
        else { return nil }

        // Departure keeps its local clock time; arrival keeps the block time.
        // Not the arrival's local clock time: when the two ends change clocks
        // on different dates (New York and London, for a few weeks each
        // spring and autumn) that would make the flight an hour longer or
        // shorter, and the aircraft doesn't fly any faster in March.
        let block = reference.scheduledArrival.timeIntervalSince(reference.scheduledDeparture)
        let newArrival = newDeparture.addingTimeInterval(block)

        var flight = reference
        flight.id = UUID()
        flight.scheduledDeparture = newDeparture
        flight.scheduledArrival = newArrival
        flight.estimatedDeparture = nil
        flight.actualDeparture = nil
        flight.estimatedArrival = nil
        flight.actualArrival = nil
        // Gates, belts, the tail and the inbound rotation belong to that one
        // day's operation. Terminals and the aircraft type are properties of
        // the schedule and usually hold, so they stay.
        flight.departureGate = nil
        flight.arrivalGate = nil
        flight.baggageClaim = nil
        flight.registration = nil
        flight.inbound = nil
        flight.phase = .scheduled
        flight.projectedFrom = reference.scheduledDeparture
        flight.lastUpdated = .now
        return flight
    }

    /// The days worth asking the live feed about to project onto `targetDay`:
    /// the same weekday this coming week first (the most current timetable),
    /// then the same weekday last week. Both sit inside a one-week window.
    static func referenceDays(for targetDay: DateComponents,
                              now: Date = .now,
                              calendar: Calendar = .current) -> [DateComponents] {
        guard let target = calendar.date(from: targetDay) else { return [] }
        let today = calendar.startOfDay(for: now)
        let gap = (calendar.component(.weekday, from: target)
                   - calendar.component(.weekday, from: today) + 7) % 7
        guard let upcoming = calendar.date(byAdding: .day, value: gap, to: today),
              let previous = calendar.date(byAdding: .day, value: -7, to: upcoming)
        else { return [] }
        return [upcoming, previous].map { calendar.dateComponents([.year, .month, .day], from: $0) }
    }

    // MARK: - Calendar arithmetic on bare Y/M/D
    //
    // Done in UTC so a DST transition between the two days can't turn
    // "seven days" into 6.96 of them.

    private static let utc: Calendar = calendar(in: TimeZone(identifier: "UTC")!)

    private static func calendar(in zone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar
    }

    private static func dayOnly(_ components: DateComponents) -> Date? {
        utc.date(from: DateComponents(year: components.year, month: components.month, day: components.day))
    }

    private static func days(from a: DateComponents, to b: DateComponents) -> Int? {
        guard let start = dayOnly(a), let end = dayOnly(b) else { return nil }
        return utc.dateComponents([.day], from: start, to: end).day
    }

    private static func adding(_ days: Int, to day: DateComponents) -> DateComponents? {
        guard let start = dayOnly(day),
              let moved = utc.date(byAdding: .day, value: days, to: start) else { return nil }
        return utc.dateComponents([.year, .month, .day], from: moved)
    }

    private static func at(_ day: DateComponents, like time: DateComponents) -> DateComponents {
        DateComponents(year: day.year, month: day.month, day: day.day,
                       hour: time.hour, minute: time.minute)
    }
}
