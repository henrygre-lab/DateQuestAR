# Serendipity — Project Status (August 5, 2026)

## Build Status
- [x] Clean build succeeds against the iOS 26.5 SDK (verified August 5)
- [x] All Firebase modules resolved
- [x] Info.plist + Signing + @main entry point correct
- [x] AlertCapManager, BalanceEnforcer, and core safety features compile
- [x] Waves 1–2 of the rework are committed (`8891383`, July 29)
- [ ] Not run on device or simulator since the UI rework — see below

One warning survives the build, deliberately: `OpenURLOptionsKey` is deprecated
in iOS 26, and migrating off it means moving URL handling into a scene delegate
on the auth-critical Google Sign-In path. The call site carries a comment saying
so. Everything else is clean.

## Latest: Liquid Glass + logging (August 5)

**Liquid Glass.** The app deploys to iOS 26.2, so the frosted surfaces the spec
described in CSS terms are now the platform material. Adopted on chrome that
floats above content — the tab bar, icon buttons, over-photo chips, the
over-photo reveal meter, the chat composer, and the HUD controls over the AR and
liveness camera feeds — and deliberately kept off the content layer. Full
before/after table in [`UI_REWORK_STATUS.md`](UI_REWORK_STATUS.md) §0; the rule
and its consequences are now spec, in `DESIGN_SYSTEM.md` §5 and §8.

**Logging.** 55 `print` calls across 14 files moved onto `os.Logger` via
`Utilities/Log.swift`. `print` is not compiled out of release builds, and those
calls between them carried a user's geohash, a match's display name and a
reported user's uid — which is the security checklist's §01 rule ("remove all
`print` statements that expose internals in production builds") going unenforced
on the exact data the product exists to protect. Messages are now marked
`.private`, so they read under Xcode and redact everywhere else.

## Current phase: DesignSystem v2 UI rework

Replacing the v1 purple/mono token layer with the ember, photo-forward v2 system
from the design handoff. Functionality is unchanged throughout: the reveal
mechanic, stage machine, trust ladder and `#if DEBUG` demo path all behave
exactly as before.

**27 of 46 view files are now on v2; 17 still read `enum DQ`.**

**Wave 2 — forms, auth & system chrome (newest):** a second handoff drop added a
form vocabulary to the spec, plus Radar and Settings mocks. `DQFormParts` (1,005
lines, 20 components) implements it: rows, groups, fields, text areas, toggles,
steppers, sliders, segmented pickers, top bars, step dots, empty states,
skeletons, danger rows, confirm sheets and a blocking-save overlay. Migrated on
top of it: `SettingsView`, `AddPauseZoneView`, `ReportUserView`,
`DataRightsView`, and `ProfileSetupView` + all 7 step views. The v1 `DQTextField`
was deleted — `DQFormParts` supersedes it with an identical init signature, so no
call site changed. Five of the nine open design calls are now answered by the
spec; three remain (Radar, camera overlay, OAuth brand marks).

**Wave 1 — the 6 handoff surfaces:**
- `EncounterView` — stepper, RevealHero, score card, rating + tier upgrade, CTA ladder
- `IcebreakerView` — partner strip, trivia rows, word chain, feedback banner
- `HomeView` — QuestCard, DemoControl, nearby signals, floating tab bar
- `TrustCenterView` — current tier, metallic ladder, per-tier requirements, disclaimer
- `SafetySheetView` — two working rows, report-only `danger`; wired to the encounter shield
- `ConnectedChatView` — built but **unreachable**: there is no messaging model

**Not yet migrated (17 files):** `RadarView`, `StatsView`, the auth/liveness tree
(`SplashView`, `OnboardingView`, `LivenessCheckView`, `WaitlistView`),
`NameDropInstructionView`, `PostMeetRatingView`, `RootView` (one token), and the
eight v1 components.

**Blocked on features, not styling:** messaging (no `Message` model, so chat is
unwired and stage 4 still reads "Done"), live-location sharing and check-in
scheduling (both safety rows ship visibly unavailable), and a quest content
model. `TrustCenterView` is still unreachable — the Settings Verification row
pushes a "Verification coming soon" empty state where it belongs.

Fonts are bundled and verified: Plus Jakarta Sans + IBM Plex Mono, SIL OFL 1.1,
in `Resources/Fonts` via a new synchronized group.

Full detail — including everything deferred and why — is in
[`UI_REWORK_STATUS.md`](UI_REWORK_STATUS.md).

## Immediate next steps

1. **Run it.** This is now the only thing standing between the rework and
   confidence, and it has been the top item for two waves running. Nothing has
   been exercised at runtime: the floating tab bar's safe-area handling, the
   QuestCard sweep timing, the width-scaled thumbnail blur, the step dots, the
   blocking-save overlay — and now the glass, which is the kind of change that
   can only be judged on a device. See `UI_REWORK_STATUS.md` §6 for the specific
   things to look at.
2. Migrate the 17 remaining `enum DQ` readers, then delete it. Three design calls
   need answering first — Radar, the camera overlay (now half-answered: controls
   take glass, the prompt text is still unruled), and OAuth brand marks; see
   `UI_REWORK_STATUS.md` §7. Read the `RadarScreenV2` mock into spec §6 before
   touching `RadarView`.
3. Add mock fixtures + SwiftUI previews so v2 surfaces can be iterated without a
   Firebase sign-in.
4. Point the Settings Verification row at `TrustCenterView` instead of the
   placeholder — a one-line change.
5. Define a quest content model — the QuestCard is specced around one that does
   not exist.
6. Design messaging, then wire `ConnectedChatView` and restore `Say hello`.
7. **Optional: shrink the repo's history.** `functions/node_modules/` is no
   longer tracked (August 5) — it was 8,847 of 8,973 tracked files, kept alive
   only because it predated the `.gitignore` rule. Untracking stops the growth
   but leaves the old blobs in past commits, so a fresh clone is still large.
   Actually shrinking it means a history rewrite (`git filter-repo`), which is
   worth doing only if clone size becomes a real problem — it invalidates every
   existing clone and rewrites every commit hash.

## Carried over (unchanged from Phase 1/2)

- Firestore Security Rules still needed to enforce alert caps server-side;
  client caps remain advisory.
- `ProximityService` UWB/BLE events not yet wired into
  `MatchManager.handleNearbyEvent`.
- AI preference alignment (dimension 4) still a distance-tolerance check.
- Apple Sign-In stubbed pending paid Developer Program enrollment.
