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
            // The disclaimer comes before the claim, not after the 42 pt number.
            if forecast.usesSimulatedHistory { simulatedWarning }
            gauge
            arrivalRow
            confidenceRow
            if !forecast.factors.isEmpty { factorsSection }
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
                    .scaledFont(42, weight: .heavy)
                    .monospacedDigit()
                    .foregroundStyle(tint)
                Text("CHANCE OF DELAY")
                    .scaledFont(11, weight: .bold)
                    .kerning(1.1)
                    .foregroundStyle(Theme.textTertiary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(forecast.riskLabel)
                    .scaledFont(15, weight: .heavy)
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
                .accessibilityHidden(true)

                if let onTime = forecast.historicalOnTimeRate, forecast.sampleSize > 0 {
                    Text("Historically \(Fmt.percent(onTime)) on time")
                        .scaledFont(11, weight: .medium)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(forecast.percentText) chance of delay, \(forecast.riskLabel)")
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
                    .scaledFont(11, weight: .bold, design: .default)
                    .foregroundStyle(Theme.textTertiary)
                Text("Most likely between \(Fmt.time(forecast.earlyArrival, airportIATA: flight.destinationIATA)) and \(Fmt.time(forecast.lateArrival, airportIATA: flight.destinationIATA))")
                    .scaledFont(12, weight: .semibold)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
            }
        }
    }

    private var confidenceRow: some View {
        Text(forecast.basis)
            .scaledFont(11, weight: .medium)
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
                        .scaledFont(11, weight: .bold, design: .default)
                    Text("What's driving this")
                        .scaledFont(12, weight: .bold)
                    Spacer()
                    Text("\(forecast.factors.count)")
                        .scaledFont(11, weight: .semibold, design: .monospaced)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textTertiary)
                }
                .foregroundStyle(Theme.accent)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(factorsToggleLabel)

            if showingFactors {
                ForEach(forecast.factors) { factor in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: factor.icon)
                            .scaledFont(14, weight: .bold, design: .default)
                            .foregroundStyle(factor.raisesRisk ? Theme.orange : Theme.accent)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(factor.label)
                                .scaledFont(13, weight: .bold)
                            Text(factor.detail)
                                .scaledFont(11, weight: .medium)
                                .foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 4)
                        if factor.minutes != 0 {
                            Text(factor.minutes > 0 ? "+\(factor.minutes)m" : "\(factor.minutes)m")
                                .scaledFont(12, weight: .semibold, design: .monospaced)
                                .monospacedDigit()
                                .foregroundStyle(factor.minutes > 0 ? Theme.orange : Theme.green)
                        }
                    }
                }
            }
        }
    }

    private var factorsToggleLabel: String {
        showingFactors
            ? "Hide what's driving this"
            : "Show what's driving this, \(forecast.factors.count) factors"
    }

    private var simulatedWarning: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "testtube.2")
                .scaledFont(12, weight: .bold, design: .default)
                .foregroundStyle(Theme.sample)
                .accessibilityHidden(true)
            Text("Demo Mode: this forecast is built from generated history, not real flights. With an AeroDataBox key it uses actual past performance.")
                .scaledFont(11, weight: .medium)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.sample.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusInner, style: .continuous))
    }
}
