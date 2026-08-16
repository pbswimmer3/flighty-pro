import SwiftUI

/// The arrival forecast: a probability, a predicted arrival with a band around
/// it, and the evidence behind both.
///
/// The evidence list is not decoration. A bare "38% chance of delay" is
/// unactionable and, worse, unfalsifiable — showing which flights and which
/// live conditions produced it is what makes the number worth trusting or
/// dismissing.
struct ArrivalForecastCard: View {
    let flight: Flight
    let forecast: ArrivalForecast

    @State private var showingFactors = false

    private var tint: Color {
        switch forecast.probability {
        case ..<0.15: return Theme.green
        case ..<0.30: return Theme.accent
        case ..<0.50: return Theme.orange
        default: return Theme.red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            gauge
            arrivalRow
            confidenceRow
            if !forecast.factors.isEmpty { factorsSection }
            if forecast.usesSimulatedHistory { simulatedWarning }
        }
        .cardStyle()
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            SectionHeader(title: "Arrival Forecast", systemImage: "chart.line.uptrend.xyaxis")
            StatusPill(text: forecast.confidence.label, color: confidenceColor, filled: false)
        }
    }

    private var confidenceColor: Color {
        switch forecast.confidence {
        case .none: return Theme.textTertiary
        case .low: return Theme.orange
        case .medium: return Theme.accent
        case .high: return Theme.green
        }
    }

    // MARK: - Probability

    private var gauge: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(forecast.percentText)
                    .font(.system(size: 42, weight: .heavy, design: .rounded))
                    .foregroundStyle(tint)
                Text("CHANCE OF DELAY")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .kerning(1.1)
                    .foregroundStyle(Theme.textTertiary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(forecast.riskLabel)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.09))
                        Capsule().fill(tint)
                            .frame(width: max(geo.size.width * forecast.probability, 4))
                    }
                }
                .frame(height: 6)

                if let onTime = forecast.historicalOnTimeRate, forecast.sampleSize > 0 {
                    Text("Historically \(Fmt.percent(onTime)) on time")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }

    // MARK: - Predicted arrival

    private var arrivalRow: some View {
        VStack(spacing: 8) {
            HStack(spacing: 0) {
                StatBlock(caption: "Scheduled",
                          value: Fmt.time(flight.scheduledArrival, airportIATA: flight.destinationIATA))
                StatBlock(caption: "Forecast",
                          value: Fmt.time(forecast.predictedArrival, airportIATA: flight.destinationIATA),
                          color: forecast.expectedDelayMinutes >= Flight.delayThresholdMinutes
                                 ? Theme.orange : Theme.green)
                StatBlock(caption: forecast.expectedDelayMinutes >= 0 ? "Late by" : "Early by",
                          value: "\(abs(forecast.expectedDelayMinutes))m",
                          color: forecast.expectedDelayMinutes >= Flight.delayThresholdMinutes
                                 ? Theme.orange : Theme.textPrimary)
            }

            HStack(spacing: 6) {
                Image(systemName: "arrow.left.and.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
                Text("Most likely between \(Fmt.time(forecast.earlyArrival, airportIATA: flight.destinationIATA)) and \(Fmt.time(forecast.lateArrival, airportIATA: flight.destinationIATA))")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
            }
        }
    }

    private var confidenceRow: some View {
        Text(forecast.basis)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(Theme.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Evidence

    private var factorsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showingFactors.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: showingFactors ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                    Text("What's driving this")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                    Spacer()
                    Text("\(forecast.factors.count)")
                        .font(Theme.monoFont(11))
                        .foregroundStyle(Theme.textTertiary)
                }
                .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)

            if showingFactors {
                ForEach(forecast.factors) { factor in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: factor.icon)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(factor.raisesRisk ? Theme.orange : Theme.accent)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(factor.label)
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                            Text(factor.detail)
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 4)
                        if factor.minutes != 0 {
                            Text(factor.minutes > 0 ? "+\(factor.minutes)m" : "\(factor.minutes)m")
                                .font(Theme.monoFont(12))
                                .foregroundStyle(factor.minutes > 0 ? Theme.orange : Theme.green)
                        }
                    }
                }
            }
        }
    }

    private var simulatedWarning: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "testtube.2")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.purple)
            Text("Demo Mode: this forecast is built from generated history, not real flights. Add an AeroDataBox key in Settings to forecast from actual past performance.")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.purple.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
