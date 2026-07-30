# Handoff: Serendipity — DesignSystem v2 (UI rework)

## Overview

A full visual rework of Serendipity, a proximity-based dating app built around a **progressive photo reveal**. Two strangers near each other open an encounter; the partner's photo starts heavily blurred and sharpens as they complete icebreaker challenges, reaching full clarity only after a mutual NameDrop. Trust tiers (Bronze → Platinum) and safety affordances run throughout.

**The app's functionality does not change.** This is a design-system replacement: new colour, type, geometry and component language applied across every surface the product already has. The reveal mechanic, stage machine, trust ladder and `#if DEBUG` demo path are all preserved exactly as they behave today.

The direction was derived from four reference apps supplied by the client: warm, photo-forward, soft neutral grounds, frosted glass over imagery, pills for every interactive element, and bold geometric display type. It replaces a colder teal/monospace "technical" system.

## About the Design Files

The files in this bundle are **design references created in HTML** — prototypes that show the intended look and behaviour. They are **not production code to copy directly**.

Serendipity is a **SwiftUI** app. The task is to recreate these designs in the existing SwiftUI codebase using its established patterns, view structure and navigation. `DesignSystem.swift` in this bundle is the one file intended to be used close to as-is: it is a drop-in token layer (palette, geometry, typography, shadows, reveal maths, trust tiers) written idiomatically for SwiftUI. Everything else — screens and components — should be built as native SwiftUI views that read from those tokens.

Do not port the HTML. Do not introduce a web view. Do not hard-code hex values in views; read `@Environment(\.dq)`.

## Fidelity

**High-fidelity.** Final colours, typography, spacing, radii, shadows and motion are specified. Recreate the UI pixel-accurately using the tokens provided. Where a value is not listed, derive it from the nearest token rather than inventing a new one.

Mocks are drawn at **iPhone 15/16 Pro — 393 × 852 pt**.

## Screens / Views

Full per-component specification lives in **`DESIGN_SYSTEM.md` §5 (Components)** and **§6 (Screens)**. Summary:

### 1. EncounterView — the core surface
The reveal ladder, four stages on one screen.
- **Layout (top → bottom):** top bar (proximity label + shield/more icon buttons) → StageStepper → RevealHero (flexes to fill) → score card *or* rating + tier-upgrade card → primary CTA → safety line.
- **Padding:** 58 top, 16 horizontal, 22 bottom. 14 between blocks.
- **RevealHero:** `rHero` 28, blurred photo layer at `scale(1.18)`, dark scrim gradient, glass tier chips top-left, radar pulse top-right (stage 1 only), name/identity + reveal meter pinned bottom.
- **Stage 1–3** show the vibe score breakdown and shared-interest chips. **Stage 4** replaces them with the rating bar and the Gold → Platinum upgrade banner, and the name resolves with a verify check.
- **CTA copy per stage:** `Start icebreaker` → `Continue` → `NameDrop to connect` → `Say hello`. Only stage 3 uses the ember fill; the rest use the neutral CTA.

### 2. IcebreakerView — Trivia & Word Chain
- Persistent **partner strip** at the top: blurred thumbnail + live reveal meter, so the unblur stays visible during play.
- **Trivia:** prompt card with four `IcebreakerOptionRow`s; the selected/correct row is `emberSoft` + 1.5px `ember` + white check.
- **Word Chain:** alternating chain pills (theirs neutral, yours ember-tinted, open slot bolder) + a pill input with an ember send FAB.
- Both end with a feedback banner (`+8% reveal`) above the neutral CTA.

### 3. HomeView — Quest card + demo control
- **QuestCard** is the hero and the only ember-bordered surface in the app, with a sweeping indeterminate bar signalling "active".
- **DemoControl** (`#if DEBUG`): dashed-border block with a mono `DEBUG` chip, "Developer bypass · not shipped", a ghost **Simulate encounter** pill and a reset circle. Deliberately on-system but unmistakably not production.
- **Signals nearby:** blurred photo cards with glass tier chips.
- Floating pill tab bar over content.

### 4. Connected chat (post-NameDrop)
Unblurred avatar + verify check, live "still nearby" indicator, a "You connected" summary card with shared-interest chips, message bubbles (`ember` for outgoing), a persistent safety prompt, and a pill composer with ember send FAB.

### 5. Trust centre
Current-tier card with the 4-segment metallic ladder, then a row per tier stating its requirement, with completed tiers checked and the current tier ringed. Closes with the disclaimer that tiers are not a ranking and never affect visibility.

### 6. Safety sheet
Bottom sheet over a dimmed, blurred encounter. Four rows — share live location, check in later, end encounter, report. Only the report row uses `danger`.

## Interactions & Behavior

