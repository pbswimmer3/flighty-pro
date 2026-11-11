# FlightDeck UI/UX review — App Store readiness

_Reviewed 2026-11-11 against branch `claude/app-store-prep` (HEAD `2d4db01`, screenshot harness already merged). Every view file under `FlightDeck/Views`, `Theme`, `RootTabView` and `FlightDeckApp` was read. Visual pass: the fresh harness captures in `docs/store/raw-before/` (iPhone Pro Max, 1320×2868, current build) first, the October `docs/screenshots/` (6.1-inch) for the smaller-width checks. Line numbers are from that commit._

Hard constraints every fix below respects: SwiftUI only, iOS 17 APIs (no `#available` needed anywhere), no new app dependencies, no change to stores/providers/forecaster beyond the two one-line edits called out, nothing that imitates Flighty, and nothing that restructures `FlightDeckApp.swift` or `RootTabView.swift` (one modifier is added to the latter, named exactly).

---

## 1. Verdict

The app is in good shape: an original dark identity, consistent card grammar, honest labelling of estimates, and strong copy on the flight page. What stands between it and an App Store listing is not the design, it is three gaps that every outside tester will hit in the first minute:

1. **A fresh install opens on four sample flights that are never labelled as samples** on the Flights, Passport or Connection tabs, with no welcome and no explanation of Demo Mode, the API key, or manual entry. Fixing this (banner + one-time welcome + "Sample" badges in Add Flight) is the single biggest win.
2. **Accessibility is at zero**: no `accessibility*` modifier anywhere, ~180 fixed-size fonts, tertiary text at 3.2:1, white-on-orange banners at 2.1:1, 38 pt map controls. A foundation package (`scaledFont`, contrast tokens, labels) lifts the whole app at once.
3. **Review red flags in plain sight**: the Settings footer names Flighty, the version string is hard-coded "1.1" against `MARKETING_VERSION = 1.0`, there is no privacy-policy link or MIT attribution for the airport data, and the app icon is a dashed arc that reads as empty at 60 pt.

---

## 2. Findings

Severity: **must** = block the TestFlight invite / listing; **should** = fix before listing; **nice** = polish.

