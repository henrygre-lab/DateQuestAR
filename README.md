# Serendipity

A proximity-based iOS dating app that uses real-world location, AR icebreakers, and AI compatibility scoring to help people meet in person — spontaneously.

## Concept

Serendipity flips the traditional dating app model. Instead of swiping endlessly, users activate **Quest Mode** to passively scan their surroundings. When a high-compatibility match comes within a quarter mile, both phones alert. As the two people get closer, their profile photos reveal themselves and an AR icebreaker challenge triggers — turning the moment of meeting into a game.

## Features

### Quest Mode

- Activate background location scanning to find nearby compatible people
- Haptic feedback ramps up in intensity as distance closes (0.25 mi → 0.0 mi)
- Auto-pauses when entering user-defined zones (home, work, etc.)

### Proximity-Driven Match Flow (Updated)

| Distance / Stage | Reveal Level | Experience |
|------------------|--------------|------------|
| < 0.25 mi (`inProximity`) | Heavily blurred | Alert + vibe badges only (after `AlertCapManager` + women-first queue) |
| Icebreaker active | Progressive unblur during shared AR | Collaborative challenge (Trivia/Gesture/AR Object/Word Association) |
| Icebreaker completed | Mostly clear + IG tease | "Vibe passed? NameDrop to connect" |
| Post-NameDrop `connected` | **Full profile** | Official match + post-meet accuracy rating → trust score |

**Additional Rules**  
- `EncounterSession` persists 10–15 min (even if users drift apart) for gamification momentum.  
- 3D proximity (horizontal + `CMAltimeter` altitude) and motion context (`CMMotionActivityManager` + speed) inside active sessions.  
- Strict walking/running filter for new sessions; relaxed once active.

### AR Icebreakers

Four challenge types designed to break the ice on the spot:

- **Trivia** — Answer a prompt together
- **Gesture** — Mirror a physical action via AR
- **AR Object** — Both users place the same virtual object in the world
- **Word Association** — Rapid-fire word chain game

### AI Compatibility Scoring

Matches are scored 0.0–1.0 across four dimensions before being surfaced:

| Dimension            | Method                                    |
| -------------------- | ----------------------------------------- |
| Interest overlap     | Jaccard index on interest arrays          |
| Relationship type    | Jaccard index on relationship type arrays |
| Age compatibility    | Bidirectional age-range check             |
| Preference alignment | Distance tolerance + future ML model      |

Default threshold to qualify as a match: **0.80**. Users can adjust this in settings.

### Safety & Privacy (Strengthened)

- Geohash-only storage (precision 7).  
- Mandatory ID + live selfie verification path.  
- Delayed reveal + AR icebreaker before full photos.  
- Enhanced group anomaly detection and "Unsafe Proximity" reporting.
- Three sharing modes: `precise`, `anonymized` (default), `hidden`
- Configurable auto-pause geofence zones
- Asymmetric daily alert caps via `AlertCapManager` (gender-aware limits)
- User verification system with `unverified / pending / verified / flagged` states
- Safety verification managed by `SafetyVerifier`
- **Liveness detection** during onboarding: camera-based face landmark analysis (Vision framework) prompts 2 random actions (turn left, turn right, blink, smile) to confirm a real person
- **Trust tier system**: Bronze (email) → Silver (liveness passed) → Gold (ID face match) → Platinum (avg post-meet rating ≥ 4.0)

### Gamification

- XP and level progression
- Badges earned for quests and connections
- Quest completion and total connection counters

## Tech Stack

| Layer        | Technology                                   |
| ------------ | -------------------------------------------- |
| Language     | Swift 5                                      |
| UI           | SwiftUI (dark mode enforced)                 |
| Architecture | MVVM + ObservableObject services             |
| Backend      | Firebase (Auth + Firestore)                  |
| Location     | CoreLocation, geohashing                     |
| Proximity    | NearbyInteraction (UWB), CoreBluetooth (BLE) |
| Haptics      | CoreHaptics                                  |
| AR           | ARKit                                        |
| Auth         | Firebase Auth, Face ID / Touch ID            |
| Vision       | Vision framework (liveness detection)        |
| Tracking     | AppTrackingTransparency                      |
| Tests        | XCTest (unit + UI)                           |

