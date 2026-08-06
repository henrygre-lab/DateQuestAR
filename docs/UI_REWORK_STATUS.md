# DesignSystem v2 — implementation status

Companion to `docs/DESIGN_SYSTEM.md`. That file is the **spec** (intent). This
one records **what is actually built**, what is deliberately deferred, and why.

The spec wins on values. Where the code departs from it, the reason is recorded
here and in a comment at the call site.

_Last updated: 2026-08-05. Verified building against the iOS 26.5 SDK on that
date; still never run — see §6._

---

## 0. Liquid Glass

The app deploys to iOS 26.2, so the frosted surfaces the spec described in CSS
terms are now the platform material. `dqGlass` in `DQDesignSystem.swift` wraps
`.glassEffect` so tints stay tokens; `DQGlass` holds those tints.

**Adopted** — everything that floats above content:

| Surface | Was | Now |
|---|---|---|
| `GlassChip` | `.ultraThinMaterial` under a white fill + 1pt border | glass tinted `chipTint`, no border |
| `RevealMeter` (over photo) | same hand-rolled stack | glass tinted `meterTint`, no border |
| `DQIconChrome` / `DQIconButton` | `surface` fill + `line` border + `shadowSm` | interactive glass circle |
| `FloatingTabBar` | `nav` fill capsule | glass tinted `DQGlass.nav`, active pill now slides |
| `ConnectedChatView` composer | `surface2` capsule + border | glass |
| `RadarView` HUD chrome | 6%-white chips, a glyph with a drop shadow | glass over the camera feed |
| `LivenessCheckView` cancel | 50%-black disc | glass over the camera feed |
| `HomeView` scroll | — | `.scrollEdgeEffectStyle(.soft, for: .bottom)` under the tab bar |

**Deliberately not adopted.** Glass is the layer above content; content stays
opaque. So: no glass on QuestCard, SignalCard, DemoControl, `DQGroup`/`DQRow`,
fields, the SafetySheet, the `DQBlockingSave` card, or the reveal hero. And no
`.glass` / `.glassProminent` button styles — the ember commit pill is supposed
to be the loudest thing on its screen, and a translucent one is a weaker CTA,
not a more modern one.

`SafetySheetView` keeps its explicit `bg` background rather than falling through
to the system's glass sheet material, because the theme is pinned dark (§1)
while the OS may be in light mode — the system material would follow the OS and
render that one sheet light inside a dark app.

Two call sites deliberately reach for `.glassEffect` directly instead of
`dqGlass`: `RadarView` and `LivenessCheckView` are still v1 surfaces, and the
no-mixing rule below means they must not pull in a v2 utility. The material is a
SwiftUI API, not a token, so using it there breaks nothing.

---

## 1. Two design systems, mid-migration

| | v1 (legacy) | v2 (current) |
|---|---|---|
| File | `Utilities/DesignSystem.swift` | `Utilities/DQDesignSystem.swift` |
| Entry point | `enum DQ` — `DQ.Colors.accent`, `DQ.Spacing.xl` | `@Environment(\.dq)`, `DQRadius` / `DQSpace` / `DQSize`, `DQFont` |
| Theme | Dark only | Dual-theme (pinned dark, see below) |
| Accent | Purple `#A855F7` | Ember `#F2683C` |

The two names are close enough to be a trap. **When touching a view, check which
system it already reads and stay in it — never mix them in one view.** Both files
carry a header saying so.

### Migrated to v2

- `Views/Encounter/EncounterView.swift`
- `Views/Icebreaker/IcebreakerView.swift`
- `Views/Home/HomeView.swift`
- `Views/Trust/TrustCenterView.swift`
- `Views/Safety/SafetySheetView.swift`
- `Views/Chat/ConnectedChatView.swift`
- `Views/Settings/SettingsView.swift`, `AddPauseZoneView.swift`,
  `ReportUserView.swift`, `DataRightsView.swift`
- `Views/Onboarding/ProfileSetupView.swift` + all 7 step views
- `Views/Components/` — `RevealHero`, `StageStepper`, `VibeScoreBreakdown`,
  `TierUpgradeBanner`, `DQEncounterParts`, `DQIcebreakerParts`, `DQHomeParts`,
  `DQFormParts`

### Still on v1

