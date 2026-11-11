# FlightDeck
My personal flight tracker for iPhone, built without a Mac.
**Now:** UI polish compiles on Codemagic. Store copy and screenshot cards are half done.
**Next:** Pick the store name: read "Name and subtitle" in [store-review.md](docs/store/store-review.md). ~5 min
Updated 2026-11-11

## Needs you
- [ ] **Pick the App Store name**: "FlightDeck - Flight Tracker" is already taken by another app. ~5 min
  1. Open docs/store/store-review.md, section 2
  2. Reply with your pick (recommended: "Overwing: Flight Tracker")
- [ ] **Say "continue" in a new Claude session**: the run stopped at the usage limit. ~1 min
  1. Open Claude in flighty-pro and say: "Continue the app-store-prep run from BRIEF.md"

## Later
- [ ] **Decide on outside testers**: public TestFlight link plus Apple's beta review. ~10 min
- [ ] **Host the privacy policy**: the app links to pbswimmer3.github.io/flighty-pro/privacy. ~10 min

## What changed
- ✅ **UI reworked across every screen.** Welcome sheet, sample-data labels, larger-text support, new icon.
- ✅ **It compiles.** Codemagic built the merged app first try.
- ✅ **Privacy manifest added.** Apple requires it for uploads.
- ⚠️ **Not seen on a phone yet.** Screenshots still being captured.
- ⚠️ **Store copy and cards unfinished.** Agents stopped at the usage limit.

## Decisions
- **2026-11-11 · iPhone-only for version 1** _(auto)_
  - Why: no layout was checked on iPad; reviewers test there.
  - Undo: TARGETED_DEVICE_FAMILY back to "1,2" in the Xcode project.
- **2026-11-11 · Work happens on branch claude/app-store-prep, not main** _(auto)_
  - Why: every push to main uploads a TestFlight build.
  - Undo: merge or close the pull request.

## More
- UI review: [docs/ui-review.md](docs/ui-review.md)
- Store plan: [docs/store/store-review.md](docs/store/store-review.md)
- Readme: [README.md](README.md)
