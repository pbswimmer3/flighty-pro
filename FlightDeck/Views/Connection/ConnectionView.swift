import SwiftUI

/// Connection Assistant: rates the layover between two of your flights using
/// live estimated times against the airport's minimum connection time.
struct ConnectionView: View {
    @EnvironmentObject private var store: FlightStore

    @State private var inboundID: UUID?
    @State private var outboundID: UUID?

    private var inbound: Flight? { store.flights.first { $0.id == inboundID } }
    private var outbound: Flight? { store.flights.first { $0.id == outboundID } }

    private var assessment: ConnectionAssessment? {
        guard let inbound, let outbound, inbound.id != outbound.id else { return nil }
        return ConnectionAssessment(
            inbound: inbound,
            outbound: outbound,
            airport: AirportDatabase.shared.airport(iata: inbound.destinationIATA))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    DemoBanner()
                    if store.flights.count < 2 {
                        emptyState
                    } else {
                        detectedSection
                        pickerCard
                        if let assessment {
                            if assessment.inbound.destinationIATA == assessment.outbound.originIATA {
                                AssessmentCard(assessment: assessment)
                            } else {
                                mismatchWarning
                            }
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(Theme.background)
            .navigationTitle("Connection")
            .onAppear(perform: autoSelect)
        }
    }

    /// Preselect the first detected connection so the tab is useful instantly.
    private func autoSelect() {
        guard inboundID == nil, let pair = store.detectedConnections.first else { return }
        inboundID = pair.inbound.id
        outboundID = pair.outbound.id
    }

    // MARK: Sections

    @ViewBuilder
    private var detectedSection: some View {
        let pairs = store.detectedConnections
        if !pairs.isEmpty {
            SectionHeader(title: "Detected Connections", systemImage: "sparkles")
                .padding(.top, 6)
            ForEach(Array(pairs.enumerated()), id: \.offset) { _, pair in
                Button {
                    inboundID = pair.inbound.id
                    outboundID = pair.outbound.id
                } label: {
                    detectedRow(pair)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func detectedRow(_ pair: (inbound: Flight, outbound: Flight)) -> some View {
        let selected = pair.inbound.id == inboundID && pair.outbound.id == outboundID
        return HStack(spacing: 12) {
            Image(systemName: "arrow.triangle.branch")
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(pair.inbound.originIATA) → \(pair.inbound.destinationIATA) → \(pair.outbound.destinationIATA)")
                    .scaledFont(15, weight: .heavy)
                Text("\(pair.inbound.displayNumber) connecting to \(pair.outbound.displayNumber)")
                    .scaledFont(12, weight: .medium)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            if selected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.green)
            }
        }
        .cardStyle(padding: 14)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                .strokeBorder(selected ? Theme.accent : .clear, lineWidth: 1.5))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var pickerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Choose Flights", systemImage: "hand.point.up.left")
            flightPicker(title: "First flight (arriving)", selection: $inboundID)
            flightPicker(title: "Second flight (departing)", selection: $outboundID)
        }
        .cardStyle()
    }

    private func flightPicker(title: String, selection: Binding<UUID?>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .scaledFont(13, weight: .medium)
                .foregroundStyle(Theme.textSecondary)
            Picker(title, selection: selection) {
                Text("None").lineLimit(1).tag(UUID?.none)
                ForEach(store.flights) { flight in
                    Text("\(flight.displayNumber) \(flight.originIATA)→\(flight.destinationIATA)")
                        .lineLimit(1)
                        .tag(UUID?.some(flight.id))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .tint(Theme.accent)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var mismatchWarning: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.orange)
            Text("These flights don't connect: the first arrives at \(inbound?.destinationIATA ?? "—") but the second departs \(outbound?.originIATA ?? "—").")
                .scaledFont(13, weight: .medium)
                .foregroundStyle(Theme.textSecondary)
        }
        .cardStyle()
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Track two flights to analyze a connection", systemImage: "arrow.triangle.branch")
        } description: {
            Text("Add both legs of your trip in the Flights tab. FlightDeck auto-detects connections and rates your layover risk live.")
        }
        .padding(.top, 40)
    }
}

// MARK: - Assessment card

private struct AssessmentCard: View {
    let assessment: ConnectionAssessment

    var body: some View {
        VStack(spacing: 16) {
            StatusPill(text: assessment.risk.rawValue, color: assessment.risk.color, large: true)
                .padding(.top, 6)

            Text(assessment.layoverDescription)
                .scaledFont(52, weight: .heavy)
                .foregroundStyle(assessment.risk.color)
                .monospacedDigit()
            Text("connection time at \(assessment.inbound.destinationIATA)")
                .scaledFont(13, weight: .medium)
                .foregroundStyle(Theme.textSecondary)
                .padding(.top, -10)

            Text(assessment.risk.explanation)
                .scaledFont(14, weight: .semibold)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal)

            Divider().overlay(Theme.separator)

            gateRow
            detailRows
        }
        .cardStyle()
    }

    private var gateRow: some View {
        HStack(spacing: 0) {
            StatBlock(caption: "Arrive gate",
                      value: assessment.inbound.arrivalGate ?? "TBD",
                      color: Theme.accent)
            Image(systemName: "figure.walk")
                .font(.title3)
                .foregroundStyle(Theme.textTertiary)
            StatBlock(caption: "Depart gate",
                      value: assessment.outbound.departureGate ?? "TBD",
                      color: Theme.accent)
        }
    }

    private var detailRows: some View {
        VStack(spacing: 4) {
            InfoRow(label: "Arrives \(assessment.inbound.destinationIATA)",
                    value: Fmt.time(assessment.inbound.bestArrival,
                                    airportIATA: assessment.inbound.destinationIATA))
            InfoRow(label: "Departs \(assessment.inbound.destinationIATA)",
                    value: Fmt.time(assessment.outbound.bestDeparture,
                                    airportIATA: assessment.outbound.originIATA))
            if assessment.terminalChange {
                InfoRow(label: "Terminal change",
                        value: "\(assessment.inbound.arrivalTerminal ?? "?") → \(assessment.outbound.departureTerminal ?? "?")",
                        valueColor: Theme.orange)
            }
            if assessment.bufferChangeMinutes != 0 {
                InfoRow(label: "Change vs. schedule",
                        value: changeText,
                        valueColor: assessment.bufferChangeMinutes < 0 ? Theme.orange : Theme.green)
            }
            InfoRow(label: "Connection rule",
                    value: "\(assessment.isInternational ? "International" : "Domestic") · \(assessment.minimumConnectionMinutes) min minimum")
        }
    }

    private var changeText: String {
        let delta = assessment.bufferChangeMinutes
        return delta < 0 ? "Lost \(-delta) min" : "Gained \(delta) min"
    }
}
