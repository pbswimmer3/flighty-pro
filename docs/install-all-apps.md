# Always-on iPhone setup: FlightDeck, Fiend, Ride Compare

Companion to [`install-on-iphone.md`](install-on-iphone.md) (FlightDeck detail).
Findings from reading each repo; nothing was built or run (no Mac in the cloud).

| App | Stack | Bundle ID in repo | Extras needing portal setup | Path to phone |
|---|---|---|---|---|
| FlightDeck (`flighty-pro`) | SwiftUI, iOS 17, no deps | `com.personal.flightdeck` | none | Xcode → TestFlight → Xcode Cloud |
| Fiend (`Fiend_Urge_Tracker`) | SwiftUI/SwiftData, iOS 17 | `com.fiendapp.fiend` | App Group `group.com.fiendapp.fiend`; widget target is **not** in the pbxproj | Xcode → TestFlight → Xcode Cloud |
| Ride Compare (`ride-compare`) | Expo SDK 57 / React Native, `app/` | `dev.ridecompare.app` (+ `.widget`) | App Group `group.dev.ridecompare.app`, Push, widget extension; EAS project already set (`owner: pradbiswas`) | EAS Build → TestFlight (EAS Submit) |

## Once, when Apple approves you
1. Enrollment "Active" at developer.apple.com → Account; note the **Team ID**
   (FlightDeck's `MMKLPPVX8S` is stale; Fiend/Ride Compare have none set).
2. Accept agreements (Account + App Store Connect → Business). Apple ID 2FA on.
3. iPhone: Settings → Privacy & Security → **Developer Mode** → On → reboot.
4. Install **TestFlight** from the App Store on the phone.
5. Mac with Xcode 16+ (needed for FlightDeck/Fiend first build; Ride Compare
   builds in EAS cloud, no Mac).

## FlightDeck
Follow `install-on-iphone.md` steps 3–5. Short form: set Team → Run on phone →
create App Store Connect app → Archive/Upload → Internal Testing group →
Xcode Cloud workflow on push to `main` → TestFlight.

## Fiend
1. `git clone https://github.com/pbswimmer3/Fiend_Urge_Tracker && open Fiend.xcodeproj`
2. Signing & Capabilities: Team = paid team, unique bundle ID (e.g.
   `com.<you>.fiend`). If you change it, also change the App Group in
   `Fiend.entitlements` and `FiendWidgets.entitlements` (and `WidgetBridge`)
   to `group.<new bundle id>`.
3. Run on phone to verify (⌘R). Location/speech/notification prompts expected.
4. Widgets (optional, paid account makes it possible): File → New → Target →
   Widget Extension `FiendWidgets`, add the repo's `FiendWidgets/` files, set
   its entitlements file, add **App Groups** to both targets with the same
   group. Then commit the updated pbxproj.
5. App Store Connect → New App (same bundle ID) → Archive → Upload →
   Internal Testing → Xcode Cloud (as FlightDeck §5). The widget extension
   must be in the archive for widgets to ship.
6. Counselor feature needs your own Anthropic API key entered in Settings
   (stored in Keychain; nothing to configure at build time).

## Ride Compare (Expo/EAS — no Mac required)
From the repo's `docs/STATE.md` owner checklist, plus TestFlight:
1. Windows/any PC: `npm install` at root, `npm i -g eas-cli`.
2. In `app/`: `eas login` (account `pradbiswas`), `eas init` (project id is
   already in `app.json`; commit any change), `eas device:create` and open the
   link on the iPhone (needed only for the internal/dev build).
3. `eas build -p ios --profile development` — let EAS manage certificates;
   approve App Groups + Push for **both** `dev.ridecompare.app` and
   `dev.ridecompare.app.widget`. Install from the build link, then
   `npx expo start --dev-client --tunnel` for development.
4. **For always-on (no PC):** add a production profile to `app/eas.json`
   (`"production": { "autoIncrement": true }`), run
   `eas build -p ios --profile production`, then `eas submit -p ios`
   (creates/uses the App Store Connect record; you'll be asked for an App
   Store Connect API key or Apple ID login). Add yourself to Internal Testing
   in TestFlight and install from the TestFlight app.
5. Caveat from the repo: native Swift modules (`ride-grpc`, `ride-cookies`)
   have never been compiled — the first EAS build may fail there; send the
   Swift errors back. Uber/Lyft/Waymo private-endpoint use is outside their
   ToS (repo notes this).
6. JS-only changes after that can ship with `eas update` only if you add
   `expo-updates` (not currently a dependency); otherwise rebuild + submit.

## Keeping them alive
- TestFlight builds expire after **90 days**. Xcode Cloud (FlightDeck, Fiend)
  rebuilds on any push to `main` — add a monthly reminder or scheduled
  trigger. For Ride Compare run `eas build --auto-submit` (or the build+submit
  pair) at least every ~2 months; EAS free tier has limited builds/month.
- Developer Program renews yearly ($99); lapse = TestFlight apps stop.
- Internal testing needs no App Review (up to 100 internal testers, your
  Apple ID counts).

## Not reviewed
Other Apple-looking repos (`iMessage-Insights-App` is TypeScript, likely
Mac-side) were not inspected; say which you want next.