**17 files.** `RootView`, `SplashView`, `OnboardingView`, `LivenessCheckView`,
`WaitlistView`, `RadarView`, `StatsView`, `NameDropInstructionView`,
`PostMeetRatingView`, and the v1 components (`ChipToggle`, `DQBackground`,
`DQButtonStyles`, `DQCardModifier`, `FlowLayout`, `OAuthButton`, `StatBadge`,
`TrustBadgeView`).

`RootView` is the cheapest of them: a single `DQ.Anim.stateTransition` on the
state-router animation, and nothing else.

Two still need a design call before they can move — see §7: `LivenessCheckView`
(text and controls over a live camera feed) and the OAuth branding in
`OnboardingView`. `RadarView` now has a mock (`RadarScreenV2.dc.html`) but no
§6 entry in the spec.

`enum DQ` **cannot be deleted yet** — those 17 files still read it. The v1
`DQTextField` is gone: `DQFormParts` supersedes it with an identical init
signature, so its four call sites were untouched.

`FlowLayout` is shared: its default `spacing` is a v1 token, so v2 call sites
always pass `spacing:` explicitly.

### Theme resolution

There is **exactly one** theme pin, in `DateQuestARApp`:
`.dqTheme(DQThemePreference.resolved)`. Every v2 surface reads
`@Environment(\.dq)` and inherits it, including sheets and full-screen covers.

`DQThemePreference.resolved` returns `.dark` for now, because the un-migrated v1
surfaces are dark-only and a light theme would render half the app wrong. When
the migration finishes and a user-facing appearance setting lands, **that
property is the only thing that changes.**

Never pin a theme per surface. A screen that hard-codes its own palette can
never follow an appearance setting, which is the whole reason the system carries
two palettes. (Six per-surface pins existed briefly; the wrapper structs that
held them are gone.)

---

## 2. Typography

Plus Jakarta Sans (400–800) and IBM Plex Mono (400–500) ship in
`Serendipity/Resources/Fonts`, registered via `UIAppFonts`. Both are SIL Open
Font License 1.1 and the licences ship beside them in the bundle.

Two non-obvious details in `DQFont`:

- Faces are addressed by **exact PostScript name**, not family + `.weight()`,
  which leaves matching to the font engine and picks the wrong face at 800.
  IBM Plex Mono's names are irregular: Regular is `IBMPlexMono` (no suffix) and
  Medium is `IBMPlexMono-Medm`. The obvious guess `IBMPlexMono-Medium` resolves
  silently to Helvetica.
- `.custom(_:fixedSize:)`, not `.custom(_:size:)`. The latter opts into Dynamic
  Type scaling that `.system(size:)` never had, which would have silently
  changed layout under a skin change. **Dynamic Type is unaddressed** across
  both design systems and is its own piece of work.

---

## 3. Deferred — blocked on a data model

None of these are styling gaps. Each needs a model that does not exist, and the
project rule is to omit rather than fabricate a figure.

| Spec | Blocker |
|---|---|
| §5 QuestCard: title, description, `n / m quests`, end-time chip | **No quest content model.** Quest Mode is a `Bool` (`MatchManager.isQuestModeActive`); `GamificationProfile` explicitly removed `questsCompleted`. Card copy describes actual behaviour; the progress row and end-time chip are omitted. |
| §5 VibeScoreBreakdown: `emberSoft` percentile chip ("Top 4% nearby") | No percentile anywhere in `ScoreBreakdown` or the profile model. Number and label sit alone; nothing stretches to fill. |
| §5 Word chain: "Streak 4" chip | No streak field on `IcebreakerChallenge`. |
| §6 row 1 Signal cards: per-signal distance ("40 m away") | No per-user distance in production — only `demoDistanceMiles`, which is DEBUG-only. Cards show tier + vibe match. Vibe score is a real join from `activeMatches` to `nearbyUsers` by uid, and the line drops when no match record backs a profile. |
| §5 WordChainPill/Input: free-text input + ember send FAB | A game rule, not a skin — needs a definition of a valid link. See §6.2. |

---

## 4. Deferred — blocked on a missing feature

