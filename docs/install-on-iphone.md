# Getting FlightDeck (and other personal apps) onto your iPhone — permanently

Findings from the repo: SwiftUI, iOS 17+, zero dependencies, no backend, no
entitlements/capabilities, Automatic signing, bundle ID `com.personal.flightdeck`,
and a hard-coded `DEVELOPMENT_TEAM = MMKLPPVX8S` (an old/personal team — you
will replace it, see step 3). Demo Mode works with no API key.

## Why TestFlight is the "always running" path

| Route | Lasts | Needs Mac each time? |
|---|---|---|
| Free Apple ID, Xcode install | 7 days | yes |
| Paid program, Xcode install | ~1 year (dev profile) | yes, to rebuild |
| **Paid program, TestFlight** | **90 days per build, auto-renewed by a new build** | **no (with Xcode Cloud)** |

Recommended: Xcode install first to verify, then TestFlight + Xcode Cloud so
every push to `main` builds and lands on your phone with no Mac.

## 1. Finish Apple Developer enrollment
1. developer.apple.com → Account → confirm status "Active" ($99/yr, individual).
2. Note your **Team ID** (Membership details). It will differ from `MMKLPPVX8S`.
3. Turn on 2FA for your Apple ID (required) and accept any new agreements
   (Account → Agreements, and App Store Connect → Business).

## 2. Phone prep
Settings → Privacy & Security → **Developer Mode** → On → reboot → confirm.
Plug in via USB and tap **Trust**.

## 3. First install via Xcode (needs a Mac, Xcode 16+)
1. `git clone https://github.com/pbswimmer3/flighty-pro && open FlightDeck.xcodeproj`
2. Target **FlightDeck → Signing & Capabilities**: tick *Automatically manage
   signing*, set **Team** to your new paid team (this overwrites `MMKLPPVX8S`).
3. If Xcode says the bundle ID is unavailable, change it to something unique,
   e.g. `com.<yourname>.flightdeck`.
4. Pick your iPhone as the run destination → **Run (⌘R)**.
5. Open the app: Demo Mode is on by default. For real data, Settings → add an
   AeroDataBox (RapidAPI) key.

## 4. Make it permanent: TestFlight
1. appstoreconnect.apple.com → Apps → **+ New App**: iOS, name, primary
   language, bundle ID (from step 3), any SKU.
2. Xcode: set destination *Any iOS Device (arm64)* → Product → **Archive** →
   Distribute App → **TestFlight & App Store** → Upload.
3. App Store Connect → TestFlight → wait for "Processing" to finish; answer
   the export-compliance question (app uses only standard HTTPS → "No"
   proprietary encryption; or add `ITSAppUsesNonExemptEncryption = NO` to the
   target's Info keys to skip it every time).
4. TestFlight → **Internal Testing** → create a group, add your Apple ID,
   enable automatic distribution. Internal builds need **no App Review**.
5. On the iPhone install the **TestFlight** app, accept the invite, Install.

## 5. Automate with Xcode Cloud (no Mac afterwards)
1. Xcode → Product → Xcode Cloud → Create Workflow; grant it access to the
   GitHub repo (install the Xcode Cloud GitHub app when prompted).
2. Start condition: push to `main`. Action: **Archive – iOS**. Post-action:
   **TestFlight Internal Testing**. (25 compute hrs/month are included.)
3. Bump `CURRENT_PROJECT_VERSION`? Not needed — Xcode Cloud sets the build
   number automatically.
4. Builds expire after 90 days. Re-run the workflow (or push anything) at
   least every ~2 months. Tip: add a calendar reminder or a monthly scheduled
   trigger in Xcode Cloud.

## 6. Other Apple app repos
Each app repo has its own guide at `docs/install-on-iphone.md`:
[Fiend](https://github.com/pbswimmer3/Fiend_Urge_Tracker/blob/claude/build-fiend-ios-app-Mv1ZC/docs/install-on-iphone.md)
(same Xcode → TestFlight → Xcode Cloud path, plus App Group and widget
setup) and
[Ride Compare](https://github.com/pbswimmer3/ride-compare/blob/main/docs/install-on-iphone.md)
(Expo: EAS Build → TestFlight, no Mac needed).

For any other repo, repeat steps 3–5 (each needs its own unique bundle ID and its own
App Store Connect app record). Check each for capabilities that need
portal setup (Push, iCloud, App Groups, Widgets, Sign in with Apple); Xcode's
automatic signing registers these for you once the paid team is selected.
If a repo uses XcodeGen/Tuist/SwiftPM, run its generate step before opening.

## Troubleshooting
- "Untrusted Developer" after install: Settings → General → VPN & Device
  Management → trust (Xcode installs only; TestFlight doesn't need this).
- "No account for team": Xcode → Settings → Accounts → re-add Apple ID.
- Enrollment still pending: you can only use the 7-day free route until it's
  Active; TestFlight requires the paid program.
