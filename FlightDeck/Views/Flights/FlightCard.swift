import SwiftUI

/// The signature Flighty-style flight card: airline badge + flight number,
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
                    .font(Theme.monoFont(15))
                Text(flight.airlineName)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            statusPill
        }
    }

    private var routeRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(flight.originIATA)
                .font(Theme.codeFont(34))
            Image(systemName: "arrow.right")
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(Theme.textTertiary)
            Text(flight.destinationIATA)
                .font(Theme.codeFont(34))
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Fmt.dayAndDate(flight.scheduledDeparture,
                                    tz: AirportDatabase.shared.airport(iata: flight.originIATA)?.timeZone))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                Text(Fmt.duration(flight.duration))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
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
        let changed = abs(best.timeIntervalSince(scheduled)) > 5 * 60
        return VStack(alignment: alignment, spacing: 2) {
            HStack(spacing: 5) {
                if changed {
                    Text(Fmt.time(scheduled, airportIATA: iata))
                        .strikethrough()
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                Text(Fmt.time(best, airportIATA: iata))
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(changed ? Theme.orange : Theme.textPrimary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .rounded))
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
                ? ("Late \(flight.arrivalDelayMinutes)m", Theme.orange)
                : (stage.label, Theme.accent)
        case .taxiingIn, .atGate, .arrived: return ("Arrived", Theme.green)
        case .boarding, .gateClosing: return (stage.label, Theme.purple)
        case .scheduled, .checkInOpen, .boardingSoon:
            return flight.isDelayed
                ? ("Delayed \(flight.departureDelayMinutes)m", Theme.orange)
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
}