| id | sev | screen | file:line | problem | fix |
|---|---|---|---|---|---|
| U1 | must | Global | every view (e.g. `FlightCard.swift:51`, `PassportComponents.swift:21`, `ArrivalForecastCard.swift:61`) | ~180 `.font(.system(size:…))` calls; nothing scales with Dynamic Type. A tester with Larger Text sees the same 10–12 pt captions. | Add `View.scaledFont(_:weight:design:relativeTo:)` backed by `@ScaledMetric` (P0), sweep every file (P1–P4), cap the app at `.xxxLarge` on `RootTabView` so untested layouts can't explode at AX sizes. |
| U2 | must | Global | `grep accessibility FlightDeck` → 0 hits | VoiceOver reads cards as loose fragments ("9:53 PM 10:18 PM San Francisco"), icon-only buttons are unnamed (`MyFlightsView.swift:38` "+", `AirportDetailView.swift:35` star, `FlightTrackingMapView.swift:660-666` follow/zoom, `:731` close), chevrons and decorative glyphs are read aloud. | Labels on every icon-only control, `.accessibilityElement(children: .combine)` + composed labels on cards/tiles, `.accessibilityHidden(true)` on chevrons, badges, bars. Per package below. |
| U3 | must | Global | `Theme.swift:17` | `textTertiary = white 0.35` on `#19191F` card ≈ 3.2:1 — fails AA for the 9–12 pt captions it is used on (`InfoCard.swift:46`, `PassportComponents.swift:26`, `ArrivalForecastCard.swift:64`, `LiveTrafficMapView.swift:364`). The struck-through old time on the card is in this colour. | `textTertiary = Color.white.opacity(0.48)` (≈ 4.9:1). No other change needed; the hierarchy survives. |
| U4 | must | Flight page / card | `FlightStageBar.swift:71-75` | Status banner: white text on solid orange/green/blue at 0.85 opacity. White on `#FF9E26` ≈ 2.1:1; the 13 pt subtitle fails even the large-text threshold. Visible in `detail.png`. | Tinted banner: fill `bannerColor.opacity(0.14)`, 1 pt `strokeBorder(bannerColor.opacity(0.35))`, headline + icon in `bannerColor`, subtitle in `Theme.textSecondary`. Same grammar as `StatusPill`. Spec in P0. |
| U5 | should | Global | `Theme.swift:47` (18), `PassportComponents.swift:40` (16), `PassportMapView.swift:86` (14), `ArrivalForecastCard.swift:190` (12), `LiveTrafficMapView.swift:354` (10), `AirportsView.swift:71` (10) | Corner radii are ad hoc per view. | Tokens `Theme.radiusCard = 18`, `radiusInner = 12`, `radiusChip = 10`; nested elements use `radiusInner`, chips/legends `radiusChip`. |
| U6 | should | Global | `FlightStageBar.swift:35,56` (ticks every second), `FlightTrackingMapView.swift:612`, `LiveTrafficMapView.swift:322`, `FlightMapView.swift:208`, `FlightCard.swift:103`, `InfoCard.swift:40`, `PassportComponents.swift:20` | Live-updating numbers use proportional digits, so "Boards in 3h 38m" and "4s ago" jitter horizontally each tick; time columns don't align. | `.monospacedDigit()` on every countdown, "ago", time and stat value `Text`. |
| U7 | should | Global | `FlightCard.swift:130,139`, `PastFlightsView.swift:155`, `DelayTrackerView.swift:151`, `FlightDetailView.swift:351` | `StatusPill` uppercases, so "Late 14m" becomes **LATE 14M** (reads as metres/months). | Pass "Late 14 min" / "+14 min" to pills. Mixed-case text elsewhere keeps "14m". |
| U8 | should | Global | `FlightTrackingMapView.swift:679` (38 pt), `:728-735` and `LiveTrafficMapView.swift:257-264` (close ×, no frame), `ArrivalForecastCard.swift:133`, `PassportComponents.swift:137,193`, `MyFlightsView.swift:117-131` | Tap targets under 44 pt. | `.frame(width: 44, height: 44)` on round buttons; `.frame(minHeight: 44).contentShape(Rectangle())` on text buttons/rows. |
| U9 | nice | Add Flight, Manual, Settings | `AddFlightView.swift:40`, `ManualFlightView.swift:44`, `SettingsView.swift:15` | `Form` draws the system grouped background (pure black) while every other screen is `#0B0B0F`; sheets flash a different black. | `.scrollContentBackground(.hidden).background(Theme.background)` on each `Form`. |
| U10 | must | My Flights, Passport, Connection | `FlightStore.swift:33-36` seeds `DemoFlightProvider.sampleFlights()`; nothing in `MyFlightsView.swift`, `PassportView.swift`, `ConnectionView.swift` says so | A brand-new tester sees "DL 482 SFO → JFK, Late 14 min" and "DL 4 JFK → LHR" as if they were real. The only Demo labels are buried in the forecast card and the Add Flight footer. | `DemoBanner` component (P0) at the top of the three tab scroll views; hidden in `ScreenshotMode`. |
| U11 | must | First run | none exists | No welcome. Nothing tells a tester what Demo Mode is, that the key is optional, or that they can add their own flight by hand (the keyless path that actually works for outsiders). | `WelcomeView` sheet shown once (`@AppStorage("hasSeenWelcome")`), presented from `MyFlightsView`. Spec in P1. |
| U12 | must | Add Flight | `AddFlightView.swift:78-89,183-204`; `DemoFlightProvider.swift:9-40` | In Demo Mode, searching **any** real number ("UA 123") returns a fabricated flight listed under "Results" with no marker. A tester will add it believing it's theirs. The manual-entry section only appears after typing (`:141`). | "Sample" pill on each result row when `isDemo`; footer copy rewrite; in Demo Mode show the manual section unconditionally, above Search. |
| U13 | should | First run | `SettingsView.swift:94-104` is the only place authorization is requested | Testers never discover alerts — the app's best feature after tracking — because nothing on the Flights tab asks. | `AlertsPromptCard` on My Flights when `notifications.authorization == .notDetermined`, dismissible (`@AppStorage("alertsPromptDismissed")`). Spec in P1. |
| U14 | should | Settings | `SettingsView.swift:18-24`; `SettingsStore.swift:58` | Turning Demo Mode off with an empty key silently stays in Demo. The footer doesn't say so. | Dynamic footer + a `LabeledContent("Status", …)` row: "Demo Mode", "Demo Mode (no key yet)", "Live — AeroDataBox". |
| U15 | should | Add Flight | `AddFlightView.swift:51` | "lookups return realistic simulated flights" is developer phrasing. | "Demo Mode is on, so any number you search returns a sample flight with made-up times. To add a real flight, use *Enter it yourself* below, or add a free AeroDataBox key in Settings." |
| U16 | should | My Flights / Flight page | `MyFlightsView.swift:65-71,108-114`; no equivalent in `FlightDetailView.swift` | Removing a flight is only possible via long-press context menu — undiscoverable; the flight page has no actions at all. | Toolbar `Menu` (ellipsis) on the flight page: Refresh, Remove Flight (with `confirmationDialog`). Keep the context menus. |
| U17 | should | Flight card | `FlightCard.swift:10-24,90-113` | Card is a `NavigationLink` whose children are read one by one; strikethrough carries no meaning to VoiceOver. | `.accessibilityElement(children: .combine)` on the card and an explicit `.accessibilityLabel` composed from the same values ("DL 482, Delta Air Lines, San Francisco to New York, Late 14 minutes, departs 10:18 PM, originally 9:53 PM, arrives 6:25 AM, lands in 3 hours 7 minutes"). |
| U18 | should | Flight card | `ProgressPlaneBar.swift` | No accessibility representation of progress. | `.accessibilityHidden(true)` (progress is in the card label), or `.accessibilityLabel("\(Int(progress*100))% of the way")` when used standalone. |
| U19 | nice | Empty states | `MyFlightsView.swift:136-167`, `PassportView.swift:330-351`, `PastFlightsView.swift:100-115`, `ConnectionView.swift:138-153` | Four hand-built empty states with slightly different spacing/sizes. iOS 17 has `ContentUnavailableView`. | Replace each with `ContentUnavailableView { Label(…) } description: { … } actions: { … }`; keep the same copy and buttons. |
| U20 | must | Flight page | `FlightDetailView.swift:87-99` | "Track this flight" chip: white 12 pt on `Theme.accent` ≈ 3.3:1. | `.background(.black.opacity(0.72), in: Capsule())` with `.foregroundStyle(Theme.accent)` — matches the "Estimated position" badge in the same header (`FlightMapView.swift:195-199`). |
| U21 | should | Flight page | `FlightDetailView.swift:281-284` | Timeline shows "~11:46 PM" and never explains the tilde. | Footnote under the timeline, `textTertiary`, 11 pt: "~ worked out from the schedule — boarding, gate close and bag times aren't published by the airline." |
| U22 | should | Flight page vs Airport page | `FlightDetailView.swift:445` ("54°") vs `AirportDetailView.swift:144` ("54°F") | Inconsistent temperature unit. | "°F" in both. |
| U23 | should | Flight page | `ArrivalForecastCard.swift:26-35,177-191` | The Demo "generated history" warning is the **last** element in the card, after the 42 pt percentage — the disclaimer follows the claim. | Render `simulatedWarning` directly under `header`, before `gauge`. |
| U24 | nice | Flight page | `FlightDetailView.swift:31-36` | "Flight removed" is a bare `Text`. | `ContentUnavailableView("Flight removed", systemImage: "airplane.circle", description: Text("It was deleted from your list."))`. |
| U25 | nice | Flight page | `FlightDetailView.swift:393-399` | Seat field has no Done key; keyboard is dismissed only by scrolling. | `.submitLabel(.done)`. |
| U26 | should | Tracking map, Airport traffic | `FlightTrackingMapView.swift:653-655`, `LiveTrafficMapView.swift:328-330` | Raw failure strings reach the status pill: "adsb.lol returned HTTP 503", "Unexpected response from adsb.lol". | In the view: `message.localizedCaseInsensitiveContains("retrying") ? message : "Live traffic unavailable right now"`. (Rate-limit text already says when it retries and should stay.) |
| U27 | nice | Tracking map | `FlightTrackingMapView.swift:841-857` | For a sample or hand-entered flight the own-aircraft card shows "ESTIMATED" and real ADS-B traffic around a plane that isn't there. | When `!flight.isLiveData`, prefix `ownSummary` with "Not a live flight — placed from the schedule · ". |
| U28 | should | Maps, Forecast, Passport | `LiveTrafficMapView.swift:364` (9 pt), `AirportTrafficView.swift:186` (10 pt), `ArrivalForecastCard.swift:64` (9 pt), `PassportMapView.swift:89` (9 pt), `PassportComponents.swift:167` (9 pt), `FlightTrackingMapView.swift:718` + `AirportTrafficView.swift:131` ("MLAT" 8 pt), `InfoCard.swift:46` + `PassportComponents.swift:26` (10 pt) | Text below the HIG 11 pt minimum. | Floor at 11 pt during the `scaledFont` sweep. |
| U29 | should | All maps | `FlightTrackingMapView.swift:198-227`, `LiveTrafficMapView.swift:64-82`, `FlightMapView.swift:83-107`, `PassportMapView.swift:51-72`, `AirportDetailView.swift:202-217` | The traffic `Canvas` is invisible to VoiceOver; users get MapKit's raw element. | `.accessibilityElement(children: .ignore)` + `.accessibilityLabel(...)` on the map container: tracking/traffic use the existing `statusText`; route map "Route map, SFO to JFK, aircraft 39% of the way"; Passport "Map of N airports and M routes"; airport map "Satellite map of JFK". |
| U30 | should | Passport | `PassportComponents.swift:155-181` | Weekday chart labelled "S M T W T F S" — two S's and two T's; no VoiceOver summary. | Use `Calendar.current.shortWeekdaySymbols` (always Sunday-first, matching `weekdayHistogram`); `.accessibilityElement(children: .ignore)` + label "Departures by day of week: Sunday 1, Monday 3, …". |
| U31 | should | Passport | `PassportComponents.swift:184-210` | Selected year chip: white 13 pt on accent ≈ 3.3:1; no selected trait; ~32 pt tall. | Selected: fill `Theme.accent.opacity(0.22)`, text `Theme.accent`, 1 pt `strokeBorder(Theme.accent.opacity(0.6))`; unselected unchanged. `.frame(minHeight: 44)`, `.accessibilityAddTraits(isSelected ? .isSelected : [])`. |
| U32 | nice | Delay tracker | `DelayTrackerView.swift:171-177` | Ad-hoc `Color(red: 1.0, green: 0.45, blue: 0.2)` outside Theme. | `..<30: Theme.orange`, `..<90: Theme.orange`, `default: Theme.red`. |
| U33 | nice | Passport, Delay tracker | `PassportComponents.swift:79-86`, `DelayTrackerView.swift:103-114` | Decorative bars are exposed to VoiceOver; the stacked breakdown bar has no label. | `.accessibilityHidden(true)` on `RankRow` bar; `.accessibilityLabel("On time \(n), delayed \(n), cancelled \(n)")` on the breakdown. |
| U34 | should | Airports | `AirportsView.swift:33-39` | A search with no match renders a blank screen. | `if results.isEmpty && !query.isEmpty { ContentUnavailableView.search(text: query) }`. |
| U35 | should | Airports | `SettingsStore.swift:40` (`?? ["SFO", "JFK", "LHR"]`), `AirportsView.swift:20-32` | New users see a "Favorites" section they never created; the "Featured Airports" header only appears when favourites exist. | Default favourites `[]`; show the "Featured Airports" header whenever `query.isEmpty`. |
| U36 | should | Airport page | `AirportDetailView.swift:223` | Time-zone row prints the IANA id "America/New_York". | `airport.timeZone.localizedName(for: .generic, locale: .current) ?? airport.tz` → "Eastern Time". |
| U37 | nice | Airport page, Flight page | `Metar.swift:68` | Ceiling "None" reads oddly ("Ceiling None", "None / CEILING"). | Return "Unlimited". |
| U38 | nice | Airport traffic | `AirportTrafficView.swift:160-162` | "±25 m" with no noun. | "±25 m accuracy". |
| U39 | must | Connection | `ConnectionView.swift:109-125`; wraps in the 6.1-inch `docs/screenshots/connection.png`, fits on the Pro Max capture | Menu pickers sit in a trailing `HStack` and wrap "DL 482 / SFO→JFK" onto two lines on the most common phone width. | `VStack(alignment: .leading, spacing: 4)`: caption, then `Picker(...).labelsHidden().frame(maxWidth: .infinity, alignment: .leading)`. Menu label `.lineLimit(1)`. |
| U40 | should | Connection | `ConnectionView.swift:163-164` | `StatusPill.scaleEffect(1.25)` rasterises the text. | `StatusPill(text:color:large: true)` (P0 adds `large`). |
| U41 | should | Connection | `ConnectionView.swift:223-224` | "Ruleset: International" is jargon. | `InfoRow(label: "Connection rule", value: "International · \(mct) min minimum")`; drop the separate MCT row or keep both — keep both, rename this one. |
| U42 | nice | Connection | `ConnectionView.swift:76-98` | Detected-connection row has no selected trait. | `.accessibilityAddTraits(selected ? .isSelected : [])`, `.accessibilityElement(children: .combine)`. |
| U43 | must | Settings | `SettingsView.swift:68` | "inspired by the look and feel of Flighty … Not affiliated with Flighty LLC" is the one user-visible Flighty mention. Guideline 4.1 bait; a disclaimer that names the competitor is worse than none. | Replace with the independent-app wording in P4. (Source comments at `Theme.swift:14`, `AirportEvent.swift:41`, `FlightChange.swift:138`, `Formatters.swift:4`, `FlightCard.swift:3`, `ProgressPlaneBar.swift:3` are not user-visible; leave or reword at leisure.) |
| U44 | must | Settings | `SettingsView.swift:64` vs `project.pbxproj:265` | Version hard-coded "1.1"; project is `MARKETING_VERSION = 1.0`, build 1. | Read `CFBundleShortVersionString` + `CFBundleVersion` from `Bundle.main`. |
| U45 | must | Settings | `SettingsView.swift:60-69` | No privacy-policy link, no acknowledgements. The world airport list is MIT-licensed (`scripts/build_world_airports.py:11`) and MIT requires the notice to ship. | "Privacy Policy" `Link` + "Acknowledgements" `NavigationLink` → new `AcknowledgementsView`; `docs/privacy-policy.md`. Spec in P4. |
| U46 | should | Settings | `SettingsView.swift:37-40,140-141` | "Observations stored", "Analysis window", "Alerts queued with iOS" are developer labels. | "Flights on record", "Looks back", "Scheduled alerts". |
| U47 | nice | Settings | only `AirportTrafficView.swift:185` carries it | The "not an air-traffic-control tool" safety line is absent from the flight tracking map and About. | Add one sentence to the About footer. |
| U48 | must | App icon | `Assets.xcassets/AppIcon.appiconset/AppIcon.png` | A dashed arc on a navy gradient: no figure, no silhouette, invisible at 60 pt, indistinguishable on a store page. | Regenerate: the app's own `AircraftGlyph` silhouette (original, already shipped) in white, heading north-east, over the blue dashed arc, on the navy gradient. Script + spec in P1. |
| U49 | nice | Passport | `PassportMapView.swift:71`; `raw-before/passport.png` | Apple's city labels ("San Jose", "Anaheim", "Las Vegas") compete with the route and the caption overlaps "Anaheim". | `.mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))` (iOS 17) and move the caption to `.topTrailing`. |
| U50 | nice | Tracking map | `FlightTrackingMapView.swift:698`; `raw-before/tracking.png` | `bottomPanel` reserves 92 pt for the floating tab bar; when the screen is shown without one (the standalone harness scene) the own-aircraft card floats 70 pt above the bottom edge. | Leave the padding (correct in the real app) and have the harness push the tracking scene inside the Flights tab instead — see §4. |

