# Serendipity — Project Status (July 29, 2026)

## Build Status
- [x] Clean build succeeds for the iOS 26.2 simulator (verified July 29)
- [x] All Firebase modules resolved
- [x] Info.plist + Signing + @main entry point correct
- [x] AlertCapManager, BalanceEnforcer, and core safety features compile
- [ ] Not run on device or simulator since the UI rework — see below
- [ ] The entire rework is **uncommitted** — 45 changed paths in the working tree

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

1. **Commit the rework.** It is two full waves deep and entirely untracked, which
   means there is no way to bisect a regression back to a surface.
2. **Run it.** Nothing from the rework has been exercised at runtime. The
   floating tab bar's safe-area handling, the QuestCard sweep timing, the
   width-scaled thumbnail blur, and now the step dots and blocking-save overlay
   all need eyes on a device.
3. Migrate the 17 remaining `enum DQ` readers, then delete it. Three design calls
   need answering first — Radar, the camera overlay, and OAuth brand marks; see
   `UI_REWORK_STATUS.md` §7. Read the new `RadarScreenV2` mock into spec §6
   before touching `RadarView`.
4. Add mock fixtures + SwiftUI previews so v2 surfaces can be iterated without a
   Firebase sign-in.
5. Point the Settings Verification row at `TrustCenterView` instead of the
   placeholder — a one-line change.
6. Define a quest content model — the QuestCard is specced around one that does
   not exist.
7. Design messaging, then wire `ConnectedChatView` and restore `Say hello`.
8. Decide where the two design handoff drops live. There are currently two
   untracked copies — `Serendipity/design/` (drop 1) and
   `design_handoff_serendipity_ds_v2 2/` at the repo root (drop 2, with the forms,
   Radar and Settings mocks). Keep one, gitignore or commit it deliberately, and
   drop the stale one; `docs/DESIGN_SYSTEM.md` is canonical either way.

## Carried over (unchanged from Phase 1/2)

- Firestore Security Rules still needed to enforce alert caps server-side;
  client caps remain advisory.
- `ProximityService` UWB/BLE events not yet wired into
  `MatchManager.handleNearbyEvent`.
- AI preference alignment (dimension 4) still a distance-tolerance check.
- Apple Sign-In stubbed pending paid Developer Program enrollment.
