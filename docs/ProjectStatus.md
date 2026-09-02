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

## Security checklist audit (August 5)

Full pass over `docs/SECURITY_CHECKLIST.md` §01–§05. Eight findings, all fixed
except the two noted as still open.

| § | Finding | Status |
|---|---|---|
| 02 | `signIn` assigned Firebase's `localizedDescription` straight to the UI, which distinguishes `.userNotFound` from `.wrongPassword` — an account-enumeration oracle on the login form. The file's own compliance block claimed the opposite | **Fixed** — one message for both |
| 02 | `SafetyVerifier.reportUser` and the verification `catch` rendered raw backend error text; `deleteAccount` and `signOut` did the same | **Fixed** — generic copy, detail to the log |
| 04 | The AR session was never explicitly paused or torn down. ARKit interrupts itself on background, so no camera was left open, but nothing stopped the session when the radar was dismissed and the rule was satisfied only by inheritance | **Fixed** — explicit pause/resume + `dismantleUIView` |
| 01 | Dependencies had never been audited: 20 advisories, 2 critical, 3 high | **Fixed** for critical/high; 9 moderate remain, all requiring major bumps of `firebase-admin` and `firebase-functions` |
| 03/05 | `grantXP` documented its clamp as "server-side". It runs on the client, in a client-side transaction anyone can bypass | **Fixed** — comment now says advisory, like `AlertCapManager` |
| 04 | `NSFaceIDUsageDescription` missing while `LocalAuthentication` ships. Would crash the moment Face ID is wired | **Fixed** |
| — | `UIRequiredDeviceCapabilities` was `armv7` — 32-bit ARM, which no iOS 26 device has | **Fixed** → `arm64` |
| — | The checklist claimed every source file carries a compliance block; 25 of 75 did, in two different wordings, and `SafetyVerifier` had two stacked | **Fixed** — one wording, convention documented honestly |

**Still open, and both are structural rather than oversights:**

1. ~~**No Firestore Security Rules.**~~ **Closed (September 2).** See the campus
   pivot below.
2. **Motion and altitude filtering do not exist.** `CMMotionActivityManager` and
   `CMAltimeter` appear in no source file. README stated both as shipped and has
   been corrected; `EDGE_CASES_AND_OBJECTIONS.md` was already honest in calling
   them proposals. Vertical density and vehicle noise are unmitigated.

## Campus pivot (September 2)

The product moved from a city-scale proximity dating app to a **campus-gated,
multi-intent** one. Dating is now one of five intents, off by default, and the
only one carrying the gender-balance machinery.

**What was built**

- **Three gates**, each reading only server-issued fields:
  `canEnterCampusCommunity` (school gate) → `canStartQuestMode` (student ID card
  photo + liveness) → `canUseDatingIntent` (ID ↔ liveness face match + verified
  adult age). `canNameDrop` sits alongside the third.
- **`firestore.rules` + `storage.rules` + `firebase.json` + `firestore.indexes.json`.**
  The single largest open gap from the August audit is closed. The rules carry
  the same-school predicate (evaluated per document, so an unconstrained nearby
  query fails outright), the server-owned field list, the write-only verification
  prefix, and the reveal-stage gate on NameDrop. Authorization travels as Firebase
  Auth custom claims, which a client cannot forge.
- **Cloud Functions**: `schoolGate.ts` (phone + `.edu` magic link / school OAuth /
  enrollment proof; issues `schoolId` and `enrollmentStatus`),
  `studentIdVerification.ts` (server-side face match; deletes the artefacts once
  the outcome is recorded), `intents.ts` (intents + the 24h Dating-off cooldown).
  `balanceMonitor.ts` is now per-school and counts Dating-gated users only.
- **Spring Break Mode**: the one exception to same-school. Server-dated windows,
  dual server-confirmed presence, verified students only, 45-minute claim TTL.
- **48 unit tests**, all passing, covering the three gates, the same-school
  predicate, the intent lock, the cooldown and the fail-closed decoders.

**What this cost**

- `MatchPreferences.RelationshipType` is gone, replaced by `Intent`.
  `ScoreBreakdown.relationshipTypeMatch` became `intentMatch`.
- `FirestoreService.updateTrustLevel` was removed rather than left to fail:
  `trustLevel` is server-owned and a client write is now denied.
- `VerificationStepView` was deleted — it described a driver's licence or
  passport scan, which is no longer the flow. `StudentIDStepView` replaces it.
- `GamificationService.awardXP(uid:)` and `ReferralManager.processReferralReward`
  write another user's document. The rules now correctly deny that, so **those
  paths are broken until they move server-side.** This is a real regression and
  it is deliberate: a client-writable XP counter is a free XP faucet.

**What is unproven**

The rules have never been executed. There is no Firebase CLI in this environment,
so no `firebase emulators:exec` and no rules unit tests. Everything above is
reasoned and reviewed, not run. That is the top item on the list below.

## Current phase: DesignSystem v2 UI rework

Replacing the v1 purple/mono token layer with the ember, photo-forward v2 system
from the design handoff. Functionality is unchanged throughout: the reveal
mechanic, stage machine, trust ladder and `#if DEBUG` demo path all behave
exactly as before.

**28 of 48 view files are now on v2; 17 still read `enum DQ`.** The three new
campus surfaces (`SchoolGateView`, `StudentIDStepView`, `StudentIDPendingView`)
were written on v2.

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
model. `TrustCenterView` is now reachable — the Settings row points at it, and
the tier copy describes the campus gate rather than a generic identity ladder.

Fonts are bundled and verified: Plus Jakarta Sans + IBM Plex Mono, SIL OFL 1.1,
in `Resources/Fonts` via a new synchronized group.

Full detail — including everything deferred and why — is in
[`UI_REWORK_STATUS.md`](UI_REWORK_STATUS.md).

## Immediate next steps

0. **Execute the security rules.** They are the enforcement boundary for the
   entire campus gate and they have never run. Install the Firebase CLI, add
   `@firebase/rules-unit-testing` cases for the same-school predicate, the
   server-owned-field rejections and the cross-school Spring Break path, and put
   them in CI. Until this happens the gate is reviewed, not verified.
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
4. Move `GamificationService.awardXP(uid:)` and the referral reward path into
   Cloud Functions. The rules deny them now, so they are broken, not merely
   advisory.
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

- Firestore Security Rules are written and cover alert-adjacent server-owned
  fields; client caps remain advisory by design, with the rules as the boundary.
  Unexecuted — see step 0.
- The Spring Break `sbDest` claim has a 45-minute TTL that nothing re-confirms on
  a timer, so a user standing at a destination for over 45 minutes silently drops
  back to same-school until the next region crossing.
- `ProximityService` UWB/BLE events not yet wired into
  `MatchManager.handleNearbyEvent`.
- AI preference alignment (dimension 4) still a distance-tolerance check.
- Apple Sign-In stubbed pending paid Developer Program enrollment.