## Project Structure

```
Serendipity/
├── App/                    # Entry point, AppDelegate, RootView (state router)
├── Models/                 # UserProfile, Match, ScoreBreakdown, IcebreakerChallenge
├── ViewModels/             # AuthViewModel
├── Managers/               # MatchManager (scoring, quest mode, icebreakers)
│                           # SafetyVerifier, LivenessDetector
├── Services/               # FirestoreService, LocationService, ProximityService
├── Views/
│   ├── Auth/               # Sign in / sign up
│   ├── Onboarding/         # Profile setup, liveness check
│   ├── Home/               # Main dashboard
│   ├── Radar/              # Proximity visualization
│   ├── Icebreaker/         # AR mini-game views
│   ├── Settings/           # Privacy, preferences, reporting
│   └── Components/         # Reusable UI (DQTextField, ChipToggle, StatBadge, etc.)
└── Utilities/              # DesignSystem (DQ tokens), ColorExtension
```

## App State Flow

```
Loading (SplashView)
    └── Unauthenticated → OnboardingView (sign up / sign in)
            └── Onboarding → ProfileSetupView (first-time profile creation)
                    └── Authenticated → HomeView
```

## Requirements

- iOS 17+ (recommended)
- Xcode 16+
- "Always On" location permission required for Quest Mode
- Firebase project with Auth and Firestore enabled

## Setup

1. Clone the repo and open `Serendipity/Serendipity.xcodeproj` in Xcode.
2. Add your `GoogleService-Info.plist` to the `Serendipity/` target directory.
3. Resolve Swift Package dependencies (Firebase SDK) via Xcode's package manager.
4. Build and run on a physical device (location and haptics require real hardware).

> **Debug builds** include a "Developer Bypass" button on the login screen that skips authentication with a mock user profile.

### Competitor Landscape

Serendipity improves on Happn (AR gamified reveal vs. instant exposure), Breeze (spontaneous proximity vs. scheduled dates), Swerv (passive Quest Mode + AR vs. venue-only map), and First Round's On Me (vibe-first AI + trust flywheel vs. planned social). See `docs/COMPETITOR_ANALYSIS.md` for details.

## Known Limitations / TODOs

## Gender Balance & Safety Enhancements (In Progress on `feature/gender-balance-safety-v1`)
- Asymmetric alert caps, women-first queuing, squad radar defaults, intent/vibe filtering
- Dynamic `BalanceEnforcer` with male waitlist when male % > 55%
- Tiered identity verification via Persona/Onfido proxy
- Addresses top risks from `POTENTIAL_ISSUES.md` (#1 Gender Imbalance + #2 Misrepresentation & Lying)
- Every changed file will include Vibe Coding Security Checklist compliance header

> **Security Note**: All code changes in this feature strictly follow the [Vibe Coding Security Checklist](SECURITY_CHECKLIST.md). No hardcoded secrets, full auth + ownership checks, minimal data exposure.

- Geohash encode/decode is currently a placeholder — integrate GeoFire or a native geohash library
- Apple Sign-In is stubbed; OAuth flow not yet implemented (requires paid Apple Developer Program)
- Google Sign-In is implemented and functional
- ProximityService (UWB/BLE) is not yet wired to MatchManager — real proximity events don't trigger match flow
- AI preference alignment score is minimal (distance check only); expand with gender preferences, dealbreakers, and ML model
- Post-meet rating pipeline is integrated (ratings flow through to trust level recalculation)

## Launch Strategy (Phase 1 – Controlled Density & Female-First Acquisition)

**Goal**: Reach balanced gender ratio and critical mass in high-density environments where the AR icebreaker experience shines.

[Insert the full launch strategy draft I provided in the previous response here — the one covering college campuses, post-grad nightlife, Ft. Lauderdale Spring Break, festivals/concerts, tactics, metrics, and risk controls.]

## Design Considerations

See [docs/POTENTIAL_ISSUES.md](docs/POTENTIAL_ISSUES.md) for critical risks and mandated mitigations (gender imbalance, trust erosion, swarm effect, privacy, low-density silence).

## License

Copyright 2026 Serendipity. All rights reserved. Unauthorized reproduction, distribution, or modification is prohibited.

