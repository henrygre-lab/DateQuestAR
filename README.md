# Serendipity

Most dating apps are catalogs. Serendipity is a compass — a proximity-first iOS app that only reveals who you're compatible with, and what they look like, as you physically move closer together.

---

## Key Features

| Feature | Description |
|---|---|
| **Quest Mode** | Background location scanning. Haptic feedback ramps in intensity as a compatible match closes distance (0.25 mi → 0.0 mi). Auto-pauses inside user-defined geofence zones (home, work, etc.). |
| **Progressive Photo Reveal** | Photos unlock in four stages tied to physical proximity and shared interaction — no upfront visual judgment. |
| **AR Icebreakers** | Four challenge types (Trivia, Gesture, AR Object, Word Association) fire when users are in proximity. Completing one advances the photo reveal. |
| **AI Compatibility Scoring** | 0.0–1.0 score across interest overlap, relationship type, age compatibility, and preference alignment before any alert fires. Default match threshold: **0.80**. |
| **Asymmetric Alert Caps** | Gender-aware daily caps (women: 10, non-binary: 20, men: 40) enforced client-side via `AlertCapManager`. Firestore Security Rules are the authoritative gate. |
| **Real-Time Gender Balance** | `BalanceEnforcer` listens to a live Firestore ratio document (written by Cloud Functions). When male% exceeds 55%, male match visibility is probabilistically throttled to protect marketplace balance. |
| **Trust Tier System** | Bronze → Silver → Gold → Platinum progression based on identity verification depth and post-meet accuracy ratings. |
| **XP Gamification** | XP and level progression earned for icebreakers completed, NameDrops, and daily logins (`XPManager`). Badge definitions live in `GamificationService`; `GamificationProfile` stores XP, level, and login streak only. |

---

## How It Works

### Stage Progression

```
1. Quest Mode active
   └── Compatible user enters 0.25 mi radius
         └── AlertCapManager + BalanceEnforcer gate fires
               └── Both phones alert (haptics, vibe badges — NO photos yet)

2. Users physically approach
   └── EncounterSession opens (10–15 min, persists even if users briefly drift apart)
         └── AR icebreaker activates
               └── Photo progressively unblurs as challenge progresses (revealProgress 0.0 → 1.0)

3. Icebreaker completed
   └── Photo mostly clear + Instagram teaser visible
         └── Prompt: "Vibe passed? NameDrop to connect."

4. Mutual NameDrop (opt-in)
   └── Full profile unlocked — official match
         └── Post-meet accuracy rating → feeds into trust score
```

### Encounter Session Detail

`EncounterSession` is Firestore-backed and tracks `RevealStage` (`blurred → partial → revealed → connected`) plus a `revealProgress` float (0.0–1.0). Stage thresholds:

- `partial` at progress ≥ 0.30
- `revealed` at progress ≥ 0.70
- `connected` at progress ≥ 1.00 (post-NameDrop only)

> **Not yet implemented.** Earlier drafts of this section described 3D proximity via `CMAltimeter` altitude and a `CMMotionActivityManager` walking/running filter gating session creation. Neither framework is referenced anywhere in the codebase. Both remain *proposed* mitigations in [`docs/EDGE_CASES_AND_OBJECTIONS.md`](docs/EDGE_CASES_AND_OBJECTIONS.md) — vertical density (someone 40 floors up) and vehicle noise (alerts from passing cars) are currently unmitigated.

---

## Architecture

MVVM with `ObservableObject` services. All business logic lives in Managers and Services; Views bind only to `@Published` state. No logic in Views.

```
┌──────────────────────────────────────────────┐
│                  Presentation                │
│   RootView (state router)                    │
│     ├── AuthViewModel ──► FirebaseAuth       │
│     └── HomeView / RadarView / IcebreakerView│
└─────────────────┬────────────────────────────┘
                  │ binds to
┌─────────────────▼────────────────────────────┐
│                  Managers                    │
│   MatchManager   ─── scoring, quest mode,    │
│                       icebreaker dispatch    │
│   AlertCapManager ─── asymmetric daily caps  │
│   BalanceEnforcer ─── live gender ratio gate │
│   RevealManager  ─── EncounterSession state  │
│   LivenessDetector ─ Vision-based liveness   │
│   SafetyVerifier ─── group anomaly, reports  │
└─────────────────┬────────────────────────────┘
                  │ reads/writes
┌─────────────────▼────────────────────────────┐
│                  Services                    │
│   FirestoreService  ── Firestore CRUD        │
│   LocationService   ── CoreLocation + Geohash│
│   ProximityService  ── NearbyInteraction/BLE │
│   GamificationService ─ XP + badges         │
│   AnalyticsService  ── event logging (no PII)│
└──────────────────────────────────────────────┘
```

