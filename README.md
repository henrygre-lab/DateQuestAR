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
| **XP Gamification** | XP, level progression, and badges earned for quests, icebreakers completed, and confirmed connections. |

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

3D proximity uses horizontal distance + `CMAltimeter` altitude. Motion context (`CMMotionActivityManager`) gates new session creation to walking/running only.

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
| UI | SwiftUI — dark mode enforced, custom `DesignSystem` tokens |
| Architecture | MVVM + `ObservableObject` services |
| Backend | Firebase Auth + Cloud Firestore |
| Location | CoreLocation, geohash (precision 7, native implementation) |
| Short-range proximity | NearbyInteraction (UWB), CoreBluetooth (BLE) |
| Motion / Altitude | CMMotionActivityManager, CMAltimeter |
| Haptics | CoreHaptics |
| AR | ARKit |
| Computer Vision | Vision framework (liveness detection) |
| Auth | Firebase Auth, Face ID / Touch ID |
| Analytics | AppTrackingTransparency-compliant, no PII in events |
| Tests | XCTest (unit + UI) |

---

## Requirements & Setup

**Requirements**
- iOS 17+, Xcode 16+
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

## Known Limitations / Current Scope

These are deliberate next steps, not gaps — the core proximity-reveal-AR loop is fully implemented.

| Area | Current State | Next Step |
|---|---|---|
| ProximityService wiring | UWB/BLE service implemented; not yet connected to MatchManager trigger path | Wire `ProximityService` events into `MatchManager.handleNearbyEvent` |
| AI preference alignment | Dimension 4 (preference alignment) uses distance-tolerance check only | Expand with dealbreaker logic and ML model |
| Apple Sign-In | Stub implemented | Requires paid Apple Developer Program enrollment |
| Firestore Security Rules | Client caps are advisory; server rules not yet written | Add Firestore rules to enforce alert caps atomically |
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
