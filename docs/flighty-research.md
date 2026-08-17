# What Flighty actually does — research notes

Background for the Passport, tracking and arrival-forecast work. Gathered from
Flighty's own marketing and help pages (via search summaries — `flighty.com` is
unreachable from this build environment's egress proxy, so the primary pages
were read through search result summaries rather than fetched directly),
plus third-party reviews and press coverage. Treat exact stat wording as
approximate; the *shape* of the features is well corroborated across sources.

---

## 1. Passport

Flighty's Passport is a lifetime travel record with a per-year "year in review"
mode. Corroborated stats across sources:

| Stat | Have it? | Notes |
|---|---|---|
| Total flights | ✅ | |
| Total distance flown | ✅ | Flighty frames it as miles; we add "× around the world" |
| Total time in the air | ✅ | |
| Airports visited (count + map) | ✅ | |
| Countries visited | ✅ | Derived from the bundled airport DB |
| Airlines flown | ✅ | |
| Most-flown aircraft type | ✅ | Explicitly called out in Flighty's own copy |
| Most-flown individual airframe | ✅ | Flighty tracks tail numbers; we tally by registration |
| Oldest / newest aircraft flown | ❌ | Needs an airframe age database we don't bundle |
| Top seat | ✅ | User-entered — no API supplies it |
| Most-flown routes | ✅ | Direction-agnostic city pairs |
| Total hours delayed | ✅ | The delay tracker headline |
| Worst delay | ✅ | |
| Worst airline for delays | ✅ | Plus worst arrival airports, which Flighty doesn't surface |
| Domestic / international / long-haul counts | ✅ | |
| Longest and shortest flight | ✅ | |
| Day of week most flown | ✅ | |
| Route map as a heat map (thicker = more frequent) | ✅ | Line weight scales with frequency |
| Shareable stat cards | ❌ | Deliberately skipped — see "Not built" below |
| "Get Me Off This Plane" (scheduled arrival → actual disembark) | ❌ | Needs gate-in and door-open times; our providers give runway times |

Flighty publishes an aggregate year-in-review too (in 2025: 22M flights,
34B miles, 78M hours across its user base). That's a server-side product, not
an app feature, and is out of scope for a personal app.

## 2. Delay prediction

How Flighty describes it:

- **Machine learning** over aviation-authority data plus incoming-aircraft
  information. Sources named across coverage: ADS-B tracking, FAA ground delay
  programs, historical route performance, and weather.
- **The physical aircraft is the key signal.** Flighty tracks the airframe
  assigned to your flight and can flag a delay while it's still inbound from
  its previous city — claimed at up to 6 hours before the airline acknowledges
  it, and up to 25 hours of forward visibility on where your plane is.
- **Covers two of every three US delays**: late-arriving aircraft (#1 cause)
  and ATC/airspace mandates (#2), plus weather and ground stops.
- **Predicted times shown alongside official ones**, never replacing them.
- Claims **>95% accuracy**, and notifications carry the reason —
  e.g. "Delayed 45m. Due to late arriving aircraft from New York."

What we built instead, and why it's honest about the difference:

Flighty trains on a fleet-wide dataset we don't have. A personal app sees only
the user's own flights, which for a specific route is a handful of samples a
year — nowhere near enough to state a percentage. So `ArrivalForecaster`:

1. Starts from the published US baseline (~21% of arrivals 15+ min late).
2. Refines it through progressively narrower slices of a rolling 60-day
   history — origin airport → that airline at that airport → the route → that
   airline on that route → that airline, route and time of day — each tier
   shrunk toward the one below it in proportion to how little data it has.
   Six flights on your exact route move the number without overriding it.
3. Adjusts in log-odds for the same live signals Flighty names: late inbound
   aircraft, FAA ground stops / ground delay programs / arrival delays, and
   IFR-or-worse weather at either end.
4. Once airborne, stops guessing: the live estimate becomes the centre and the
   band narrows with flight progress.

The card always shows its sample size, its basis in plain English, and every
factor that moved the number — a bare percentage from a personal-scale dataset
would be unfalsifiable, which is worse than no percentage.

**Where the history comes from** is the honest weak point and is surfaced in
the UI: with an AeroDataBox key we backfill the same flight number across ~15
sampled past dates; in Demo Mode we generate deterministic synthetic history,
labelled as generated wherever it appears. Neither is a fleet-wide dataset.

## 3. Live map and tracking

- Tapping a flight opens flight details with a live map; the aircraft moves in
  real time along its route.
- Interactive detail: tapping a gate badge zooms the map to that gate.
- Flighty's tracking is oriented around *your flight*, not around airports —
  which is what prompted the rework here. Aircraft tracking used to require
  going through an airport page; it now hangs off the flight, with the airport
  view kept for the separate "what's happening at this field" question.

## 4. Things Flighty has that we still don't

Listed so the gaps are known rather than accidental:

- **Push notifications and Live Activities.** These need a paid Apple Developer
  account and a server; delay signals are computed in-app on refresh instead.
  This was already an explicit non-goal in `plan.md`.
- **Sharing cards.** Flighty's Passport is heavily oriented toward shareable
  images. Skipped deliberately: the value is social, and this is a
  personal-use app with no social surface.
- **Airframe age, seat maps, cabin class, fare class.** No bundled data source.
- **Airport delay *forecasting*** (predicting when an airport's delays will
  end). We show current FAA programs, not a forecast of their end.
- **Auto-import** from TripIt, calendar or email.
- **Amenity and terminal maps.**

## Sources

- [Flighty Passport help page](https://flighty.com/help/passport)
- [Flighty Passport product page](https://flighty.com/passport)
- [How Flighty predicts flight delays](https://flighty.com/help/delay-predictions)
- [The Points Guy — everything you need to know about Flighty](https://thepointsguy.com/travel-gear/everything-you-need-to-know-about-flighty-app/)
- [Going.com — Flighty app review](https://www.going.com/guides/flighty-review)
- [Thrifty Traveler — why Flighty is a must-have](https://thriftytraveler.com/reviews/flighty-pro-app/)
- [TechCrunch — Flighty can now predict delays using machine learning](https://techcrunch.com/2024/08/06/flightys-popular-flight-tracking-app-can-now-predict-delays-using-machine-learning/)
- [Techlicious — Flighty predicts when airport delays will end](https://www.techlicious.com/blog/flighty-flight-tracking-app-airport-delay-predictions/)
- [World Airline News — Flighty's first year-in-review global Passport report](https://worldairlinenews.com/2025/12/11/flighty-launches-its-first-year-in-review-global-passport-report-including-the-most-delayed-airlines-in-2025/)
- [9to5Mac — Flighty year-in-review features](https://9to5mac.com/2023/12/12/flighty-year-in-review-features/)
- [MacSources — Flighty app review](https://macsources.com/flighty-app-review/)

FlightDeck is an independent personal-use app. It is not affiliated with
Flighty LLC, and ships no Flighty artwork, code, or trademarked assets.
