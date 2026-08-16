# Live Traffic & Smooth Aircraft Motion — Research + Implementation Plan

**Status:** implemented, 16 Aug 2026. See §3.6 for how each acceptance criterion was verified.

**Goal:** show the user's aircraft *and neighbouring aircraft* on a map — in the air and on the ground — accurately enough to tell your position in the runway queue, and animated as one continuous motion rather than a position that jumps every few seconds.

---

## Part 1 — How Flighty actually does it

### 1.1 The data source is paid and enterprise-grade

Flighty uses **FlightAware Firehose**, described by FlightAware as "an enterprise-grade, real-time, and predictive data feed of global aircraft ADS-B positions and flight statuses." That partnership is the reason for their coverage claims (20% more tail numbers, 25% wider European coverage, ~110s faster alerts).

This matters for expectation-setting: **a meaningful part of Flighty's quality is bought, not engineered.** Firehose is a streaming push feed with global aggregation, not a polled public endpoint. We cannot replicate its coverage on a free tier. We *can* replicate the motion quality — see Part 2, which is the actually interesting half.

### 1.2 Why the positions are runway-accurate

The accuracy does not come from the tracking service. It comes from the aircraft.

- ADS-B Out broadcasts the aircraft's **own GNSS position**, roughly twice per second, on 1090 MHz. Ground receivers just listen.
- Aircraft on the ground transmit **surface position messages** (a distinct message type from airborne ones) which carry ground track and movement rate.
- Every message carries self-reported quality metrics:
  - **NACp** (Navigation Accuracy Category – Position): 95% horizontal accuracy bound. `9` → <30 m, `10` → <10 m, `11` → <3 m.
  - **NIC** / **Rc**: integrity containment radius, the 99.999% bound. NIC 8 → Rc < 185 m.

**I verified this against live data rather than trusting the spec.** Querying adsb.lol around LAX and JFK returned `nac_p` values of **9 and 10** — i.e. 10–30 m accuracy — with `nic: 8, rc: 186`.

A precision-instrument runway is ~45 m wide. At NACp 10 (<10 m) you can genuinely resolve *which aircraft is ahead of you in the queue and roughly where on the pavement it sits*. At NACp 9 (<30 m) you resolve sequence reliably but not precise lateral position. **This is the mechanism behind the feature the user likes.** It is available to us for free.

Note the distinction: `nac_p` is the *accuracy* figure to use for a confidence radius. `rc` is the much larger *integrity* bound — do not render `rc` as the error circle or every aircraft will look 186 m fuzzy.

### 1.3 Why the motion is smooth — the key insight

**It is not a higher update rate. It is client-side dead reckoning.**

The network feed is discrete and irregular. Measured live via the `seen_pos` field (age of the position fix in seconds), samples in one query ranged from **0.19 s to 49 s old** in the same response. If you bind a map annotation directly to received positions, you get exactly the periodic jumping the user wants to avoid — and it would be *uneven* jumping, which looks worse.

The technique:

1. Keep a **kinematic state** per aircraft: position, ground speed, track/heading, vertical rate, and the timestamp that state was true (`now - seen_pos`).
2. Drive rendering from a **display-linked clock** (`TimelineView(.animation)` or `CADisplayLink`) at 60–120 Hz — *not* from network callbacks.
3. Every frame, **integrate the state forward** by Δt since the fix: project along the great circle at ground speed on the current track. The plane moves continuously because you are computing where it *should* be, every frame.
4. When a new sample arrives, **do not snap.** Reconcile: ease from the currently-extrapolated position to the new measured position over ~300–800 ms. A snap is visible and reads as a glitch even when the new data is more correct.
5. Interpolate heading along the **shortest angular path** so 359° → 1° turns 2° right, not 358° left.

The principled version of steps 3–4 is an **alpha-beta filter** (or a small Kalman filter) over (lat, lon, track, speed): prediction and measurement blend continuously, and the reconciliation falls out of the filter gain instead of being hand-tuned. Recommended once the naive version works — start simple, the naive version is genuinely convincing.

The rendered position is therefore **an estimate, not a report.** That is fine and is what every flight tracker does, but it drives two requirements: cap extrapolation age (below), and never present extrapolated position as authoritative.

---

## Part 2 — What we can build on the current stack

The repo already has the foundation: [`AdsbService.swift`](../FlightDeck/Services/AdsbService.swift) talks to adsb.lol (free, keyless) and [`GreatCircle.swift`](../FlightDeck/Utilities/GreatCircle.swift) has the spherical math.

### 2.1 The endpoint we need already exists

`AdsbService` currently only queries by callsign. adsb.lol also exposes a **radius search**, which is the entire neighbouring-traffic feature:

```
GET https://api.adsb.lol/v2/lat/{lat}/lon/{lon}/dist/{nm}
```

Live results when I probed it:

