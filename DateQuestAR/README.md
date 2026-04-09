# Serendipity

A proximity-based iOS dating app that uses real-world location, AR icebreakers, and AI compatibility scoring to help people meet in person — spontaneously.

## Concept

Serendipity flips the traditional dating app model. Instead of swiping endlessly, users activate **Quest Mode** to passively scan their surroundings. When a high-compatibility match comes within a quarter mile, both phones alert. As the two people get closer, their profile photos reveal themselves and an AR icebreaker challenge triggers — turning the moment of meeting into a game.

## Features

### Quest Mode

- Activate background location scanning to find nearby compatible people
- Haptic feedback ramps up in intensity as distance closes (0.25 mi → 0.0 mi)
- Auto-pauses when entering user-defined zones (home, work, etc.)

### Proximity-Driven Match Flow

| Distance  | Status             | Experience                   |
| --------- | ------------------ | ---------------------------- |
| < 0.25 mi | `inProximity`      | Alert sent, match card shown |
| < 0.10 mi | `revealed`         | Profile photos unlock        |
| Active    | `icebreakerActive` | AR mini-game triggered       |
| Post-meet | `connected`        | NameDrop / contact exchange  |

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

### Privacy & Safety

- Location stored as **geohash** (precision 7) — never raw coordinates
- Three sharing modes: `precise`, `anonymized` (default), `hidden`
- Configurable auto-pause geofence zones
- Daily alert limits
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

## Known Limitations / TODOs

- Geohash encode/decode is currently a placeholder — integrate GeoFire or a native geohash library
- Apple Sign-In is stubbed; OAuth flow not yet implemented (requires paid Apple Developer Program)
- Google Sign-In is implemented and functional
- ProximityService (UWB/BLE) is not yet wired to MatchManager — real proximity events don't trigger match flow
- AI preference alignment score is minimal (distance check only); expand with gender preferences, dealbreakers, and ML model
- Post-meet rating pipeline is integrated (ratings flow through to trust level recalculation)

## Design Considerations

See [docs/POTENTIAL_ISSUES.md](docs/POTENTIAL_ISSUES.md) for critical risks and mandated mitigations (gender imbalance, trust erosion, swarm effect, privacy, low-density silence).

## License

Copyright 2026 Serendipity. All rights reserved. Unauthorized reproduction, distribution, or modification is prohibited.
