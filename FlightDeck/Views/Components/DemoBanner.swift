import SwiftUI

/// One line at the top of a tab that says the flights on it are samples.
/// Shown whenever the app is effectively in Demo Mode (toggle on, or no
/// key), hidden for store screenshots.
struct DemoBanner: View {
    @EnvironmentObject private var settings: SettingsStore
    var text = "Demo Mode · these flights are samples with made-up times. Airport status, weather and live aircraft are real."

    /// Same rule as `SettingsStore.provider`: an empty key means Demo Mode
    /// even with the toggle off.
    private var isDemo: Bool { settings.demoMode || settings.aeroDataBoxKey.isEmpty }

    var body: some View {
        if isDemo && !ScreenshotMode.isActive {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "wand.and.stars")
                    .scaledFont(12, weight: .bold)
                    .accessibilityHidden(true)
                Text(text)
                    .scaledFont(12, weight: .semibold)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .foregroundStyle(Theme.sample)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.sample.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: Theme.radiusInner, style: .continuous))
            .accessibilityElement(children: .combine)
        }
    }
}

#Preview {
    DemoBanner()
        .padding()
        .background(Theme.background)
        .environmentObject(SettingsStore())
}
