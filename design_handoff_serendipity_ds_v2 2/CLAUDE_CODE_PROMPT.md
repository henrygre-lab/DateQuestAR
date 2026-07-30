# Claude Code prompt — DQ form primitives + v1 token migration

Paste everything below the line into Claude Code from the repo root.

---

You are working in the Serendipity (DateQuestAR) SwiftUI app. The design system was reworked to v2 — warm, photo-forward, dual-theme — and six encounter-flow surfaces are already migrated. Your job is the remaining ~30 views. There is no new design work in this task: every visual decision is already made and written down. Follow it exactly.

## Read first

- `docs/DESIGN_SYSTEM.md` — canonical. If anything here disagrees with it, the repo doc wins, and tell me.
- `UI_REWORK_STATUS.md` §7 — the survey of what is left.
- `Utilities/DQDesignSystem.swift` — the v2 tokens. Everything is reached through `@Environment(\.dq)`.

## Current state

- v2 tokens live in `Utilities/DQDesignSystem.swift` and are consumed as `@Environment(\.dq) var dq`.
- Already migrated: `EncounterView`, `IcebreakerView`, `HomeView`, `ConnectedChatView`, `TrustCentreView`, `SafetySheetView`, plus `Views/Components/DQEncounterParts.swift` and `DQIcebreakerParts.swift`.
- Legacy `enum DQ` still exists and is what the remaining views use. It gets deleted at the end of this task, not before.
- Theme is pinned once, at the app root, via `DQThemePreference.resolved` in `DateQuestARApp`. Do not add a second `.dqTheme(` call anywhere. There should be exactly one in the codebase when you are done.
- `AppDelegate.swift` has two pre-existing `OpenURLOptionsKey` deprecation warnings. Leave them. Do not fix, do not touch that file.

## Step 1 — build the form primitives

Create `Views/Components/DQFormParts.swift`. Nothing else can migrate until this exists. Build these, all reading `@Environment(\.dq)`, no raw hex, no `enum DQ`:

| Component | Notes |
|---|---|
| `DQSectionHeader` | uppercase tracked label above a group, outside the card |
| `DQGroup` | grouped container; hosts rows and draws the dividers between them |
| `DQRow` | label + optional sub-label + trailing content |
| `DQValueRow` | `DQRow` with a mono value and a chevron; push navigation |
| `DQToggleRow` | `DQRow` with the custom toggle |
| `DQStepperRow` | `DQRow` with the −/+ control |
| `DQSliderRow` | full-width label/value header over the track |
| `DQSegmentedPicker` | 2–3 options; standalone, not inside `DQGroup` |
| `DQTextField` | label above, field, error below; idle/focus/error/disabled |
| `DQTextArea` | multiline variant with a character counter in the label row |
| `DQDangerRow` | `DQRow` with danger label text |
| `DQConfirmSheet` | title, body, filled danger pill, cancel |
| `DQEmptyState` | glyph circle, title, body, ghost pill action |
| `DQSkeleton` | shimmering placeholder bar |
| `DQTopBar` | root (large title) and pushed (centred title, back circle, optional trailing action) variants |
| `DQAuthButton` | filled neutral / ghost-with-glyph / plain-text variants |

### Exact metrics

Rows and groups
- Row min height 56pt, padding 14 vertical / 18 horizontal, 14pt gap between label block and trailing content.
- Label 600/14. Sub-label 500/11.5 in `text-2`. Divider 1pt `line`, inset 18pt on the leading edge, never after the last row in a group.
- Group corner radius 24 (`r-card`), background `surface`, 1pt `line` border, contents clipped.
- Section header 600/9.5, +20% tracking, uppercase, `text-3`, 18pt leading inset, 9pt above the group.
- Footnote below a group: 500/11 `text-3`, 18pt leading inset.
- Rows carry **no icons**. Leading glyphs are reserved for trust, live and verify states.

Fields
- New radius `r-field` = 16. Add it to the token file alongside `r-row` 20 / `r-card` 24 / `r-hero` 28.
- Field height 52pt, horizontal padding 16, background **always** `surface-2` with a 1pt `line` border — same on `bg` and inside a `surface` card. Do not vary it by context.
- Field label 600/9.5 +16% uppercase `text-2`, 7pt above the field. Error 500/11 in `danger`, 7pt below.
- Focus: border goes 1.5pt `cta`. No glow, no ember. Caret is `text`.
- Disabled: opacity 0.45. Geometry and border unchanged.
- Text area min height 84pt, padding 14/16, character counter 500/10.5 mono `text-3`, right-aligned in the label row.

