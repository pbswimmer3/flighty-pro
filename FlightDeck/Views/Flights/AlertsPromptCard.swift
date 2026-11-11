import SwiftUI

/// Asks for notification permission from the Flights tab.
///
/// Settings used to be the only place that asked, so testers never found the
/// alerts — boarding, gate close, landing, bags — which are the best thing the
/// app does after tracking. Shown only while iOS hasn't been asked yet; "Not
/// Now" hides it for good (Settings still has the switch).
struct AlertsPromptCard: View {
    @EnvironmentObject private var notifications: NotificationService
    @EnvironmentObject private var store: FlightStore
    @AppStorage("alertsPromptDismissed") private var dismissed = false

    var body: some View {
        if notifications.authorization == .notDetermined && !dismissed && !ScreenshotMode.isActive {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "bell.badge.fill")
                    .scaledFont(20, weight: .bold, design: .default)
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Get boarding and gate alerts")
                            .scaledFont(15, weight: .heavy)
                        Text("Scheduled on your phone from your flight times — no account, no server.")
                            .scaledFont(13, weight: .medium)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)

                    HStack(spacing: 16) {
                        Button {
                            Task {
                                _ = await notifications.requestAuthorization()
                                // Permission changes what can be scheduled;
                                // rebuild now rather than on the next mutation.
                                store.refreshNotificationSchedule()
                            }
                        } label: {
                            Text("Turn On")
                                .scaledFont(15, weight: .heavy)
                                .foregroundStyle(.black)
                                .padding(.horizontal, 20)
                                .frame(minHeight: 40)
                                .background(Theme.accent, in: Capsule())
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)

                        Button {
                            dismissed = true
                        } label: {
                            Text("Not Now")
                                .scaledFont(15, weight: .bold)
                                .foregroundStyle(Theme.accent)
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                Spacer(minLength: 0)
            }
            .cardStyle()
        }
    }
}