---

## 3. Work packages

Five packages. **P0 merges first** (it adds the tokens and components the others call); P1–P4 are then developed in parallel in separate worktrees and each compile-checks on Codemagic against `main` with P0 in it. File sets are disjoint.

### Shared vocabulary P0 adds (the others only *use* these — exact names and values)

```swift
// Theme.swift
static let textTertiary = Color.white.opacity(0.48)        // was 0.35
static let sample = purple                                 // semantic: "generated / demo" (matches the forecast warning)
static let radiusCard: CGFloat = 18
static let radiusInner: CGFloat = 12
static let radiusChip: CGFloat = 10

// View extension
func scaledFont(_ size: CGFloat,
                weight: Font.Weight = .regular,
                design: Font.Design = .rounded,
                relativeTo style: Font.TextStyle = .body) -> some View

// Components
struct DemoBanner: View            // no parameters; reads SettingsStore from the environment
struct StatusPill { ... var large: Bool = false }   // existing init gains one trailing parameter
```

**Mechanical sweep rule (applies in every package, to every file it owns):**

| before | after |
|---|---|
| `.font(.system(size: N, weight: W, design: .rounded))` | `.scaledFont(N, weight: W)` |
| `.font(.system(size: N, weight: W))` (no design) | `.scaledFont(N, weight: W, design: .default)` |
| `.font(.system(size: N))` | `.scaledFont(N, design: .default)` |
| `.font(Theme.codeFont(N))` | `.scaledFont(N, weight: .heavy)` |
| `.font(Theme.monoFont(N))` | `.scaledFont(N, weight: .semibold, design: .monospaced)` |
| `.font(Theme.monoFont(N, weight: W))` | `.scaledFont(N, weight: W, design: .monospaced)` |
| any `N < 11` | use `11` |
| `.font(.subheadline)`, `.font(.footnote)`, `.font(.caption)`, `.font(.title3)`, `.font(.headline)` | leave — already dynamic |
| fonts passed to `context.resolve(Text(...).font(...))` inside a `Canvas` | leave — `@ScaledMetric` can't live in a draw closure |

`.kerning`, `.strikethrough`, `.lineLimit`, `.monospacedDigit`, `.multilineTextAlignment` are all `View` modifiers on iOS 16+, so they may follow `.scaledFont(...)` unchanged. Add `.monospacedDigit()` to every `Text` that shows a time, countdown, "ago", count or stat value (U6). Keep `Theme.codeFont` / `Theme.monoFont` — the canvases still use them.

---

### P0 — Foundation: tokens, components, demo banner
**model:** `opus` **merge first**

**Owned files**
- `FlightDeck/Theme/Theme.swift`
- `FlightDeck/Views/Components/StatusPill.swift`
- `FlightDeck/Views/Components/InfoCard.swift`
- `FlightDeck/Views/Components/ProgressPlaneBar.swift`
- `FlightDeck/Views/Components/FlightStageBar.swift`
- `FlightDeck/Views/Components/AircraftGlyph.swift` (no change expected; owned so nobody else touches it)
- NEW `FlightDeck/Views/Components/DemoBanner.swift`
- `FlightDeck/RootTabView.swift` — **one line only**, see step 8

**Steps**