- **Stage advance:** blur radius, stepper and reveal meter animate **together**, 400ms ease-out. This is the product's signature moment — do not stagger them.
- **Icebreaker action:** +0.08 `revealProgress` per success, clamped to the stage ceiling. `EncounterSession` remains authoritative.
- **NameDrop:** requires both parties. Only on mutual confirmation does `revealProgress` reach 1.0 and the name resolve.
- **Rating submit:** average ≥ 4.0 triggers the Gold → Platinum upgrade, shown in real time with a breathing glow.
- **Simulate encounter (DEBUG):** drives the same state machine as a real proximity trigger — no separate code path.
- Ambient loops (live dot, radar pulse, quest sweep, tier glow) and press states are specified in `DESIGN_SYSTEM.md` §7.

## State Management

Unchanged from the current app. The design consumes:
- `revealProgress: Double` (0…1) — drives blur, meter and stage.
- `stage: DQReveal.Stage` — derived from `revealProgress`; drives stepper, CTA copy and which panel is shown.
- `partner` — photo, vibe score + breakdown, shared interests, trust tier, verification state.
- `user.trustTier` + `averageRating` — drives the tier badge and the upgrade banner.
- `icebreaker` — game type, question/link index, per-answer correctness, streak.
- `isDebugBuild` — gates the demo control.

`DQReveal.Stage` in `DesignSystem.swift` mirrors the existing stage semantics; map it to the app's own enum rather than replacing that enum if one already exists.

## Design Tokens

See **`DESIGN_SYSTEM.md` §1–§3** for the complete table (colour, type, geometry) and **`DesignSystem.swift`** for the compilable version. Highlights:

- **Ember `#F2683C`** — the single brand accent: reveal progress, the commit CTA, correct answers. Never a large fill.
- **Verify `#2E9BF0`**, **Live `#4ADE80` / `#3E9E63`**, **Danger `#E5484D`** — each reserved to one meaning.
- **Neutral CTA** flips `#1B1C1F` (light) ↔ `#FFFFFF` (dark) so ember stays reserved for commitment.
- Radii 28 / 24 / 20 / 999. Gutter 16, block gap 14. CTA height 54, min hit target 44.
- Type: **Plus Jakarta Sans** (display/UI) + **IBM Plex Mono** (session IDs, option letters).

## Assets

- **Fonts:** Plus Jakarta Sans (400–800) and IBM Plex Mono (400–500), both SIL Open Font License — bundle them in the app target. `DesignSystem.swift` includes `.system` fallbacks.
- **Photography:** all partner/user photos in the prototypes are empty drag-and-drop placeholders. No imagery is included or licensed — supply real assets.
- **Icons:** the prototypes use typographic glyphs (`←`, `⋯`, `⛨`, `◆`, `♡`, `↑`) as stand-ins. Replace with SF Symbols in implementation: `chevron.left`, `ellipsis`, `shield`, `diamond.fill`, `heart`, `arrow.up`.

## Files

Design references in this bundle (open in a browser):

| File | Contents |
|---|---|
| `Serendipity DS v2.dc.html` | **Start here.** The system board — token ramps, type scale, component gallery in both themes, the reveal ladder, and EncounterView at four stages. |
| `Serendipity Screens v2.dc.html` | All six app surfaces rendered in dark and light. |
| `EncounterScreenV2.dc.html` | EncounterView component (props: `stage` 1–4, `mode`). |
| `IcebreakerScreenV2.dc.html` | Icebreaker component (props: `game` trivia/chain, `mode`). |
| `HomeScreenV2.dc.html` | HomeView with quest card + DEBUG control. |
| `ConnectedChatV2.dc.html` | Post-NameDrop chat. |
| `TrustCenterV2.dc.html` | Trust tier ladder. |
| `SafetySheetV2.dc.html` | Safety bottom sheet. |
| `DSGallery.dc.html` | The component gallery, theme-agnostic. |
| `DESIGN_SYSTEM.md` | **The spec.** Tokens, components, motion, rules. |
| `DesignSystem.swift` | Drop-in SwiftUI token layer. |
| `ios-frame.jsx`, `image-slot.js`, `support.js` | Prototype scaffolding only — ignore when implementing. |

Every theme in the prototypes is a set of CSS custom properties on a wrapper element; no component knows which theme it is in. Mirror that in SwiftUI with `@Environment(\.dq)` rather than branching on `colorScheme` inside views.

## What to avoid

Carried over from the client's art direction, and enforced throughout the mocks:

- Pink/purple gradients, neon, heavy glows.
- Ember as a large surface fill.
- Gamified trust — XP bars, badge shelves, confetti on verification.
- Partial face or eye reveal; any non-uniform blur.
- Neumorphic emboss shadows.
- Auto-revealing without mutual consent.