---

## Tech Stack

| Layer | Technology |
|---|---|
| Language | Swift 5 |
| UI | SwiftUI — dark mode enforced. Two token layers mid-migration: `DQDesignSystem.swift` (v2, current) and `DesignSystem.swift` (v1, legacy). See [Design System](#design-system). |
| Material | Liquid Glass (iOS 26) on chrome that floats above content — tab bar, icon buttons, over-photo chips, camera HUDs. Content surfaces stay opaque. |
| Typography | Plus Jakarta Sans + IBM Plex Mono, bundled (SIL OFL 1.1) |
| Architecture | MVVM + `ObservableObject` services |
| Backend | Firebase Auth + Cloud Firestore |
| Location | CoreLocation, geohash (precision 7, native implementation) |
| Short-range proximity | NearbyInteraction (UWB), CoreBluetooth (BLE) |
| Haptics | CoreHaptics |
| AR | ARKit |
| Computer Vision | Vision framework (liveness detection) |
| Auth | Firebase Auth (email/password + Google). Face ID via `LocalAuthentication` is implemented but not wired to any screen |
| Analytics | AppTrackingTransparency-compliant, no PII in events |
| Logging | `os.Logger` via `Utilities/Log.swift`, one category per subsystem area, messages marked `.private` |
| Tests | XCTest (unit + UI) |

---

## Requirements & Setup

**Requirements**
- Xcode 26+ (the deployment target is iOS 26.2 and the UI uses the Liquid Glass APIs; the project also uses file-system synchronized groups, which need Xcode 16+)
- iOS 26.2+ — this is the `IPHONEOS_DEPLOYMENT_TARGET` currently set in the project
- Physical device required — location services, haptics, and NearbyInteraction do not work in Simulator
- "Always On" location permission required for Quest Mode background scanning
- Firebase project with Auth and Firestore enabled

**Setup**
1. Clone the repo and open `Serendipity/Serendipity.xcodeproj`
2. Add your `GoogleService-Info.plist` to the `Serendipity/` target directory
3. Resolve Swift Package dependencies (Firebase SDK) via Xcode → File → Packages
4. Build and run on a physical device

> **Developer Bypass** — Debug builds include a login-screen bypass that signs in with a mock `UserProfile`. Useful for UI work without a live Firebase project.

---

## Safety, Privacy & Trust

These are design constraints, not afterthoughts. Each decision maps to a specific risk in `docs/POTENTIAL_ISSUES.md`.

**Location Privacy**
- Raw coordinates are never stored. All location data is encoded as a precision-7 geohash (~150 m cell) before any Firestore write.
- Three sharing modes: `precise` (opt-in only), `anonymized` (default), `hidden`.
- Configurable geofence auto-pause zones keep Quest Mode off at home and work.
- **No place is ever named in the UI.** Outside an active encounter, the count of nearby signals is the only spatial fact displayed — never a neighbourhood, city, venue or landmark. Storing coordinates safely is worth nothing if a screen prints the neighbourhood back out, and ambient screens are the most screenshotted. Enforced as a design rule in [`docs/DESIGN_SYSTEM.md`](docs/DESIGN_SYSTEM.md) §8.
- **Nothing identifying reaches the device log.** All logging goes through `Utilities/Log.swift`, which hands messages to `os.Logger` marked `.private` — readable when attached to Xcode or Console, redacted in any log a shipping build hands out. This replaced 55 `print` calls, which were not compiled out of release builds and between them carried a user's geohash, a match's display name and a reported user's uid.

**Identity Verification & Liveness**
- Onboarding requires a liveness check powered by the Vision framework. The camera prompts two randomly selected actions (turn left, turn right, blink, smile) and confirms completion across ≥ 3 consecutive frames before marking the user verified.
- Trust tiers reflect verification depth:
  - **Bronze** — email confirmed
  - **Silver** — liveness check passed
  - **Gold** — government ID + face match (via third-party proxy)
  - **Platinum** — Gold + average post-meet accuracy rating ≥ 4.0

**Asymmetric Alert Caps**
- Women receive significantly fewer inbound alerts (10/day) vs. men (40/day). Non-binary: 20/day.
- `AlertCapManager` enforces this client-side as a courtesy gate. Firestore Security Rules are the authoritative enforcement layer.
- Caps reset daily and are synced to Firestore using `updateData` on alert-only fields — server-authoritative fields (`trustLevel`, `accountStatus`) are never overwritten by the client.

**Gender Balance Enforcement**
- `BalanceEnforcer` maintains a real-time Firestore listener on a `global_gender_stats/current` document written exclusively by a Cloud Function.
- When male percentage exceeds 55%, male match visibility is probabilistically reduced (pass rate scales down linearly from 1.0, floored at 0.10).
- Alert caps are also dynamically halved for men during high-imbalance periods.
- Women-first queuing is toggled server-side and read by `BalanceEnforcer`.

**Anti-Harassment**
- Per-user ping cap: any single user can receive a maximum of 5 alerts per hour from the same partner.
- 15-minute cooldown between alerts for the same match pair.
- "Unsafe Proximity" one-tap report + group anomaly detection via `SafetyVerifier`.
- `accountStatus` enum gates all match visibility: `active / waitlisted / suspended / banned`.

**Progressive Reveal as Safety Mechanism**
- Photos are never surfaced at first alert. Visual identity only unlocks through mutual AR interaction. This removes the "swarm around attractive users" failure mode and eliminates cold visual rejection at the point of meeting.

---

## Design System

The UI is mid-migration between two token layers. **New work should target v2.**

| | v1 (legacy) | v2 (current) |
|---|---|---|
| File | `Utilities/DesignSystem.swift` | `Utilities/DQDesignSystem.swift` |
| Entry point | `enum DQ` — `DQ.Colors.accent` | `@Environment(\.dq)`, `DQRadius` / `DQSpace` / `DQSize`, `DQFont` |
| Accent | Purple `#A855F7` | Ember `#F2683C` |
| Theme | Dark only | Dual-theme (currently pinned dark) |

The names are close enough to be a trap: check which system a view already reads and stay in it. Never mix them in one view. Both files carry a header saying so.

**Liquid Glass** is applied through `dqGlass` in the v2 layer, and only to chrome that floats above content: the tab bar, icon buttons, over-photo chips, the over-photo reveal meter, the chat composer, and the HUD controls over the AR and liveness camera feeds. Content — cards, rows, panels, fields, sheets — stays on the opaque `surface` tokens, because glass that covers everything has nothing left to float above. The rule and its consequences (no borders, no drop shadows on small glass chrome) are in [`docs/DESIGN_SYSTEM.md`](docs/DESIGN_SYSTEM.md) §5; what changed where is in [`docs/UI_REWORK_STATUS.md`](docs/UI_REWORK_STATUS.md) §0.

- **The spec** — [`docs/DESIGN_SYSTEM.md`](docs/DESIGN_SYSTEM.md). Source of truth for tokens, components, motion and screen composition. This repo copy is canonical: rulings are written into it by whoever implements them. The spec wins on values.
- **What's actually built** — [`docs/UI_REWORK_STATUS.md`](docs/UI_REWORK_STATUS.md). Migration status, deferred items and why, deliberate departures from the mocks.

**27 of 46 view files are on v2.** All six handoff surfaces (`EncounterView`, `IcebreakerView`, `HomeView`, `TrustCenterView`, `SafetySheetView`, `ConnectedChatView`), the Settings tree (`SettingsView`, `AddPauseZoneView`, `ReportUserView`, `DataRightsView`) and the Onboarding tree (`ProfileSetupView` + all seven step views), plus the components they own.

Component layers live in `Views/Components`: `DQEncounterParts`, `DQIcebreakerParts`, `DQHomeParts` for the encounter flow, and `DQFormParts` for forms, auth and system chrome — rows, groups, fields, toggles, steppers, sliders, segmented pickers, top bars, step dots, empty states, skeletons, confirm sheets and the blocking-save overlay.

Still on v1 — **17 files**: `RootView`, `RadarView`, `StatsView`, `SplashView`, `OnboardingView`, `LivenessCheckView`, `WaitlistView`, `NameDropInstructionView`, `PostMeetRatingView`, and eight v1 components (`ChipToggle`, `DQBackground`, `DQButtonStyles`, `DQCardModifier`, `FlowLayout`, `OAuthButton`, `StatBadge`, `TrustBadgeView`). `enum DQ` cannot be deleted until they all move.

Fonts are bundled in `Serendipity/Resources/Fonts` and registered via `UIAppFonts` — no setup step required.

---

## Known Limitations / Current Scope

These are deliberate next steps, not gaps — the core proximity-reveal-AR loop is fully implemented.

| Area | Current State | Next Step |
|---|---|---|
| UI rework | 27 of 46 view files on v2 — all 6 handoff surfaces plus the Settings and Onboarding trees | Migrate the 17 remaining v1 files, delete `enum DQ`, then drop the theme pin and go `colorScheme`-driven |
| Messaging | `ConnectedChatView` is built but there is **no `Message` model, collection, or send path** | Design messaging; then wire the view and restore the stage-4 `Say hello` CTA |
| Safety actions | *End encounter* and *Report* work; *Share live location* and *Check in later* have no backing feature and ship visibly unavailable | Build a live-location link service and a check-in scheduler |
| Trust centre entry | `TrustCenterView` is built but unreachable. The Verification row in `SettingsView` currently pushes a "Verification coming soon" empty state | Swap that placeholder destination for `TrustCenterView` |
| Quest content model | Quest Mode is a `Bool`; no quest title, description, or `n / m` progress exists | Define a quest model so the QuestCard can carry real quest content |
| Dynamic Type | Neither design system scales with Dynamic Type | Audit both layers and adopt scaled fonts |
| Runtime verification | Builds clean against the iOS 26.5 SDK; **no v2 surface has been run**, on device or in Simulator, and the Liquid Glass work has never been looked at | Reaching an encounter needs Firebase auth — add mock fixtures and SwiftUI previews |
| ProximityService wiring | UWB/BLE service implemented; not yet connected to MatchManager trigger path | Wire `ProximityService` events into `MatchManager.handleNearbyEvent` |
| AI preference alignment | Dimension 4 (preference alignment) uses distance-tolerance check only | Expand with dealbreaker logic and ML model |
| Apple Sign-In | Stub implemented | Requires paid Apple Developer Program enrollment |
| Firestore Security Rules | **The single largest open gap.** Client caps, the XP clamp in `grantXP`, trust recalculation and account status are all advisory — a client-side Firestore transaction can be bypassed by anyone holding the app's credentials. `docs/SECURITY_CHECKLIST.md` §02/§03 name the server as authoritative; today nothing is | Write the rules, then move XP grants and trust updates behind Cloud Functions |
| Motion / altitude filtering | Not implemented — no `CMMotionActivityManager`, no `CMAltimeter`. Vertical density and vehicle noise are unmitigated | Build the walking/running gate and the altitude check described in `EDGE_CASES_AND_OBJECTIONS.md` |
| Cloud Functions dependencies | `npm audit` clean of critical/high as of 2026-08-05; 9 moderate advisories remain, all needing a major bump of `firebase-admin` (→14) and `firebase-functions` (→7) | Take the majors deliberately, with a deploy to the emulator to catch API breakage |
| AR Icebreaker views | Challenge types defined and dispatched; AR Object + Gesture views in progress | Complete ARKit placement views for all four types |
| Post-meet rating pipeline | Rating flow integrated into trust score recalculation | Build rating UI and Cloud Function aggregation |

---

## Competitor Differentiation

| App | Their Approach | Serendipity's Difference |
|---|---|---|
| Happn | Shows who you crossed paths with — instant photo exposure, retroactive matching | No photo until you've interacted in AR; meeting is the icebreaker, not the outcome |
| Breeze | Scheduled IRL dates | Fully spontaneous; no pre-planning required |
| Swerv | Venue-based map, check-in model | Passive Quest Mode — no venue dependency, works anywhere |
| Hinge / Tinder | Async swiping catalog, no physical proximity | Physical co-presence required; removes ghosting by design |

---

## License

Copyright 2026 Serendipity. All rights reserved. Unauthorized reproduction, distribution, or modification is prohibited.
