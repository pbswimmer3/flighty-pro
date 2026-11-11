import SwiftUI

/// The signature flight card: airline badge + flight number,
/// huge airport codes, live progress bar, status pill and delay-aware times.
struct FlightCard: View {
    let flight: Flight

    private var phase: FlightPhase { flight.effectivePhase }

    var body: some View {
        VStack(spacing: 14) {
            header
            routeRow
            ProgressPlaneBar(progress: flight.progress, activeColor: progressColor)
            timesRow
            // Only while there's still something to count down to. On a flight
            // that's over, "Bags in 0m" is noise.
            if showsStageBar {
                Divider().overlay(Theme.separator)
                FlightStageBar(flight: flight, compact: true)
            }
        }
        .cardStyle()
        // One VoiceOver stop per card, read as a sentence. Read child by
        // child it came out as "9:53 PM 10:18 PM San Francisco", and the
        // strikethrough that says which time is stale means nothing aloud.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private var showsStageBar: Bool {
        let stage = flight.stage()
        return stage != .arrived && stage != .scheduled && stage != .cancelled
    }

    // MARK: Subviews

    private var header: some View {
        HStack(spacing: 10) {
            AirlineBadge(code: flight.airlineCode, size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(flight.displayNumber)
                    .scaledFont(15, weight: .semibold, design: .monospaced)
                    .monospacedDigit()
                Text(flight.airlineName)
                    .scaledFont(12, weight: .medium)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            statusPill
        }
    }

    private var routeRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(flight.originIATA)
                .scaledFont(34, weight: .heavy)
            Image(systemName: "arrow.right")
                .scaledFont(16, weight: .heavy, design: .default)
                .foregroundStyle(Theme.textTertiary)
            Text(flight.destinationIATA)
                .scaledFont(34, weight: .heavy)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Fmt.dayAndDate(flight.scheduledDeparture,
                                    tz: AirportDatabase.shared.airport(iata: flight.originIATA)?.timeZone))
                    .scaledFont(12, weight: .semibold)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
                Text(Fmt.duration(flight.duration))
                    .scaledFont(12, weight: .semibold)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }

    private var timesRow: some View {
        HStack {
            timeColumn(label: cityName(flight.originIATA),
                       scheduled: flight.scheduledDeparture,
                       best: flight.bestDeparture,
                       iata: flight.originIATA,
                       alignment: .leading)
            Spacer()
            // "Lands in …" used to sit here. It now lives in the stage bar
            // below, which counts down live instead of rounding to the hour —
            // two of them on one card was one too many.
            Spacer()
            timeColumn(label: cityName(flight.destinationIATA),
                       scheduled: flight.scheduledArrival,
                       best: flight.bestArrival,
                       iata: flight.destinationIATA,
                       alignment: .trailing)
        }
    }

    private func timeColumn(label: String, scheduled: Date, best: Date,
                            iata: String, alignment: HorizontalAlignment) -> some View {
        let changed = isChanged(scheduled: scheduled, best: best)
        return VStack(alignment: alignment, spacing: 2) {
            HStack(spacing: 5) {
                if changed {
                    Text(Fmt.time(scheduled, airportIATA: iata))
                        .strikethrough()
                        .scaledFont(12, weight: .medium)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                Text(Fmt.time(best, airportIATA: iata))
                    .scaledFont(16, weight: .heavy)
                    .monospacedDigit()
                    .foregroundStyle(changed ? Theme.orange : Theme.textPrimary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            Text(label)
                .scaledFont(11, weight: .medium)
                .foregroundStyle(Theme.textTertiary)
        }
    }

    private var statusPill: some View {
        let (text, color) = statusInfo
        return StatusPill(text: text, color: color)
    }

    /// The pill leads with trouble — a delay is what someone scanning a list
    /// of flights needs to see first. Otherwise it names the stage, so the
    /// card says "Taxiing" or "Landing soon" rather than a flat "En Route".
    private var statusInfo: (String, Color) {
        let stage = flight.stage()
        switch stage {
        case .cancelled: return ("Cancelled", Theme.red)
        case .diverted: return ("Diverted", Theme.red)
        case .airborne, .landingSoon, .taxiingOut:
            return flight.arrivalDelayMinutes > 10
                ? ("Late \(flight.arrivalDelayMinutes) min", Theme.orange)
                : (stage.label, Theme.accent)
        case .taxiingIn, .atGate, .arrived: return ("Arrived", Theme.green)
        case .boarding, .gateClosing: return (stage.label, Theme.purple)
        case .scheduled, .checkInOpen, .boardingSoon:
            // "On Time" about a timetable copied from another week would be a
            // claim nobody has made yet.
            if flight.isScheduleProjected { return ("Projected", Theme.textSecondary) }
            return flight.isDelayed
                ? ("Delayed \(flight.departureDelayMinutes) min", Theme.orange)
                : ("On Time", Theme.green)
        }
    }

    private var progressColor: Color {
        switch phase {
        case .cancelled, .diverted: return Theme.red
        case .landed, .arrived: return Theme.green
        default: return flight.isDelayed ? Theme.orange : Theme.accent
        }
    }

    private func cityName(_ iata: String) -> String {
        AirportDatabase.shared.airport(iata: iata)?.city ?? iata
    }

    /// Same five-minute rule the time columns use to strike the old time
    /// through, so the spoken "originally …" matches what's drawn.
    private func isChanged(scheduled: Date, best: Date) -> Bool {
        abs(best.timeIntervalSince(scheduled)) > 5 * 60
    }

    // MARK: Accessibility

    /// "DL 482, Delta Air Lines, San Francisco to New York, Late 14 min,
    /// departs 10:18 PM, originally 9:53 PM, arrives 6:25 AM, Lands in 3h 7m".
    /// Built from the same values the card draws, so the two can't disagree.
    private var accessibilitySummary: String {
        let now = Date.now
        var parts: [String] = [
            flight.displayNumber,
            flight.airlineName,
            "\(cityName(flight.originIATA)) to \(cityName(flight.destinationIATA))",
            statusInfo.0,
            spokenTime("departs", scheduled: flight.scheduledDeparture,
                       best: flight.bestDeparture, iata: flight.originIATA),
            spokenTime("arrives", scheduled: flight.scheduledArrival,
                       best: flight.bestArrival, iata: flight.destinationIATA),
        ]
        if showsStageBar {
            parts.append(stageHeadline(flight.stage(at: now), at: now))
        }
        return parts.joined(separator: ", ")
    }

    private func spokenTime(_ verb: String, scheduled: Date, best: Date, iata: String) -> String {
        let text = "\(verb) \(Fmt.time(best, airportIATA: iata))"
        guard isChanged(scheduled: scheduled, best: best) else { return text }
        return text + ", originally \(Fmt.time(scheduled, airportIATA: iata))"
    }

    /// Mirrors `FlightStageBar.headline`, which is private to that view. Kept
    /// in step by hand: it's six cases, and sharing it would mean editing the
    /// stage bar for an accessibility label.
    private func stageHeadline(_ stage: FlightStage, at now: Date) -> String {
        guard let next = flight.nextMilestone(at: now) else { return stage.label }
        let countdown = Fmt.countdown(to: next.date, from: now)
        switch next.kind {
        case .checkIn:   return "Check-in opens in \(countdown)"
        case .boarding:  return "Boards in \(countdown)"
        case .gateClose: return "Gate closes in \(countdown)"
        case .departure: return stage == .taxiingOut ? "Taxiing" : "Departs in \(countdown)"
        case .landing:   return "Lands in \(countdown)"
        case .bags:      return stage == .arrived ? stage.label : "Bags in \(countdown)"
        }
    }
}
