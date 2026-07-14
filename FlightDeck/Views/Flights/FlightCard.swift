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
        }
        .cardStyle()
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
            if phase.isAirborne {
                VStack(spacing: 1) {
                    Text("LANDS \(Fmt.relative(flight.bestArrival).uppercased())")
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.accent)
                }
            }
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
                }
                Text(Fmt.time(best, airportIATA: iata))
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(changed ? Theme.orange : Theme.textPrimary)
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

    private var statusInfo: (String, Color) {
        switch phase {
        case .cancelled: return ("Cancelled", Theme.red)
        case .diverted: return ("Diverted", Theme.red)
        case .enRoute:
            return flight.arrivalDelayMinutes > 10
                ? ("Late \(flight.arrivalDelayMinutes)m", Theme.orange)
                : ("En Route", Theme.accent)
        case .landed, .arrived: return ("Arrived", Theme.green)
        case .boarding: return ("Boarding", Theme.purple)
        case .scheduled:
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
