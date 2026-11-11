# FlightDeck: App Privacy answers

What to enter in App Store Connect → App Privacy. Checked against the code at HEAD of `claude/app-store-prep` on 2026-11-11.

## The answer

- **Data collection: "No, we do not collect data from this app."** The product page then shows **Data Not Collected**.
- **Tracking: No.** There is no App Tracking Transparency prompt and nothing to ask for.

## Why that is the true answer

Apple counts data as "collected" when it is sent off the device in a way that lets the developer or its partners access it beyond what is needed to answer the request in real time. Here:

| Fact | Where it is true |
| --- | --- |
| No server, no analytics, no crash reporting, no ads, no third-party SDK (zero dependencies) | `project.pbxproj` (no packages); Settings → Acknowledgements: "No third-party code." |
| No account or sign-in of any kind | no auth code anywhere in `FlightDeck/` |
| No location permission; no `NSLocation…` key, no `CLLocationManager` | grep of `FlightDeck/` and `project.pbxproj` |
| Notifications are local (`UNUserNotificationCenter`), scheduled on the device; no push token exists | `Services/NotificationService.swift` |
| Flights stored in `flights.json`, punctuality history in `delay-history.json` (Application Support) | `Stores/FlightStore.swift`, `Stores/DelayHistoryStore.swift` |
| Settings, favourite airports, alert choices and the AeroDataBox key stored in UserDefaults | `Stores/SettingsStore.swift` |
| Deleted with Settings → Remove All Flights / Clear Punctuality History, or by deleting the app | `Views/Settings/SettingsView.swift` |

## Every network request the app makes

All go straight from the phone to a public service. The developer never sees this traffic.

| Host | What is sent | Why |
| --- | --- | --- |
| `nasstatus.faa.gov` | nothing beyond the feed request | US airport delay programs and ground stops |
| `aviationweather.gov` | an airport code | METAR weather |
| `api.adsb.lol` | an aircraft callsign, or a latitude/longitude and radius around an **airport or the flight's own estimated position** (never the phone's location) | live aircraft positions |
| `api.adsbdb.com` | an aircraft callsign | route for a callsign |
| Apple Maps (MapKit) | map tiles for the area shown | maps; covered by Apple's own policy |
| `aerodatabox.p.rapidapi.com` | **only if the user adds a key:** flight number, date, and the user's own RapidAPI key | flight schedules and status |

Nothing in these requests identifies the user. The only user-provided value that leaves the device, the AeroDataBox key, goes to the user's own account at that service, which is the service the user signed up for.

Contrast with ride-compare, which had to declare data because it has user accounts and location: nothing like that exists here.

## Questionnaire walk-through

1. "Do you or your third-party partners collect data from this app?" → **No**.
2. Publish. No data types to select; the tracking question does not apply.

## Privacy manifest

Done. `FlightDeck/PrivacyInfo.xcprivacy` is in the project (commit `4bda8a2`; the project uses synchronized folders, so it is included in the build without a pbxproj entry):

- `NSPrivacyTracking` = false, no tracking domains
- `NSPrivacyCollectedDataTypes` = empty
- `NSPrivacyAccessedAPITypes` = UserDefaults, reason `CA92.1` (data only this app reads and writes)

**OWNER, after the next upload:** if App Store Connect still emails an ITMS-91053 warning, the manifest did not make it into the bundle; check it in Xcode's file inspector (Target Membership: FlightDeck).

## Privacy policy

`docs/privacy-policy.md` exists. **OWNER:** host it publicly and paste the URL into App Store Connect (App Information → Privacy Policy URL, and TestFlight → Test Information). Settings links `https://pbswimmer3.github.io/flighty-pro/privacy` (marked `TODO(owner)` in `SettingsView.swift`); make that page exist or change the constant so the two match.