1. **Theme tokens (U3, U5).** Change `textTertiary` to `Color.white.opacity(0.48)`. Add `sample`, `radiusCard`, `radiusInner`, `radiusChip` as above. Change `CardBackground` to use `Theme.radiusCard`. Reword the comment on line 14 from "Flighty-ish blue" to "primary accent".
2. **`scaledFont` (U1).** Append to `Theme.swift`:
   ```swift
   /// Dynamic-Type-aware replacement for `.font(.system(size:weight:design:))`.
   /// `@ScaledMetric` scales the point size with the user's text size relative
   /// to `style`, so the default-size look is unchanged.
   struct ScaledSystemFont: ViewModifier {
       @ScaledMetric private var size: CGFloat
       private let weight: Font.Weight
       private let design: Font.Design

       init(size: CGFloat, weight: Font.Weight, design: Font.Design, relativeTo style: Font.TextStyle) {
           _size = ScaledMetric(wrappedValue: size, relativeTo: style)
           self.weight = weight
           self.design = design
       }

       func body(content: Content) -> some View {
           content.font(.system(size: size, weight: weight, design: design))
       }
   }

   extension View {
       func scaledFont(_ size: CGFloat,
                       weight: Font.Weight = .regular,
                       design: Font.Design = .rounded,
                       relativeTo style: Font.TextStyle = .body) -> some View {
           modifier(ScaledSystemFont(size: size, weight: weight, design: design, relativeTo: style))
       }
   }
   ```
   Convert `SectionHeader` (lines 66-71) with the sweep rule.
3. **`StatusPill` (U7, U40).** Add `var large: Bool = false` after `filled`. Font `scaledFont(large ? 13 : 11, weight: .heavy)`; padding horizontal `large ? 14 : 10`, vertical `large ? 7 : 5`. Add `.accessibilityLabel(text)` (un-uppercased, so VoiceOver gets "Late 14 min" not letter-spaced caps).
4. **`InfoCard.swift`.** Sweep. `StatBlock` caption 10 → 11. `StatBlock` value `.monospacedDigit()`. `StatBlock`: `.accessibilityElement(children: .combine)` and `.accessibilityLabel("\(caption): \(value == "—" ? "not posted" : value)")`. `InfoRow`: `.accessibilityElement(children: .combine)`; when `strikethroughValue` is set, `.accessibilityLabel("\(label): \(value), originally \(old)")`. `AirlineBadge`: `.accessibilityHidden(true)` (the airline name is always adjacent).
5. **`ProgressPlaneBar` (U18).** Add `var accessibilityHidden = true` default; apply `.accessibilityHidden(accessibilityHidden)` on the outer `GeometryReader`; when not hidden, `.accessibilityLabel("\(Int(clamped * 100)) percent of the way")`.
6. **`FlightStageBar` banner restyle (U4, U6).** In the non-compact branch replace lines 71-75 with:
   ```swift
   .foregroundStyle(bannerColor(stage))
   .padding(16)
   .frame(maxWidth: .infinity, alignment: .leading)
   .background(bannerColor(stage).opacity(0.14))
   .overlay(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                .strokeBorder(bannerColor(stage).opacity(0.35), lineWidth: 1))
   .clipShape(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
   ```
   Inside: stage label keeps `.opacity(0.75)` (it inherits the banner colour); headline stays in banner colour; subtitle `.foregroundStyle(Theme.textSecondary)` and drop its `.opacity(0.8)`; delay chip `.background(bannerColor(stage).opacity(0.22), in: Capsule())` with text in banner colour and `"+\(…) min"`. Headline and chip `Text` get `.monospacedDigit()`. Compact branch: headline `.monospacedDigit()`. Both branches: `.accessibilityElement(children: .combine)`.
7. **`DemoBanner.swift` (U10).** New file:
   ```swift
   import SwiftUI

   /// One line at the top of a tab that says the flights on it are samples.
   /// Shown whenever the app is effectively in Demo Mode (toggle on, or no
   /// key), hidden for store screenshots.
   struct DemoBanner: View {
       @EnvironmentObject private var settings: SettingsStore
       var text = "Demo Mode · these flights are samples with made-up times. Airport status, weather and live aircraft are real."

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
   ```
8. **`RootTabView.swift` — exactly one line.** Directly after `.background(Theme.background)` in `tabs`, add `.dynamicTypeSize(...DynamicTypeSize.xxxLarge)`. Touch nothing else in that file.

**Acceptance (self-check by reading code)**
- `Theme.swift` declares `textTertiary` 0.48, `sample`, three radius tokens, `ScaledSystemFont`, `View.scaledFont` with the exact signature above.
- `grep -n "\.system(size" FlightDeck/Theme FlightDeck/Views/Components` returns only the two `context.resolve` lines in `AircraftGlyph.swift` and the body of `ScaledSystemFont`.
- No `Text` in `Components/` uses a size below 11.
- `FlightStageBar` non-compact branch contains no `.foregroundStyle(.white)` and no `.opacity(0.85)` background.
- `StatusPill` has a `large` parameter and an `accessibilityLabel`.
- `DemoBanner.swift` compiles standalone with only `SettingsStore` and `ScreenshotMode` as dependencies.
- `RootTabView.swift` diff is exactly one added line.

---

### P1 — First run, My Flights, Add Flight, app icon
**model:** `opus`

**Owned files**
- `FlightDeck/Views/Flights/MyFlightsView.swift`
- `FlightDeck/Views/Flights/FlightCard.swift`
- `FlightDeck/Views/Flights/AddFlightView.swift`
- `FlightDeck/Views/Flights/ManualFlightView.swift`
- NEW `FlightDeck/Views/Flights/WelcomeView.swift`
- NEW `FlightDeck/Views/Flights/AlertsPromptCard.swift`
- `FlightDeck/Assets.xcassets/AppIcon.appiconset/AppIcon.png` (+ `Contents.json` unchanged)
- NEW `scripts/make_icon.py`

**Steps**

1. **Sweep** all four existing files with the mechanical rule; `.monospacedDigit()` on the two time `Text`s in `FlightCard.timeColumn`, the date/duration pair in `routeRow`, and `displayNumber`.
2. **`WelcomeView.swift` (U11).** New file, a `NavigationStack`-free sheet:
   - `@Environment(\.dismiss)`.
   - `VStack(spacing: 24)` inside a `ScrollView` so it survives large text: `Image(systemName: "airplane.circle.fill").scaledFont(72, design: .default).foregroundStyle(Theme.accent)`; `Text("Welcome to FlightDeck").scaledFont(28, weight: .heavy)`; `Text("Live tracking, arrival forecasts and a lifetime Passport for the flights you take.").scaledFont(15, weight: .medium).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)`.
   - Three feature rows (`HStack(alignment: .top, spacing: 14)`, icon in a 36 pt `Theme.cardElevated` rounded square, title 15 heavy, detail 13 medium secondary):
     - `airplane` — "Track your flight" — "Gates, delays, the aircraft on a map, and a countdown to boarding."
     - `chart.line.uptrend.xyaxis` — "See it coming" — "A forecast of how late you'll land, with its reasons shown."
     - `book.closed.fill` — "Keep a Passport" — "Miles, hours, airports and every minute lost to delays, built from your flights."
   - A sample-trip card in `Theme.sample` tint (same styling as `DemoBanner`, but `alignment: .top`, icon `wand.and.stars`, title "You're starting with a sample trip" 14 bold, body 13 medium secondary): "Demo Mode is on, so the flights you'll see are made up. Airport status, weather and live aircraft are always real. Add your own flights any time with *Add Flight → Enter it yourself*; for live lookups by flight number, add a free AeroDataBox key in Settings."
   - Primary button "Explore the sample trip": full width, `.frame(maxWidth: .infinity, minHeight: 50)`, `Theme.accent` fill, `.foregroundStyle(.black)` 17 heavy (black on accent ≈ 5.4:1), `Capsule()`. Calls `dismiss()`.
   - `.padding(24)`, `.background(Theme.background)`, `.presentationDragIndicator(.visible)`.
   - Every feature-row icon `.accessibilityHidden(true)`; rows `.accessibilityElement(children: .combine)`.