Controls
- Toggle 51×31, knob 27 white with a soft shadow. On = `ember`, off = `track`.
- Stepper: 34×34 buttons, radius 11, inside a 4pt-padded `surface-2` track of radius 14. Value 500/15 mono, min width 30, centred.
- Slider: 6pt track `track`, filled portion `ember`, knob 22 circle `surface` with 1pt `line` and `shadow-sm`. Value in the header row is 500/13 mono `ember-text`.
- Segmented picker: 4pt-padded `surface-2` track radius 16, segments radius 12, 11pt vertical padding. Selected = `cta` fill with `cta-text` ink at 700/12.5; unselected 600/12.5 `text-2`.

Top bars and auth
- Root title 800/21, −2.5% tracking. Pushed title 700/15 centred. Back button 38pt circle, `surface` fill, 1pt `line`.
- Trailing text action 600/13 in `ember-text`.
- Auth buttons 52pt height, pill radius. Filled variant `cta` / `cta-text` at 700/14; ghost variant 1pt `line-strong` border, 600/14 `text`; plain text variant 44pt height, 600/13 `text-2`.

Empty and loading
- Empty state: 44pt `surface-2` circle with a 17pt glyph in `text-3`, title 700/14, body 500/11.5 `text-2`, ghost pill action 11/20 padding.
- Skeleton bars radius 10 on `surface-2`, shimmer sweep 1.5s linear, gradient through `line-strong`.
- Use a spinner only for waits under ~1 second. Anything longer gets skeletons shaped like the content.

### Rules that are decided — do not re-litigate

1. **Focus is neutral, never ember.** Ember appears in a form in exactly one place: a value the user is tuning live (the radius slider fill and its mono readout).
2. **Values are mono, words are Jakarta.** Counts, distances, dates, ratings, IDs → IBM Plex Mono. Prose and labels → Plus Jakarta Sans.
3. **One primary pill per screen.** In auth, that one is the neutral filled Apple button; every other provider is ghost, and provider colour is confined to the glyph.
4. **Danger covers account deletion** — as row label text in a list, as a filled danger pill only inside a confirm step. Never a filled danger pill on a settings row.
5. **Custom top bars, not `NavigationStack` toolbars.** The floating round back button is already the app's language.
6. **No location names.** Never a neighbourhood, city, venue or landmark, anywhere, ever. Counts only. A live distance inside an active encounter is fine ("40 m away"); a place name is not.
7. **XP is not gamified trust.** `StatsView` may show XP: mono, neutral ink, plain `surface` card. Never beside a tier badge, never a level-up celebration, never confetti.
8. **`StageStepper` is not reusable for onboarding.** It reads as reveal progress. Onboarding steps get a plain dot row instead.

## Step 2 — migrate, in this order

1. `SettingsView` (448 lines) — largest, and the mock is `SettingsScreenV2.dc.html` in this bundle. Match it.
2. `ProfileSetupView` (363)
3. `AddPauseZoneView`
4. `ReportUserView`
5. `DataRightsView`
6. Everything else in `UI_REWORK_STATUS.md` §7 that is form, auth or system chrome.

For each file: swap `enum DQ` values for `@Environment(\.dq)` tokens, replace hand-rolled form UI with the `DQFormParts` components, and change nothing about the behaviour, copy or navigation. If a view needs a primitive that is not in the table above, stop and tell me rather than inventing one.

## Step 3 — finish

- Delete `enum DQ` once nothing references it. Confirm with a grep that nothing does.
- Grep for raw hex in the migrated files. There should be none outside `Utilities/DQDesignSystem.swift`.
- Confirm exactly one `.dqTheme(` call in the codebase.
- Build clean. The only warnings should be the two `OpenURLOptionsKey` ones in `AppDelegate.swift`.
- Append any ruling you had to make to `docs/DESIGN_SYSTEM.md` under the section it belongs to — that doc is written in by whoever implements, and it is canonical.

## Do not

- Do not restyle the six already-migrated surfaces.
- Do not add a second theme pin or reintroduce per-surface `Content: View` wrappers. They were deliberately collapsed.
- Do not bundle fonts in this task. SF Pro / SF Mono fallback is intentional for now.
- Do not add gradients, ember fills on large surfaces, badge shelves, or partial-blur reveal effects.

## Reference files in this bundle

- `FormsGallery.dc.html` — every primitive above, both themes. Open it in a browser.
- `SettingsScreenV2.dc.html` — the primitives composed into the first migration target.
- `Serendipity DS v2.dc.html` — the full system, §03 is forms, §04 is the do/avoid rules.
- `DESIGN_SYSTEM.md`, `DesignSystem.swift` — the spec and the token source as of this handoff. The repo copies are canonical if they have moved on.