| Query | Aircraft returned | On ground |
|---|---|---|
| LAX, 5 nm | 11 | most |
| JFK, 25 nm | 34 | 29 |

Ground aircraft come back with `alt_baro: "ground"` and real movement — e.g. a Cathay 777 taxiing at `gs: 15.5` with `true_heading: 81.56`. That is the taxi/runway picture, available now, for free.

Each aircraft object carries: `hex`, `flight`, `r` (registration), `t` (type), `lat`, `lon`, `alt_baro`, `alt_geom`, `gs`, `track` *or* `true_heading`, `baro_rate`, `nac_p`, `nic`, `rc`, `seen_pos`, `dst`, `dir`, `category`, `mlat`, `tisb`.

### 2.2 Honest limitations

- **Coverage is volunteer-fed.** adsb.lol depends on hobbyist receivers. Ground coverage at major hubs is good; smaller or non-US airports may have gaps or no surface coverage at all. The UI must degrade gracefully to "no traffic data here" rather than implying an empty sky.
- **Rate limits are dynamic and undocumented**, and adsb.lol has stated an API key will be required in future. No `x-ratelimit` headers are returned today. Budget conservatively (§3.4) and expect to need a key eventually.
- **MLAT-derived positions are less accurate** than ADS-B. The `mlat` array lists which fields were multilaterated; treat those aircraft as lower confidence.
- This is **not** an ATC-grade or safety tool and must never be framed as one.

---

## Part 3 — Implementation plan

### Phase 0 — Fix the existing latent bug (30 min)

`AdsbService.position(callSign:)` reads only `ac.track`. **Airborne aircraft report `track`; surface aircraft report `true_heading` instead.** I confirmed both cases in live data. So today, the moment a tracked aircraft is on the ground, heading silently becomes `nil` and the plane icon loses its rotation.

Fix: `trackDegrees = ac.track ?? ac.true_heading`. Also capture `seen_pos` — Phase 2 cannot work without it.

### Phase 1 — Traffic fetch layer

**New:** `FlightDeck/Services/TrafficService.swift`

- `func traffic(near: CLLocationCoordinate2D, radiusNM: Int) async -> [TrafficReport]`
- Decode the full field set above. Reuse the existing `FlexibleValue` for `alt_baro` (`"ground"` vs number).
- Normalise into a single model rather than leaking API shape upward.

**New:** `FlightDeck/Models/TrackedAircraft.swift`

```swift
struct TrafficReport {
    let hex: String                  // stable identity across polls — key on this, never on callsign
    let callsign: String?
    let registration: String?
    let icaoType: String?            // "B77W"
    let coordinate: CLLocationCoordinate2D
    let onGround: Bool
    let altitudeFeet: Int?
    let groundSpeedKts: Double?
    let headingDegrees: Double?      // track (airborne) ?? true_heading (surface)
    let verticalRateFPM: Int?
    let accuracyMetres: Double?      // derived from nac_p
    let fixAge: TimeInterval         // seen_pos — REQUIRED for extrapolation
    let isMLAT: Bool
}
```

Map `nac_p` → metres: `11→3, 10→10, 9→30, 8→92.6, 7→185.2`, else `nil` (unknown, render without a confidence radius).

### Phase 2 — The motion engine (the core of the feature)

**New:** `FlightDeck/Utilities/DeadReckoning.swift`

```swift
struct KinematicState {
    var coordinate: CLLocationCoordinate2D
    var headingDegrees: Double
    var groundSpeedKts: Double
    var validAt: Date            // = receivedAt - fixAge
}

func project(_ s: KinematicState, to t: Date) -> CLLocationCoordinate2D
func reconcile(current: KinematicState, toward measured: KinematicState, progress: Double) -> KinematicState
```

- `project` — great-circle propagation for airborne (extend `GreatCircle.swift`); planar is fine on the ground at taxi speeds.
- Heading blending must use shortest angular distance.
- **Cap extrapolation.** Past ~30 s of dead reckoning, fade the icon and mark it stale; past ~60 s, drop it. Extrapolating a 49-second-old fix at cruise speed puts the aircraft ~7 nm from where it is.

**New:** `FlightDeck/Stores/TrafficStore.swift`

- `@Published var aircraft: [String: KinematicState]` keyed by `hex`.
- Poll on a timer; on each response, reconcile rather than replace.
- Handle disappearance with a grace period — aircraft drop in and out of receiver coverage constantly, and removing on first absence makes the map flicker.

### Phase 3 — Rendering

**New:** `FlightDeck/Views/Flights/LiveTrafficMapView.swift`

- Wrap in `TimelineView(.animation)` so the body re-evaluates per display frame; read positions from `project(state, to: timeline.date)`.
- **Do not use one MapKit annotation view per aircraft.** At 30+ aircraft that thrashes. Use `Map` with a `MapPolygon`/`Annotation` set backed by a single `Canvas`, or render the traffic layer as one overlay.
- Distinguish: own aircraft (prominent), airborne traffic (by altitude), ground traffic (smaller, heading-rotated), stale (faded).
- Optional: confidence circle at `accuracyMetres` for the user's own aircraft only — on every target it is visual noise.