3. **Present it from `MyFlightsView`.** Add `@AppStorage("hasSeenWelcome") private var hasSeenWelcome = false` and `@State private var showingWelcome = false`. On the `NavigationStack`: `.onAppear { if !hasSeenWelcome && !ScreenshotMode.isActive { showingWelcome = true } }` and `.sheet(isPresented: $showingWelcome, onDismiss: { hasSeenWelcome = true }) { WelcomeView() }`. (Two `.sheet` modifiers on one view is fine; they are never presented together.)
4. **`AlertsPromptCard.swift` (U13).** New file. `@EnvironmentObject private var notifications: NotificationService`, `@EnvironmentObject private var store: FlightStore`, `@AppStorage("alertsPromptDismissed") private var dismissed = false`. Body renders only when `notifications.authorization == .notDetermined && !dismissed && !ScreenshotMode.isActive`: card (`cardStyle()`) with `bell.badge.fill` in `Theme.accent`, title "Get boarding and gate alerts" 15 heavy, body "Scheduled on your phone from your flight times — no account, no server." 13 medium secondary, then an `HStack` of `Button("Turn On")` (prominent: accent fill, black text, 40 pt tall capsule) calling `Task { _ = await notifications.requestAuthorization(); store.refreshNotificationSchedule() }`, and `Button("Not Now") { dismissed = true }` in accent text, `.frame(minHeight: 44)`. In `MyFlightsView`, place `AlertsPromptCard()` directly after the Today/Upcoming sections, before `pastFlightsLink`, only in the non-empty branch.
5. **`MyFlightsView` (U10, U8, U19, U2).** First child of the `LazyVStack` in the non-empty branch: `DemoBanner()`. "+" toolbar button: `.accessibilityLabel("Add Flight")`. "All N past flights" row: `.frame(minHeight: 44).contentShape(Rectangle())`, chevron `.accessibilityHidden(true)`. Replace `emptyState` and `allClearState` with `ContentUnavailableView` (same copy; actions: "Add Flight" prominent, "Load Sample Trip" plain). Keep the context menus.
6. **`FlightCard` (U7, U17).** Pill strings: `"Late \(n) min"`, `"Delayed \(n) min"`. Add `.accessibilityElement(children: .combine)` and `.accessibilityLabel(accessibilitySummary)` on the outer `VStack`, where `accessibilitySummary` joins: display number, airline name, "\(originCity) to \(destinationCity)", pill text, "departs \(bestDepTime)" + (changed ? ", originally \(schedTime)" : ""), "arrives \(bestArrTime)" + same, and the stage headline (compute via `flight.nextMilestone()` and `Fmt.countdown` exactly as `FlightStageBar.headline` does; duplicate the six-case switch, it is eight lines). Pass `accessibilityHidden: true` to `ProgressPlaneBar` (the default).
7. **`AddFlightView` (U9, U12, U15).** `Form` gets `.scrollContentBackground(.hidden).background(Theme.background)`. Footer copy per U15. When `isDemo`: render `manualSection` unconditionally and **before** the Search section (reorder the builder: `if isDemo { manualSection }` above, `if !isDemo { manualSection }` in its current place); in `resultRow`, when `isDemo` add `StatusPill(text: "Sample", color: Theme.sample)` before the `plus.circle.fill`; the "Results" section header becomes `"Sample results"` in demo. Manual section header in demo: "Add your real flight". Sample-trip button footer: "A showcase itinerary built around the current time: one flight in the air now, a JFK → LHR connection, tomorrow's flight, and a completed one. Everything on it is made up."
8. **`ManualFlightView` (U9, U1).** Form background as above. `.frame(width: 90)` on the IATA field → `.frame(minWidth: 90)`; `.frame(width: 60)` on the airline code → `.frame(minWidth: 60)`.
9. **App icon (U48).** Write `scripts/make_icon.py` (Pillow; dev-only tooling, not an app dependency; header comment says `pip install pillow`). It renders `FlightDeck/Assets.xcassets/AppIcon.appiconset/AppIcon.png` at 1024×1024, opaque sRGB, no alpha:
   - Background: vertical gradient `#0B0B0F` (top) → `#1B2450` (bottom), same as today.
   - Arc: the existing blue (`#4D8FFF`) dashed great-circle arc, stroke 22 px, dash 58/44, from (−60, 560) rising to apex (512, 330) and down to (1084, 560) — a quadratic Bézier sampled into segments; keep it behind the aircraft.
   - Aircraft: the `AircraftGlyph.halfOutline` points (copy the 11 `(x, y)` pairs verbatim from `AircraftGlyph.swift:21-33`, mirror for the left side), scaled so the fuselage is 560 px long, rotated 45° clockwise (nose to the upper right), centred at (512, 500), filled white, with a 10 px stroke in `#0B0B0F` at 55% so it separates from the arc, and a soft `#4D8FFF` halo (radius 300 px, 18% alpha) beneath it — the same halo the in-app map draws.
   - Also write a 180 px and a 60 px preview to `docs/screenshots/icon-preview-180.png` / `-60.png` so the owner can judge legibility; the silhouette must still read as an aircraft at 60 px.
   - Update `docs/screenshots/icon.png` from the new 1024 render (256 px).
   Tinted/dark icon variants are not needed for iOS 17 targets; skip them.

**Acceptance**
- `grep -c "\.system(size" ` on each owned Swift file → 0.
- `MyFlightsView` contains `DemoBanner()`, `AlertsPromptCard()`, a `WelcomeView` sheet gated on `hasSeenWelcome` and `ScreenshotMode.isActive`, and `ContentUnavailableView` for both empty states.
- `FlightCard` has `.accessibilityElement(children: .combine)` and no pill string ending in `"m"` after a number.
- `AddFlightView` in demo shows the manual section before Search and a "Sample" pill on result rows.
- `AppIcon.png` is 1024×1024, mode RGB (no alpha), regenerated by `scripts/make_icon.py`; previews exist.
- `WelcomeView` and `AlertsPromptCard` contain no `.font(.system(size:` and no `frame(width:)`.

---

### P2 — Flight page, forecast card, tracking and traffic maps
**model:** `opus`

**Owned files**
- `FlightDeck/Views/Flights/FlightDetailView.swift`
- `FlightDeck/Views/Flights/ArrivalForecastCard.swift`
- `FlightDeck/Views/Flights/FlightMapView.swift`
- `FlightDeck/Views/Flights/FlightTrackingMapView.swift`
- `FlightDeck/Views/Flights/LiveTrafficMapView.swift`
- `FlightDeck/Views/Airports/AirportTrafficView.swift`

**Steps**

1. **Sweep** all six files (rule above; canvases keep `context.resolve` fonts). Minimum 11 pt catches: `ArrivalForecastCard:64` ("CHANCE OF DELAY" 9 → 11), `FlightTrackingMapView:718` and `AirportTrafficView:131` ("MLAT" 8 → 11), `LiveTrafficMapView:364` (legend 9 → 11), `AirportTrafficView:186` (10 → 11), `FlightMapView:195` (10 → 11). `.monospacedDigit()` on: timeline row times, `StatBlock`s are already handled by P0, tracking status pill `Text`s, "ago" texts, `detailLine`/`ownSummary` texts, `FlightMapView.sourceBadge`.
2. **Flight page header chip (U20).** `FlightDetailView:95-98`: `.foregroundStyle(Theme.accent)`, `.background(.black.opacity(0.72), in: Capsule())`. Add `.accessibilityLabel(trackingPrompt(flight))` on the `NavigationLink`, and `.accessibilityHint("Opens the live map")`.
3. **Toolbar menu (U16).** Add `@State private var confirmRemove = false`. In `content(_:)` add
   ```swift
   .toolbar {
       ToolbarItem(placement: .topBarTrailing) {
           Menu {
               Button { Task { await store.refresh(flight); await loadIntel(flight) } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
               Button(role: .destructive) { confirmRemove = true } label: { Label("Remove Flight", systemImage: "trash") }
           } label: {
               Image(systemName: "ellipsis.circle").accessibilityLabel("Flight actions")
           }
       }
   }
   .confirmationDialog("Remove \(flight.displayNumber)?", isPresented: $confirmRemove, titleVisibility: .visible) {
       Button("Remove Flight", role: .destructive) { store.remove(flight) }
   } message: { Text("It leaves your Passport too — every stat is computed from your flights.") }
   ```
   `store.remove` already exists; the page then shows the "removed" state (step 5) until popped.