| Spec | Blocker |
|---|---|
| Stage 4 CTA `Say hello` | Chat has **no messaging model** (below), so there is still nowhere to send anyone. `DQReveal.Stage.primaryCTA` returns the shipped copy; the call site overrides to **"Done"** wired to `endDemoEncounter()`. Restore when messaging exists. |
| Safety sheet: *Share live location* | No live-location link service. The row is **absent**, not greyed out. |
| Safety sheet: *Check in later* | No check-in scheduler. Same treatment. |
| Connected chat: transcript + send | **No messaging model exists** — no `Message` type, no Firestore collection, no send path. The view is presentational and takes `messages:` / `onSend:` from its caller, so the composer is not a dead end wherever it is wired. `ChatMessage` in that file is a display-only placeholder; replace it with the real model and the layout should not need to change. |

Both safety rows are **removed entirely** rather than shown disabled. Whoever
opens that sheet may be in a bad situation right now: a row that cannot act
costs them reading time at the worst moment, and a visible "share live location"
is a false reassurance even greyed out. Two rows that both work beat four where
half are decoration. The removal site carries a comment saying where to restore
them.

### Entry points still needed

The shield in the encounter top bar now opens the SafetySheet (§6.1 authorises
shipping it once the sheet exists). The other two new surfaces are **not
reachable yet**:

| Surface | Suggested entry |
|---|---|
| `TrustCenterView` | `SettingsView`'s "Verification" row is the natural home, and it is already a `NavigationLink` — but it currently pushes `verificationPlaceholder`, a `DQEmptyState` reading "Verification coming soon". Swapping that destination is the whole wiring job. `TrustCenterView` takes `tier:` and an optional `onManageVerification:`; the CTA hides when that closure is nil rather than shipping a pill that goes nowhere, so it can be wired before ID verification exists. |
| `ConnectedChatView` | Stage-4 `Say hello`, once messaging exists. Wiring it before then would make the composer a dead end. |

---

## 5. Deliberate departures from the mocks

- **No place names anywhere.** Now a system rule — §8. Outside an active
  encounter the count of nearby signals is the only spatial fact that ships; no
  neighbourhood, city, venue or landmark, however incidental. The mock's
  "Mission district · 6 signals near" was wrong. A distance is never
  approximated when the data is absent — the line is dropped instead.
- **Three tab items, not four.** The mock's bar has four; the app has Quest /
  Stats / Settings. No fourth destination was invented.
- **Verify check is gated on real verification state.** The mock shows it
  always-on at stage 4 because its partner is fixed. §1 reserves `verify` for
  confirmed identity, so it reads `verificationStatus == .verified`.
- **Session line reads "Identity locked · A7-F3".** A bare technical ID says
  nothing; this carries the product promise. Code is display-only — first four
  hex characters of the match id, uppercased, never actionable.
- **Bottom padding respects the safe area.** §3's 22 is measured above the
  home-indicator inset, not from the physical edge — the prototype frame draws
  over the inset. Top padding is 58 from the physical edge as specced.
- **Per-stage captions are gone** (§6.1). The stepper label, reveal meter and
  CTA already carry the message three times.

---

## 6. Known loose ends

- **Nothing here has been run.** Every surface builds clean, but reaching
  EncounterView or IcebreakerView requires Firebase auth and a full sign-in, so
  none of it has been exercised on device or in the simulator. Specifically
  unverified at runtime: the floating tab bar's `.safeAreaInset(edge: .bottom)`
  + `.toolbar(.hidden, for: .tabBar)` combination across all three tabs; the
  QuestCard sweep-bar timing; whether the width-scaled blur reads as
  sufficiently hidden on the half-width signal cards; and the SafetySheet's
  `.presentationDetents([.height(560)])`, which was picked by measurement, not
  by eye. From the forms wave, add: `DQStepDots`' width animation across a
  seven-step flow, the `dqBlockingSave` overlay's 400ms floor and 8s copy swap,
  and `DQConfirmSheet`'s detent.
- **The glass has not been looked at either**, and it is the kind of change that
  can only be judged on a device. Worth a specific eye when one is available:
  whether `chipTint` at 16% white still holds a legible chip over the *lightest*
  part of a blurred photo, since the material is doing work the painted fill
  used to do outright; whether the tab bar's `nav` tint at 0.55 reads as chrome
  rather than as a grey smear; and whether the icon buttons, having lost
  `shadowSm`, still separate from a busy encounter background. All three are
  one-token fixes if they are wrong, which is why they were made tokens.
- **Three form components are built but unused.** `DQAuthButton` lands with
  `OnboardingView`, `DQSkeleton` with the first real loading state, and
  `DQSliderRow` has no caller yet. They are specced and implemented, but nothing
  has exercised them even at compile-of-a-call-site level.