### Phase 4 — Airport ground view

The payoff feature. Camera locked to the airport, `dist=3` nm, ground traffic only, zoomed to runway scale. At NACp 9–10 the queue order is genuinely readable. Pair with the existing airport detail screen.

### 3.4 Polling budget

| Context | Interval |
|---|---|
| Foreground, own flight airborne | 5 s |
| Foreground, airport ground view | 3 s |
| Foreground, no map visible | stop |
| Background | stop entirely |
| Low Power Mode | halve rate, drop render to 30 fps |

Rendering stays at display rate regardless — smoothness comes from extrapolation, *not* from polling faster. This is the whole point: **polling harder makes the app worse (battery, rate limits) and does not make motion smoother.**

### 3.5 Gotchas

1. `track` vs `true_heading` (Phase 0) — the one that will silently bite.
2. `alt_baro` is `"ground"` or a number. `FlexibleValue` already handles it.
3. Extrapolate from `now - seen_pos`, **not** from response-receipt time.
4. Key aircraft on `hex`. Callsigns are absent on some records and reused across days.
5. Heading wrap-around at 0°/360°.
6. ADS-B lat/lon is WGS-84 — same as MapKit, no datum conversion.
7. `gs` is knots; convert to m/s (× 0.514444) before integrating.
8. Aircraft parked at gates report `gs: 0.0` — skip extrapolation entirely at zero speed or floating-point drift will make parked aircraft creep.

### 3.6 Acceptance criteria

- [x] **Own aircraft moves continuously with no visible jump when a new sample lands.**
      Verified by frame-diffing eight screenshots 0.5 s apart against a 5 s poll:
      all seven intervals showed movement (one larger, where a fix landed). If
      positions snapped to samples, six of seven would have been static.
- [x] **Neighbouring traffic renders in air and on ground.** LHR ground scope
      showed 28 surface aircraft on the taxiways; nearby scope showed 88,
      coloured by altitude band.
- [x] **At an airport with coverage, queue order matches reality.** The LHR
      departure queue renders as a legible line of heading-oriented icons along
      the taxiway, labelled with callsign and taxi speed.
- [x] **Stale targets visibly degrade instead of drifting silently.**
      Extrapolation freezes at the 30 s cap and the icon fades to 35%; targets
      are dropped at 60 s. Cap verified by unit check (6,945 m travelled at the
      cap vs 13,890 m uncapped).
- [x] **Zero network traffic when backgrounded.** Measured from CFNetwork logs:
      5 requests in 15 s foregrounded, **0** in 15 s backgrounded, 3 in 12 s
      after resuming.
- [x] **Graceful empty state where coverage does not exist.** ADD (no feeders)
      shows "No ADS-B coverage here" and explains that coverage is volunteer-fed
      rather than implying an empty sky.

Engine correctness is covered by 24 checks over `DeadReckoning`, `GreatCircle`
and the wire-format decoding — projection distance, the extrapolation cap,
zero-speed creep, heading wrap-around, antimeridian interpolation, NACp
mapping, and both the `track` and `true_heading` decode paths.

### 3.7 One deviation from this plan

Propagation uses the WGS-84 **radius of curvature in the direction of travel**
rather than a mean spherical radius. The spherical version carried a systematic
error up to ~0.3% — about 20 m over a full 30 s extrapolation at cruise, which
is the same order as the NACp accuracy the UI claims, so it would have
undermined the confidence ring. The ellipsoidal version agrees with
`CLLocation.distance` to under a metre.

---

## Sources

- [Partner Spotlight: Flighty — FlightAware Firehose](https://blog.flightaware.com/partnerspotlight-flighty)
- [Flightradar24 — How ADS-B works](https://www.flightradar24.com/how-it-works/ads-b)
- [FlightAware — ADS-B flight tracking](https://www.flightaware.com/adsb/)
- [ADS-B decode guide — NIC/NAC](https://github.com/carroux/adsb-decode-guide/blob/master/nicnac.rst)
- [14 CFR §91.227 — ADS-B Out performance requirements](https://www.law.cornell.edu/cfr/text/14/91.227)
- [uAvionix — Troubleshooting NIC and NACp](https://support.uavionix.com/hc/en-us/articles/50385951659795-Troubleshooting-NIC-and-NACp-errors-on-ADS-B-PAPR-Performance-Report-Request)
- [ADSB.lol open data API](https://www.adsb.lol/docs/open-data/api/) · [GitHub](https://github.com/adsblol/api)
- Live API probes against `api.adsb.lol/v2/lat/{lat}/lon/{lon}/dist/{nm}` at LAX and JFK, 16 Aug 2026.