4. **Timeline footnote (U21).** After the `ForEach` in `timelineCard`: `Text("~ worked out from the schedule — boarding, gate-close and bag times aren't published by the airline.").scaledFont(11, weight: .medium).foregroundStyle(Theme.textTertiary).padding(.top, 8).fixedSize(horizontal: false, vertical: true)`. Each `timelineRow`: `.accessibilityElement(children: .combine)` with label "\(title), \(isEstimated ? "about " : "")\(time)\(done ? ", done" : "")"; the check icon `.accessibilityHidden(true)`.
5. **Removed state (U24).** Replace the bare `Text("Flight removed")` with `ContentUnavailableView("Flight removed", systemImage: "airplane.circle", description: Text("It was deleted from your list."))`.
6. **Weather unit (U22).** `FlightDetailView:445`: `"\(t)°F"`. `weatherRow`: `.accessibilityElement(children: .combine)`.
7. **Seat field (U25).** `.submitLabel(.done)`.
8. **Forecast card (U23, U8).** Move `if forecast.usesSimulatedHistory { simulatedWarning }` to directly after `header` in `body`. `simulatedWarning` uses `Theme.sample` (same colour, semantic name) and `Theme.radiusInner`; copy: "Demo Mode: this forecast is built from generated history, not real flights. With an AeroDataBox key it uses actual past performance." "What's driving this" button: `.frame(minHeight: 44).contentShape(Rectangle())`, `.accessibilityLabel(showingFactors ? "Hide what's driving this" : "Show what's driving this, \(forecast.factors.count) factors")`. Gauge: `.accessibilityElement(children: .combine)` on the `HStack` with label "\(percentText) chance of delay, \(riskLabel)". The bar `GeometryReader` `.accessibilityHidden(true)`.
9. **Tracking map (U8, U26, U27, U29).** `controlButton`: frame 44×44; add a `label: String` parameter and `.accessibilityLabel(label)` — "Follow aircraft" / "Stop following" (based on `isFollowing`), "Zoom in", "Zoom out". Close button in `selectedCard`: `.frame(width: 44, height: 44)` and `.accessibilityLabel("Dismiss")`. `statusText` `.failed` case per U26. `ownSummary`: when `!flight.isLiveData`, insert "Not a live flight — placed from the schedule" as the first part. Status pill `HStack` → `.accessibilityElement(children: .combine)`. On the `Map` (inside `MapReader`) add `.accessibilityElement(children: .ignore)` and `.accessibilityLabel("Live map. \(statusText). \(ownSummary)")`. `controls` bottom padding: unchanged values are fine. Add an `initialScope: Scope? = nil` parameter to `init(flight:tracker:initialScope:)`; when non-nil it overrides the airborne/ground choice (lets the screenshot harness open on Route — see §4).
10. **Live traffic map (U8, U26, U29).** Close button 44×44 + "Dismiss". `statusBar` `.failed` per U26. Legend `.accessibilityElement(children: .combine)`. `Map` → `.accessibilityElement(children: .ignore).accessibilityLabel("Live traffic map around \(centerLabel ?? "the airport"). \(statusSummary)")` where `statusSummary` is a small `String` computed from the same switch as `statusBar`.
11. **Flight map header (U29).** On the `Map`: `.accessibilityElement(children: .ignore).accessibilityLabel("Route map, \(flight.originIATA) to \(flight.destinationIATA)" + (badgeLabel.map { ". \($0)" } ?? ""))`.
12. **Airport traffic (U38).** `"±\(Int(accuracy)) m accuracy"`. Disclaimer 11 pt. Row `HStack` `.accessibilityElement(children: .combine)`.

**Acceptance**
- `grep -c "\.system(size"` → 0 in all six files except the `context.resolve` lines (`FlightTrackingMapView` none; `LiveTrafficMapView` none; `AircraftGlyph` is not owned).
- `FlightDetailView` has a toolbar `Menu` with Refresh + Remove, a `confirmationDialog`, a timeline footnote beginning with "~", `ContentUnavailableView` for the removed state, `"°F"`, and `.submitLabel(.done)`.
- `ArrivalForecastCard.body` order is `header`, warning (conditional), `gauge`, … .
- `FlightTrackingMapView.init` has an `initialScope` parameter; `controlButton` frames are 44; every `controlButton` call passes a label.
- No status text can contain "HTTP".
- Each of the four `Map`s has an `accessibilityLabel`.

---

### P3 — Passport, delay tracker, past flights
**model:** `sonnet`

**Owned files**
- `FlightDeck/Views/Passport/PassportView.swift`
- `FlightDeck/Views/Passport/PassportComponents.swift`
- `FlightDeck/Views/Passport/DelayTrackerView.swift`
- `FlightDeck/Views/Passport/PassportMapView.swift`
- `FlightDeck/Views/Passport/PastFlightsView.swift`

**Steps**

1. **Sweep** all five files. Minimums: `PassportComponents:26` (10 → 11), `:167` (9 → 11), `PassportMapView:89` (9 → 11). `.monospacedDigit()` on `PassportTile.value`, `RankRow` count, `WeekdayChart` counts, `PastFlightRow` duration and `displayNumber`, `DelayTrackerView` headline and legend counts, the month-group count in `PastFlightsView`.
2. **Radii (U5).** `PassportTile` is a top-level card → `Theme.radiusCard`; the map clip inside `PassportMapCard` → `Theme.radiusInner`.
3. **`DemoBanner` (U10).** First child of the `LazyVStack` in `PassportView` (above the `ScopePicker`), with `DemoBanner(text: "Demo Mode · this Passport includes sample flights. Add your own and the numbers are yours.")`.
4. **`ScopePicker` (U31, U8).** Selected style: `.background(isSelected ? Theme.accent.opacity(0.22) : Theme.cardElevated)`, `.foregroundStyle(isSelected ? Theme.accent : Theme.textSecondary)`, `.overlay(Capsule().strokeBorder(isSelected ? Theme.accent.opacity(0.6) : .clear, lineWidth: 1))`; button `.frame(minHeight: 44).contentShape(Rectangle())`; `.accessibilityAddTraits(isSelected ? .isSelected : [])`.
5. **`WeekdayChart` (U30, U33).** `private let labels = Calendar.current.shortWeekdaySymbols` (Sunday-first, matches `weekdayHistogram[0]`). Whole chart: `.accessibilityElement(children: .ignore).accessibilityLabel(summary)` where `summary = "Departures by day of week: " + zip(Calendar.current.weekdaySymbols, histogram).map { "\($0) \($1)" }.joined(separator: ", ")`.
6. **`RankRow` / `RankedCard` (U8, U33).** Bar `GeometryReader` `.accessibilityHidden(true)`; row `.accessibilityElement(children: .combine)` with label "\(rank). \(title), \(count) \(unit)" (+ subtitle if any). "Show all" button `.frame(minHeight: 44)`.
7. **`PassportTile`.** `.accessibilityElement(children: .combine)`; icon `.accessibilityHidden(true)`.
8. **`PassportView`.** Delay-tracker card chevron `.accessibilityHidden(true)`; the `NavigationLink` label `.accessibilityHint("Opens the delay tracker")`. Past-flights link row `.frame(minHeight: 44)`. Replace `emptyState` with `ContentUnavailableView` (same copy; action "Show all time" when `scope != .allTime`). The most-flown-aircraft circle icon `.accessibilityHidden(true)`.
9. **`DelayTrackerView` (U7, U32, U33).** Record pill text `"+\(record.minutes) min"`; `severityColor` per U32; breakdown bar `.accessibilityElement(children: .ignore).accessibilityLabel("On time \(onTime), delayed \(delayed), cancelled \(cancelled)")`; legend `.accessibilityHidden(true)` (duplicate of the bar label).
10. **`PassportMapView` (U29, U49).** On the `Map`: `.accessibilityElement(children: .ignore).accessibilityLabel("Map of \(stats.airports.count) airports and \(stats.routes.count) routes you've flown")`. Map style `.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false)`. Caption 11 pt, overlay alignment `.topTrailing`.
11. **`PastFlightsView` (U7, U19).** Pill `"+\(delayMinutes) min"`; `PastFlightRow` `.accessibilityElement(children: .combine)`; `emptyState` → `ContentUnavailableView`; `noResults` → `ContentUnavailableView.search(text: query)`.