- **No partner imagery is licensed.** `PartnerPhotoPlaceholder` is a neutral
  gradient + initials, shared by the hero, the partner strip and the signal
  cards. It fills its whole frame so blur stays uniform with no transparent edge.
- **No SwiftUI previews** on the v2 surfaces — they depend on `MatchManager`,
  which pulls in Firebase. Mock fixtures would make the rework far easier to
  iterate on.

---

## 7. Next: migrating the 17 remaining v1 files

Order: migrate every remaining `enum DQ` reader, then delete
`Utilities/DesignSystem.swift` outright. Nothing may read both systems at once.

The forms wave is done — `SettingsView`, `ProfileSetupView` and the three
smaller Settings screens moved onto `DQFormParts`. What is left is the
auth/liveness tree, the two un-specced HUD-ish screens, and the v1 components.

Roughly by cost: `RadarView` (330 lines), `LivenessCheckView` (242),
`WaitlistView` (189), `OnboardingView` (155), `PostMeetRatingView` (124),
`NameDropInstructionView` (62), `StatsView` (51), `SplashView` (49), `RootView`
(one token), then the eight v1 components.

The components are the tail, not the head: `DQBackground`, `DQButtonStyles` and
`DQCardModifier` are read by the screens above, so migrating a screen and its
components together is cheaper than doing either alone.

### Design calls — five of nine now answered by the spec

The second handoff drop added a **Form, auth & system chrome** section to §5, a
Radar and a Settings mock, and rulings in §8. That closed most of the list below.
Answered:

1. ~~**Form primitives.**~~ §5 now specifies rows, groups, fields, controls, top
   bars, auth buttons, empty/loading states, step dots and the blocking-save
   overlay. Built in `DQFormParts`.
2. ~~**Auth buttons.**~~ §8: the one primary pill in auth is the neutral filled
   button, every other provider is ghost, and provider colour is confined to the
   glyph. `DQAuthButton` is built but **not yet used** — it lands with
   `OnboardingView`.
3. ~~**StatsView vs §8.**~~ §8 now says the rule is about the *trust ladder*, not
   XP: XP may be displayed in mono on a neutral surface card, just never beside a
   tier badge and never as a level-up celebration.
4. ~~**Navigation chrome.**~~ §8: custom top bars, not `NavigationStack`
   toolbars; `NavigationStack` stays only where it drives real pushes and its bar
   is hidden. `DQTopBar` is built.
5. ~~**Multi-step progress.**~~ §5 specifies `DQStepDots` as its own component,
   deliberately not `StageStepper` — dots carry no fill so a step row can never
   be misread as a reveal meter.
6. ~~**Empty, loading and error states.**~~ §5 specifies both, plus the rule that
   skeleton-vs-spinner is *fetch vs commit*, not duration. `DQEmptyState` is in
   use in `SettingsView`; `DQSkeleton` is built but not yet used.
7. ~~**Account deletion.**~~ §1's `danger` row now reads "covers account and data
   deletion", as row-label ink in a list and as a filled pill only inside a
   confirm step. `DQDangerRow` + `DQConfirmSheet` implement exactly that.

Still open:

1. **RadarView.** A live proximity HUD with rings and blips — the most visually
   distinctive un-specced surface in the app. `RadarScreenV2.dc.html` now exists
   in the handoff, but §6 has no Radar row, so the mock has not been read into
   the spec as rulings. Do that before migrating, not during. Note the screen
   also sits directly under §8's no-place-names rule: a distance ring is a
   spatial fact and needs the same scrutiny the signal cards got.
2. **Camera overlay.** `LivenessCheckView` puts text and controls over a live
   camera feed. The scrim rule (§5) is specified for still photos. Half-answered:
   §8 now rules that *controls* over a camera feed take glass, and the cancel
   button and the Radar HUD chips have moved onto it. What is still unruled is
   the **prompt text**, which currently relies on the view's own 60%-black
   overlay-with-cutout. That overlay is doing a job the spec never described, and
   it is what a Radar migration would have to decide about too.
3. **OAuth brand marks.** §8 rules that provider colour is confined to the glyph,
   which settles the button; what it does not settle is whether Google's and
   Apple's brand guidelines accept a ghost pill with a coloured glyph. That is a
   compliance read of their published terms, not a design call.
