import SwiftUI

/// "Boarding · Boards in 42m · Gate C11" — the one line that answers "what
/// happens next, and when".
///
/// Both halves move on their own: the stage comes from `Flight.stage(at:)`, so
/// the wording advances from Boarding through Taxiing to In the air without
/// anyone refreshing anything, and the countdown is driven by a `TimelineView`
/// so it actually ticks. The timeline is wrapped tightly around the text
/// rather than the whole card, because a card in a scrolling list should not
/// be re-laying itself out once a second.
struct FlightStageBar: View {
    let flight: Flight
    /// The card in a list wants one quiet line; the flight page wants the
    /// full-width panel.
    var compact: Bool = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            content(at: context.date)
        }
    }

    @ViewBuilder
    private func content(at now: Date) -> some View {
        let stage = flight.stage(at: now)
        if compact {
            HStack(spacing: 6) {
                // The icon tracks the *headline*, not the stage: the line
                // reads "Boards in 3h 38m" while the flight is still merely
                // checked-in-open, and a check-in glyph next to it looks like
                // a bug.
                Image(systemName: flight.nextMilestone(at: now)?.kind.systemImage ?? stage.systemImage)
                    .scaledFont(11, weight: .bold, design: .default)
                Text(headline(stage, at: now))
                    .scaledFont(12, weight: .heavy)
                    .monospacedDigit()
                if let detail = detail(stage) {
                    Text("· \(detail)")
                        .scaledFont(12, weight: .semibold)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(stage.tint)
            .accessibilityElement(children: .combine)
        } else {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: stage.systemImage)
                    .font(.title3)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 3) {
                    Text(stage.label.uppercased())
                        .scaledFont(11, weight: .heavy)
                        .kerning(1.1)
                        .opacity(0.75)
                    Text(headline(stage, at: now))
                        .scaledFont(19, weight: .heavy)
                        .monospacedDigit()
                    Text(subtitle(stage, at: now))
                        .scaledFont(13, weight: .medium)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 0)
                if flight.isDelayed, flight.phase != .cancelled {
                    Text("+\(max(flight.departureDelayMinutes, flight.arrivalDelayMinutes)) min")
                        .scaledFont(13, weight: .heavy)
                        .monospacedDigit()
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(bannerColor(stage).opacity(0.22), in: Capsule())
                }
            }
            // Tinted panel, same grammar as `StatusPill`: coloured text on a
            // faint fill of the same colour. White on the old solid fill was
            // ~2:1 on orange.
            .foregroundStyle(bannerColor(stage))
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(bannerColor(stage).opacity(0.14))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                         .strokeBorder(bannerColor(stage).opacity(0.35), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
            .accessibilityElement(children: .combine)
        }
    }

    /// The banner leans on delay colour over stage colour: on a flight page,
    /// "this is running late" outranks "this is boarding".
    private func bannerColor(_ stage: FlightStage) -> Color {
        switch stage {
        case .cancelled, .diverted: return Theme.red
        case .taxiingIn, .atGate, .arrived: return Theme.green
        default: return flight.isDelayed ? Theme.orange : stage.tint
        }
    }

    // MARK: - Wording

    /// The countdown when there's something to count down to, otherwise the
    /// stage itself. "Boards in 42m" beats "Boarding soon" — one of them tells
    /// you whether to get up.
    private func headline(_ stage: FlightStage, at now: Date) -> String {
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

    private func subtitle(_ stage: FlightStage, at now: Date) -> String {
        var parts: [String] = []
        switch stage {
        case .cancelled:
            return "Check with \(flight.airlineName) for rebooking"
        case .diverted:
            return "No longer routing to \(flight.destinationIATA)"
        case .scheduled, .checkInOpen, .boardingSoon, .boarding, .gateClosing:
            parts.append("\(flight.originIATA) departs \(Fmt.time(flight.bestDeparture, airportIATA: flight.originIATA))")
            if let gate = flight.departureGate {
                parts.append("gate \(gate)")
            } else {
                parts.append("gate not posted")
            }
        case .taxiingOut:
            parts.append("Left the gate at \(flight.originIATA)")
            parts.append("lands \(Fmt.time(flight.bestArrival, airportIATA: flight.destinationIATA))")
        case .airborne, .landingSoon:
            parts.append("\(Int(flight.progress(at: now) * 100))% of the way")
            parts.append("lands \(Fmt.time(flight.bestArrival, airportIATA: flight.destinationIATA)) at \(flight.destinationIATA)")
        case .taxiingIn:
            parts.append("On the ground at \(flight.destinationIATA)")
            if let gate = flight.arrivalGate { parts.append("gate \(gate)") }
        case .atGate, .arrived:
            parts.append("Landed \(Fmt.time(flight.bestArrival, airportIATA: flight.destinationIATA))")
            if let belt = flight.baggageClaim { parts.append("claim \(belt)") }
        }
        return parts.joined(separator: " · ")
    }

    /// The single most useful extra fact for the compact line.
    private func detail(_ stage: FlightStage) -> String? {
        switch stage {
        case .boardingSoon, .boarding, .gateClosing:
            return flight.departureGate.map { "Gate \($0)" } ?? "Gate TBA"
        case .atGate, .arrived:
            return flight.baggageClaim.map { "Claim \($0)" }
        case .taxiingIn:
            return flight.arrivalGate.map { "Gate \($0)" }
        default:
            return nil
        }
    }
}