**Acceptance**
- `grep -c "\.system(size"` → 0 in all five files.
- `WeekdayChart.labels` comes from `Calendar.current.shortWeekdaySymbols`.
- No `Color(red:` literal remains in `DelayTrackerView`.
- `PassportView` body starts with `DemoBanner`; `ScopePicker` selected chip has no `.white` foreground.
- Both pill strings in Passport end in " min".
- `ContentUnavailableView` used for Passport empty, Past Flights empty, and Past Flights no-results.

---

### P4 — Airports, Connection, Settings, privacy & acknowledgements
**model:** `sonnet`

**Owned files**
- `FlightDeck/Views/Airports/AirportsView.swift`
- `FlightDeck/Views/Airports/AirportDetailView.swift`
- `FlightDeck/Views/Connection/ConnectionView.swift`
- `FlightDeck/Views/Settings/SettingsView.swift`
- NEW `FlightDeck/Views/Settings/AcknowledgementsView.swift`
- `FlightDeck/Stores/SettingsStore.swift` — **line 40 only**
- `FlightDeck/Models/Metar.swift` — **one string, line 68**
- NEW `docs/privacy-policy.md`

**Steps**

1. **Sweep** the four view files. `.monospacedDigit()` on airport local-time texts, the METAR raw string is monospaced already (keep `design: .monospaced`), connection times/layover, Settings `LabeledContent` values (wrap the value in `Text(...).monospacedDigit()`).
2. **`AirportsView` (U34, U35, U2).** Show `SectionHeader(title: "Featured Airports", …)` whenever `query.isEmpty` (move it out of the favourites `if`; keep the Favorites header inside). After the results `ForEach`: `if results.isEmpty && !query.isEmpty { ContentUnavailableView.search(text: query) }`. `AirportRow`: `.accessibilityElement(children: .combine)`, chevron hidden, IATA tile radius `Theme.radiusChip`. **`SettingsStore.swift:40`**: `?? []` (default favourites empty). Nothing else in that file.
3. **`AirportDetailView` (U36, U37, U2, U29).** Time-zone row: `airport.timeZone.localizedName(for: .generic, locale: .current) ?? airport.tz`. Star button `.accessibilityLabel(settings.isFavorite(airport.iata) ? "Remove from Favorites" : "Add to Favorites")`. Map card `.accessibilityElement(children: .ignore).accessibilityLabel("Satellite map of \(airport.iata)")`. `statusLine` and the traffic card `.accessibilityElement(children: .combine)`; chevron hidden. **`Metar.swift:68`**: `return "Unlimited"`.
4. **`ConnectionView` (U39, U40, U41, U42, U10).** `flightPicker` → `VStack(alignment: .leading, spacing: 4) { Text(title)…; Picker(title, selection: selection) {…}.labelsHidden().pickerStyle(.menu).tint(Theme.accent).frame(maxWidth: .infinity, alignment: .leading) }` with each option `Text` `.lineLimit(1)`. `AssessmentCard`: `StatusPill(text:…, color:…, large: true)` and delete `.scaleEffect(1.25)`. Rename "Ruleset" row: label "Connection rule", value `"\(isInternational ? "International" : "Domestic") · \(minimumConnectionMinutes) min minimum"`; drop the separate "Minimum connection time" row. `detectedRow`: `.accessibilityElement(children: .combine)`, `.accessibilityAddTraits(selected ? .isSelected : [])`, border radius `Theme.radiusCard`. `DemoBanner()` as the first child in the non-empty branch. Empty state → `ContentUnavailableView`. Layover headline `.monospacedDigit()`.
5. **`SettingsView` — copy and structure (U9, U14, U43, U44, U45, U46, U47).**
   - `Form` background per U9.
   - Data Source section: add `LabeledContent("Status", value: statusText)` where `statusText` = `settings.demoMode ? "Demo Mode" : (settings.aeroDataBoxKey.isEmpty ? "Demo Mode (no key yet)" : "Live — AeroDataBox")`. Footer: `settings.demoMode ? "Demo Mode generates sample flights with no setup. Turn it off and add an AeroDataBox key below to track real flights." : settings.aeroDataBoxKey.isEmpty ? "Demo Mode stays on until an AeroDataBox key is added below." : "Live lookups are on. Flights you add by number come from AeroDataBox."`
   - Arrival forecast section labels: "Flights on record", "Looks back" (value "\(days) days").
   - Alerts: "Scheduled alerts".
   - About section:
     - `LabeledContent("Version", value: "\(short) (\(build))")` from `Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"` and `"CFBundleVersion"`.
     - `Link(destination: privacyPolicyURL) { Label("Privacy Policy", systemImage: "hand.raised.fill") }` with `private let privacyPolicyURL = URL(string: "https://github.com/pbswimmer3/flighty-pro/blob/main/docs/privacy-policy.md")!` and a `// TODO(owner): move to a hosted page before submission` comment.
     - `NavigationLink { AcknowledgementsView() } label: { Label("Acknowledgements", systemImage: "heart.text.square") }`.
     - Footer (replaces the Flighty sentence): "FlightDeck is an independent flight tracker. It has no account and no server; your flights stay on this device. Airport status comes from the FAA, weather from NOAA, live aircraft positions from the adsb.lol community network, and flight schedules from AeroDataBox when you add a key. Positions on maps are estimates — this is not an air-traffic-control tool and must never be used for navigation or separation. Not affiliated with any airline or data provider."
   - Every `Label` row keeps its symbol; add `.accessibilityHint` only to the destructive buttons ("Cannot be undone").
6. **`AcknowledgementsView.swift` (U45).** `List` on `Theme.background` (`.scrollContentBackground(.hidden)`), `.navigationTitle("Acknowledgements")`, inline. Sections: **Data sources** — one row each: FAA National Airspace System Status (nasstatus.faa.gov), NOAA Aviation Weather Center (aviationweather.gov), adsb.lol community ADS-B network, adsbdb.com (callsign routes), AeroDataBox (optional, with your key), Apple Maps; **Airport data** — "World airport list from mwgg/Airports, MIT License" followed by the full MIT licence text copied verbatim from https://github.com/mwgg/Airports/blob/master/LICENSE into a monospaced 11 pt `Text` (the implementer copies it; the owner verifies the copyright line); **Built with** — "SwiftUI, MapKit, SF Symbols. No third-party code."
7. **`docs/privacy-policy.md` (U45).** Plain-English policy, dated, covering: no account, no analytics, no data collected by the developer; flights, settings and the optional API key are stored only on the device (API key in app preferences); the app contacts FAA, NOAA, adsb.lol, adsbdb, Apple Maps and — only when a key is entered — AeroDataBox via RapidAPI, sending flight numbers, airport codes and the user's own key as needed; notifications are local; how to delete everything (Settings → Remove All Flights, or delete the app); contact: the GitHub repository issues page. Keep under 60 lines.

**Acceptance**
- `grep -in flighty FlightDeck/Views/Settings` → 0 hits.
- `grep -n '"1.1"' FlightDeck/Views/Settings/SettingsView.swift` → 0; `CFBundleShortVersionString` appears.
- `SettingsView` has a `Link` to the privacy policy, a `NavigationLink` to `AcknowledgementsView`, and the word "air-traffic-control" in the About footer.
- `AcknowledgementsView.swift` contains "MIT License" and "Permission is hereby granted".
- `docs/privacy-policy.md` exists.
- `ConnectionView` contains no `.scaleEffect`; `flightPicker` is a `VStack`.
- `AirportsView` contains `ContentUnavailableView.search`; `SettingsStore.swift` diff is exactly one line; `Metar.swift` diff is exactly one line.
- `grep -c "\.system(size"` → 0 in all owned Swift files.

---

## 4. Screens to capture for the App Store

All scenes run with `-FDScreenshot <scene>` (Demo Mode forced, welcome/banners/prompt hidden by `ScreenshotMode.isActive`). The demo trip is built relative to launch time, so every capture is consistent. Required device classes: 6.9" (1320×2868) and 6.5" (1284×2778 or 1242×2688). Order below is persuasion order for the listing page. Scene changes are described for the harness owner, not assigned to a UI package; `ScreenshotMode.swift`, `FlightDeckApp.swift` and `RootTabView.swift` stay with the harness.

What the current `raw-before` captures tell us: `detail`, `flights`, `connection`, `airports` and `settings` are already usable as-is once the UI packages land; `tracking` (Nearby scope over rural Wyoming, "No ADS-B coverage here", empty map) and `passport` (1 flight, 338 miles, one line on the map) are not, and need the harness changes in rows 3 and 5.

| # | scene (launch arg) | what's on screen | state to set | harness notes |
|---|---|---|---|---|
| 1 | `detail` | Flight page for DL 482 SFO → JFK (in the air): map header with the aircraft at ~39%, "IN THE AIR · Lands in 2h 5x m" banner, Arrival Forecast card (48 %, scheduled/forecast/late-by) | Scroll position top; forecast factors collapsed; no sheet | Exists. After P0 the banner is tinted; after P2 the Demo warning sits under the forecast header — acceptable, it is honest. |
| 2 | `flights` | My Flights: TODAY with DL 482 (Late 14 min, progress bar) and DL 4 JFK → LHR (On Time, "Boards in 3h"), UPCOMING peeking | Top of list | Exists. `DemoBanner` and `AlertsPromptCard` are hidden in screenshot mode. |
| 3 | `tracking` | Full-screen tracking map, **Route** scope: SFO–JFK arc across the continent, white own-aircraft glyph mid-route, status pill "N airborne · 0 on ground", own-aircraft card "DL 482 · SFO → JFK · ESTIMATED" | Route scope; nothing selected; follow on | Two harness changes: (a) pass `initialScope: .route` (P2 adds the parameter to `FlightTrackingMapView.init`) — the current Nearby capture is an empty field in Wyoming; (b) present the scene inside the real `tabs` (select Flights, push the map) rather than standalone, so the floating tab bar is there and the own-aircraft card's 92 pt bottom clearance (U50) looks intentional. Live traffic is real and non-deterministic; the Route radius (90 nm) around mid-continent usually has a handful of airborne contacts. |
| 4 | `connection` | Connection tab: detected SFO → JFK → LHR, pickers filled, RISKY · 1h 21m · gates B24 → A5 | Top | Exists. Picker wrapping is fixed by P4 (U39). |
| 5 | `passport` | Passport hero tiles (flights, miles, hours, airports), route map spanning the continent and the Atlantic, delay tracker row | Top; All Time selected | Exists but **weak with the stock demo trip** — the current capture reads "1 FLIGHT · 338 MILES · 1% of the way around the world" with a single LAX–SFO line. The harness should seed ~10 extra *past* flights in screenshot mode only (e.g. SFO–JFK ×3, SFO–LAX ×2, JFK–LHR, LHR–CDG, SFO–NRT, SEA–SFO, AUS–ORD; one 45-min delay, one 2 h delay, one cancellation; spread over the last 10 months; aircraft types and a couple of seats set). That is harness/demo-provider work, not a UI package. |
| 6 | `airports` | JFK airport page: 56 pt code, "Local time", LIVE STATUS Normal operations, Airport-Wide Traffic card, WEATHER with VFR pill | Top | Exists. Status/weather are live; prefer a capture when JFK is VFR. |
| 7 | `airportTraffic` (new) | `AirportTrafficView(airport: JFK)`, Ground scope: satellite imagery with taxiing aircraft, "Moving on the ground" list below | Ground scope, nothing selected | New standalone scene (`tab: nil`, push `AirportTrafficView` inside the `NavigationStack`). Capture 13:00–21:00 UTC on a weekday for a busy apron; retry if the status pill says "No ADS-B coverage". |
| 8 | `delays` (optional, new) | Delay Tracker: "4h 12m LOST TO DELAYS", on-time rate tile, breakdown bar, worst airlines | Top | Only worth it with the seeded history from scene 5. Standalone: `DelayTrackerView(stats: store.passport())`. |

Captions for the listing (one line each, matching the scenes): "Your flight, live, with a countdown to boarding" · "A forecast that shows its working" · "Every aircraft around you, on the map" · "Will you make the connection?" · "A Passport that writes itself" · "Airport status and weather, in plain English" · "Who's ahead of you on the taxiway".

---

## 5. Readiness red flags (for the submission phase)

1. **Privacy policy** — required in App Store Connect for every app. P4 writes `docs/privacy-policy.md` and links it; the owner must put it at a public URL (GitHub Pages if the repo is private) and paste the same URL into ASC. Privacy nutrition label: "Data Not Collected" is accurate (no analytics, no account); note that AeroDataBox requests carry the user's own key.
2. **Flighty wording** — U43 removes the only in-app mention. Keep "Flighty" out of the App Store name, subtitle, description and keywords too (Guideline 2.3.7 / 4.1). The README and docs can keep the attribution.
3. **App icon** — U48. A dashed arc will not pass the owner's own bar, and a reviewer may read it as a placeholder.
4. **iPad** — `TARGETED_DEVICE_FAMILY = "1,2"` (pbxproj lines 270, 301) with all iPad orientations enabled. Reviewers routinely test on iPad; none of the layouts have been seen there (full-width cards at 1024 pt, split `Form`s). Safest for v1: set `TARGETED_DEVICE_FAMILY = 1` in both configurations and remove the `INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad` lines (258, 289) — iPad then runs the iPhone layout in compatibility mode. Two-line pbxproj edit, owner's call.
5. **Reviewer can't test real lookups** — there is no demo account to give. The App Review notes must say: "Demo Mode is on by default and exercises every feature with a generated itinerary; airport status, weather and live traffic are real. Real flight lookups need the user's own free AeroDataBox key; manual entry works without one." Guideline 2.1 (app completeness) is satisfied by Demo Mode as long as it is labelled — which is what U10–U12 do.
6. **MIT attribution** — the bundled world airport list (mwgg/Airports) requires the licence notice to ship with the app. P4's Acknowledgements screen covers it (Guideline 5.2.1 / licence compliance).
7. **Purpose strings** — none required today: no location, camera, photos, contacts or tracking. Local notifications need no usage string. Keep it that way; any future "centre the map on me" feature needs `NSLocationWhenInUseUsageDescription`.
8. **Metadata hygiene** — `PRODUCT_BUNDLE_IDENTIFIER = com.personal.flightdeck` must match the App ID the owner registers; `MARKETING_VERSION = 1.0`, `CURRENT_PROJECT_VERSION = 1`; `ITSAppUsesNonExemptEncryption = NO` is already set (correct — HTTPS only).
9. **Sample data uses real airline names and flight numbers** (Delta 482, United 1613, Alaska 1042). Low risk once labelled "sample" (U10, U12); do not use airline logos — the monogram badge is correct.
10. **Safety wording** — the "not an air-traffic-control tool" line should appear in the About footer (U47) and in the App Store description, since the app shows live aircraft positions.
11. **Launch screen** — generated (`UILaunchScreen_Generation = YES`) with no background colour key, so it is system black; acceptable against `#0B0B0F`. A branded launch screen needs a pbxproj edit; skip for v1.
12. **API key in UserDefaults** — not a review issue, but say "stored on this device" (not "securely") in copy; Keychain is a later task.
