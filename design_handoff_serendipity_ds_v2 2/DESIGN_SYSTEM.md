# Serendipity DesignSystem v2 (DQ tokens)

Dual-theme (light + dark), warm, photo-forward. This file is the **single source of truth** for tokens.
Everything below is expressed as a semantic token — never hard-code a raw hex in a view.

---

## 1. Colour tokens

### Brand / semantic accents (identical in both themes unless noted)

| Token | Light | Dark | Use |
|---|---|---|---|
| `ember` | `#F2683C` | `#F2683C` | Reveal progress, the commit CTA (NameDrop), correct answers, send buttons. The brand warmth. |
| `emberSoft` | `rgba(242,104,60,0.11)` | `rgba(242,104,60,0.16)` | Tinted fills behind selected/correct states |
| `emberLine` | `rgba(242,104,60,0.30)` | `rgba(242,104,60,0.38)` | Borders on ember-tinted surfaces |
| `emberText` | `#D2481F` | `#FF8A5F` | Ember-coloured **text** (contrast-corrected per theme) |
| `emberGlow` | `rgba(242,104,60,0.30)` | `rgba(242,104,60,0.32)` | Shadow colour under ember buttons |
| `verify` | `#2E9BF0` | `#2E9BF0` | Identity verification check **only** |
| `live` | `#3E9E63` | `#4ADE80` | Presence / proximity dots |
| `liveText` | `#2F8F55` | `#4ADE80` | Live-coloured text |
| `danger` | `#E5484D` | `#E5484D` | Report / destructive **only** — never decorative |

### Surfaces & ink

| Token | Light | Dark |
|---|---|---|
| `bg` | `#EFEFF1` | `#101113` |
| `surface` | `#FFFFFF` | `#1A1B1E` |
| `surface2` | `#F5F5F7` | `#24262A` |
| `text` | `#16171A` | `#F6F7F8` |
| `text2` | `#6E727A` | `#9BA0A8` |
| `text3` | `#767B84` | `#6A6F77` |
| `line` | `rgba(20,22,26,0.09)` | `rgba(255,255,255,0.09)` |
| `lineStrong` | `rgba(20,22,26,0.18)` | `rgba(255,255,255,0.18)` |
| `track` | `rgba(20,22,26,0.10)` | `rgba(255,255,255,0.12)` |

### CTA & navigation

| Token | Light | Dark |
|---|---|---|
| `cta` (neutral button fill) | `#1B1C1F` | `#FFFFFF` |
| `ctaText` | `#FFFFFF` | `#15161A` |
| `nav` (floating bar fill) | `#1B1C1F` | `rgba(36,38,42,0.94)` |
| `navInk` | `#9A9EA6` | `#8B9098` |
| `navActive` | `#FFFFFF` | `#FFFFFF` |
| `navActiveInk` | `#15161A` | `#15161A` |

### Trust tiers

| Token | Light | Dark |
|---|---|---|
| `bronze` | `#B4753F` | `#C08457` |
| `silver` | `#8D95A1` | `#B9C0CA` |
| `gold` | `#C79320` | `#E8B44A` |
| `platinumInk` | `#5B7C97` | `#D9E6F2` |
| `platinumFill` | `rgba(91,124,151,0.12)` | `rgba(217,230,242,0.14)` |

### Debug / demo affordance (`#if DEBUG` only)

| Token | Light | Dark |
|---|---|---|
| `demoBg` | `rgba(20,22,26,0.03)` | `rgba(255,255,255,0.03)` |
| `demoLine` | `rgba(20,22,26,0.22)` | `rgba(255,255,255,0.22)` |
| `demoChip` | `rgba(20,22,26,0.10)` | `rgba(255,255,255,0.12)` |
| `demoInk` | `#4A4E56` | `#C9CED6` |

### Shadows

| Token | Light | Dark |
|---|---|---|
| `shadow` | `0 20px 44px rgba(18,20,24,0.14)` | `0 22px 48px rgba(0,0,0,0.50)` |
| `shadowSm` | `0 8px 20px rgba(18,20,24,0.08)` | `0 8px 22px rgba(0,0,0,0.34)` |

---

## 2. Typography

**Display / UI:** Plus Jakarta Sans. **Data / codes:** IBM Plex Mono (session IDs and option letters only).
iOS fallback: SF Pro Text (`.system`) with the same weights — Plus Jakarta Sans must be bundled to match the mocks.

| Style | Size | Weight | Tracking | Use |
|---|---|---|---|---|
| `displayL` | 30 | 800 | −3% | Revealed partner name over photo |
| `displayM` | 25 | 800 | −3% | Screen greeting ("Evening, Alex") |
| `displayS` | 22 | 800 | −2.5% | Sheet titles, hidden-name line |
| `title` | 20–21 | 800 | −2% | Card titles, trivia question |
| `titleS` | 16 | 800 | −2% | Chat name, section heads |
| `body` | 14 | 500 | 0 | Message text, option labels |
| `bodyS` | 12.5 | 500 | 0 | Supporting copy, descriptions |
| `label` | 10–11 | 600–700 | +14–20%, UPPERCASE | State labels ("QUEST MODE ACTIVE", "REVEAL") |
| `chip` | 11–12 | 600–700 | 0 | Chips and pills |
| `mono` | 9–12 | 500 | +6–14% | Session codes, option letters |

**Minimum text size anywhere: 9px** (labels only). Body copy never below 11.5px.

---

## 3. Geometry

| Token | Value | Applied to |
|---|---|---|
| `rHero` | 28 | Photo hero cards, quest card, primary sheets |
| `rCard` | 24 | Score, rating, tier, partner-strip panels |
| `rRow` | 20 | Icebreaker option rows, message bubbles, safety rows |
| `rThumb` | 16–18 | Small blurred thumbnails |
| `rPill` | 999 | Chips, CTAs, meters, nav, inputs |
| `rSheet` | 32 (top corners only) | Bottom sheets |
| `gutter` | 16 | Screen horizontal padding |
| `gapBlock` | 14 | Between major blocks |
| `gapTight` | 9 | Between list rows / stacked chips |
| `padCard` | 16–20 | Inside cards |

**Safe-area padding in mocks:** top is **58 from the physical edge** (status bar + breathing room). Bottom is **22 above the home-indicator inset**, not 22 from the physical edge — the prototype's device frame draws over the inset, so read the mocks accordingly on every screen.

**Hit targets:** never below 44×44. Primary CTA height **54**. Secondary **52**. Icon buttons **38–46**.

---

## 4. The reveal ladder (core mechanic — unchanged from v1)

```
blurRadius = 40 * (1 - revealProgress)
```

| Stage | `revealProgress` | Blur | Stage label |
|---|---|---|---|
| 1 | 0.00 | 40px | Nearby |
| 2 | 0.30 | 28px | Icebreaker |
| 3 | 0.70 | 12px | Revealed |
| 4 | 1.00 | 0px | Connected |

Rules:
- Blur is **uniform** over the whole photo. No partial face/eye reveal, ever.
- The blurred image layer is **scaled to 1.18** so the blur never reveals a soft edge at the card bounds.
- `revealProgress` only reaches 1.0 after an explicit **mutual NameDrop**.
- Stage advance animates blur + stepper **together**, 400ms, ease-out. One gesture, one reward.
- Icebreaker actions add **+0.08** each; clamp to the stage ceiling — the real `EncounterSession` math is authoritative.
- **Blur is proportional to rendered width, not absolute.** The 40px ceiling is calibrated to the full-bleed hero (reference width ≈ 361pt). Any smaller instance must scale it: `blur = 40 * (1 - progress) * (width / 361)`. Applied raw, a 62pt thumbnail is an identical featureless blob at every stage and the unblur stops being legible — which defeats the purpose of showing it during play.

---

## 5. Components

### StageStepper
4 equal segments, `height 5`, `rPill`, `gap 6`. Completed/current = `ember`; the current segment also gets `shadow: 0 0 12px emberGlow`. Labels below: 8.5px/700, +8% tracking, uppercase — `emberText` when reached, `text3` when not.

### RevealMeter
Two variants.
- **Over photo:** inside a glass pill (`rgba(255,255,255,0.14)` + `blur(14)` + `rgba(255,255,255,0.20)` border), white track at 24% opacity, white fill, white % label.
- **On surface:** `track` background, `ember` fill, `emberText` % label.
Height 5–6, `rPill`.

### RevealHero
`rHero` card, fills available vertical space (`min-height 200`). Layers bottom→top:
1. Blurred photo, `scale(1.18)`, `blur(Npx)`
2. Scrim: `linear-gradient(180deg, rgba(12,13,15,.5) 0%, transparent 32%, transparent 46%, rgba(12,13,15,.9) 100%)`
3. Glass chips top-left (tier, ID verified); radar pulse top-right at stage 1 only
4. Bottom: name or hidden-name + reveal meter

**Text over imagery is always white, in both themes.** The scrim guarantees contrast.

### GlassChip
`padding 8×13`, `rPill`, `rgba(255,255,255,0.16)`, `backdrop-blur(14)`, `1px rgba(255,255,255,0.24)` border, white text 11px/600–700. Only used **on top of photos**.

### Chip (on surface)
`padding 9×14`, `rPill`, `surface2` fill, `line` border, `text` ink, 11–12px/600.
Variants: **selected** = `cta` fill + `ctaText`; **accent** = `emberSoft` + `emberLine` + `emberText`; **removable** prefixes a 11px `✕`.

### Buttons
- **Primary (commit):** `ember` fill, white text, height 54, `rPill`, `shadow 0 12px 30px emberGlow`. **One per screen, and only for the commit action.**
- **Primary (neutral progression):** `cta` fill / `ctaText`, height 54, `rPill`, `shadowSm`.
- **Ghost:** transparent, `1px lineStrong`, `text2`, height 52.
- **Icon button:** 38–46 circle, `surface` fill, `line` border, `shadowSm`.
- **Send FAB:** 42–48 circle, `ember`, white glyph.

### TierBadge / TrustChip
Diamond glyph `◆` in the tier colour + tier name. On surface: `surface2` pill + `line` border. On photo: GlassChip.
**Never** use medals, stars, XP bars, or confetti.

### TierUpgradeBanner
`rCard`, `surface`, `line` border, breathing glow animation (`0 0 26px` in the **destination tier's** colour at 40%, 3s ease-in-out) — a Silver upgrade glows silver, not platinum. Shows `◆ {from} → ◆ {to}`, the reason line ("Average rating ≥ 4.0 · upgraded just now"), and a 42px circle filled with the destination tier's fill colour on the right. Takes `from:`/`to:` and fires on any tier increase.

### VibeScoreBreakdown
Big number 30px/800 (−3%) + "VIBE MATCH" label. Then rows: 96px label (`text2`) / `track` bar with `ember` fill / right-aligned value.

The `emberSoft` percentile chip ("Top 4% nearby") is **optional** — render it only if the model actually carries a percentile. If there is no backing data, omit it and let the number and label sit alone. Do not stretch the remaining content to fill the row, and never fabricate the figure.

### RatingBar
5 equal segments, height 9, `rPill`, `gap 6`, `ember` when filled, `track` when not. Numeric value 16px/800 to the right. **No stars.**

### IcebreakerOptionRow
`rRow`, `padding 16×18`. Default: `surface2` + `line` + 600 weight + mono letter (A/B/C/D) in `text3`.
Correct/selected: `emberSoft` + `1.5px ember` + 700 weight + 22px `ember` circle with white `✓`.

### WordChainPill / Input
Chain pills: `rPill`, `padding 10×14`. Theirs = `surface2` + `line`; yours = `emberSoft` + `emberLine`; open slot = 700 weight + `lineStrong`.
Input: `rPill` row, `surface2`, `1.5px ember`, 42px ember send FAB inset right.

### QuestCard
`rHero`, `surface`, `shadow`. The active-state card for the app's scanning mode.

**Active:** **`emberLine` border** (the only ember-bordered surface in the app), a 3px sweeping `ember` indeterminate bar pinned to the top edge, live dot + state label, ember radar pulse, title describing what is happening, description, constraint chips.

**Inactive:** `line` border, **no sweep bar, no radar pulse**, state label in `text2`. The card must read as unmistakably off — the ember border and the motion are the entire signal that the app is live.

The progress bar and `n / m quests` row are **conditional on a quest content model existing**. If the product's quest mode is a scanning boolean with no quest objects, omit both and let the title describe the actual behaviour. Do not invent counts or an end time.

### DemoControl (`#if DEBUG`)
`rCard 22`, `demoBg` fill, **1px dashed `demoLine`**. A `DEBUG` mono chip in `demoChip`/`demoInk` at a **squared 7pt radius — deliberately not a pill**: every interactive element in the product is a pill, so a squared chip puts the debug affordance in a different visual register and stops it reading as product UI. Then the caption "Developer bypass · not shipped", a ghost pill "Simulate encounter" and a 44px reset circle. Dashed border + squared mono chip are the only signals — no yellow/black hazard styling, no warning tint, no emoji.

### FloatingTabBar
`rPill`, `nav` fill, `padding 8`, `shadow`. 4 items at 56×44. Active = `navActive` pill with `navActiveInk` glyph; inactive glyphs `navInk`.

### SafetySheet
Scrim `rgba(8,9,11,0.66)` + `blur(3)` over the dimmed screen. Sheet: `rSheet` top corners, `bg` fill, 40×5 grabber. Rows are `rRow` with a 34px circular icon. Only the report row uses `danger` (ink, icon, and a `rgba(229,72,77,0.34)` border).

---

## 6. Screens

| Screen | Purpose | Key notes |
|---|---|---|
| **HomeView** | Quest mode + nearby signals + demo entry | Quest card is the hero. Nearby signals are blurred photo cards (22–26px) with glass tier chips. Tab bar floats over content. |
| **EncounterView** | The reveal ladder, 4 stages | Top bar → stepper → RevealHero → score/chips (stages 1–3) or rating + tier upgrade (stage 4) → CTA → safety line. CTA copy per stage: `Start icebreaker` / `Resume icebreaker` / `NameDrop to connect` / `Say hello`. Only stage 3 uses the ember CTA. See §6.1 for stage-1 gating, the icebreaker chooser, and the top bar. |
| **IcebreakerView** | Trivia + Word chain | Persistent partner strip (blurred thumb + live reveal meter) so the unblur is visible during play. Feedback banner above the CTA. |
| **Connected chat** | Post-NameDrop conversation | Unblurred avatar + verify check, "You connected" summary card, shared-interest chips, persistent safety prompt above the composer. |
| **Trust centre** | Tier ladder + verification | Current tier card with 4-segment metallic ladder, then a row per tier with its requirement. Closing disclaimer: tiers are not a ranking. |
| **Safety sheet** | Report / end / share location | Reachable from every encounter via the shield icon button. |

---

### 6.1 EncounterView — states the base layout does not cover

**Top bar.** Left: a close `✕` icon button — ending an encounter must never be buried in a menu. Right: `⋯` overflow (contains *End encounter* as a labelled duplicate), and the `⛨` shield that opens the SafetySheet. Ship the shield only once the SafetySheet exists; until then the top bar is `✕` left, `⋯` right.

**Stage 1 — approach gate.** If the product gates the icebreaker on real proximity, the CTA carries that state rather than sitting disabled:

| Condition | CTA treatment |
|---|---|
| Approaching | Ghost pill (`lineStrong` border, `text2`), non-committal copy showing live distance — e.g. *"120 m away · keep walking"* |
| In range | Neutral `cta` pill, *"Start icebreaker"* |

A disabled primary pill is a dead end; a pill that reports distance is part of the reveal narrative. Feed the same live distance into the top-bar proximity label.

**Stage 1 — choosing a game.** Two primary pills would break the one-primary-per-screen rule, and a confirmation dialog adds a tap. Instead place a **selectable chip pair** (`Trivia` / `Word chain`) directly above the CTA, using the standard Chip selected state (`cta` fill + `ctaText`), one selected by default. The single CTA then launches the selected game.

**Stage 2 — Resume.** While an icebreaker is presented, this CTA is not visible; it is only reachable if the sheet was dismissed. Copy is therefore *"Resume icebreaker"*, and it re-presents the active session. Disable it only if no session exists.

**Identity line (pre-connect).** The hero's secondary line reads **`Identity locked · A7-F3`** — the words carry the product promise (the name is deliberately withheld), the code is display-only. A bare session ID is cold and tells the user nothing about why they cannot see a name. Derive the code from the match identifier: first four hex characters, uppercased. Never actionable.

**Stage 4 — CTA before chat exists.** `Say hello` is the shipped copy and assumes a chat destination. Until that destination is built, do **not** render it disabled — the same dead-end rule applies here as at stage 1. Substitute *"Done"*, wired to end the encounter. This also closes the demo loop so the 60-second path can be run repeatedly. Restore `Say hello` when chat lands.

**Verification check.** The mock shows the stage-4 verify check always present because its partner is fixed. In implementation, gate it on real verification state — §1 reserves `verify` for confirmed identity only.

**Stage captions.** Earlier per-stage captions ("Unblurring as you break the ice…", "Vibe passed…") are intentionally absent. The stepper label, the reveal meter and the CTA already carry that message three times over. If a stage change feels under-announced, emphasise the **current stepper label on advance** — do not reintroduce caption text.

### 6.2 IcebreakerView — states the base layout does not cover

**FeedbackBanner carries confirmation, not arithmetic.** Show the outcome ("Matched — you both picked B", "Strong link") and nothing more. Do not print a reveal delta: the meter in the partner strip already reports progress live, and a hard-coded figure will drift from whatever the session actually awards. If the real mechanic ramps continuously, the meter is the honest display.

**Round timer.** Not in the mocks, but real behaviour. Place it in the progress row opposite the pips. Escalate by **contrast, not hue**: `text2` normally, `text` at full contrast in the final quarter, with an optional subtle opacity pulse. Do **not** introduce a warning colour — `ember` means progress and commitment, `danger` is reserved for destructive actions, and a low-stakes game timer does not justify expanding the palette.

**Partner strip is persistent.** Render it whenever a partner exists, not only in demo builds — it is what makes the unblur legible during play, and gating it on demo means production never gets the effect.

**Chain alternation reflects real turns only.** Theirs-neutral / yours-ember styling depicts a genuine two-player exchange. If the implementation is single-player (only a seed word from the partner), style it truthfully rather than faking alternation. The styling is already in place for when real partner input lands.

**Typed word input.** §5's `WordChainPill / Input` specifies the pill input and ember send FAB, but accepting arbitrary typed words requires a rule for what counts as a valid link — that is a game mechanic, not a skin. Until that rule exists, option rows are the correct interaction and the input stays unbuilt.

### 6.3 HomeView — states the base layout does not cover

**Never render a place name derived from the user's position.** The mock's subtitle reads "Mission district · 6 signals near"; the neighbourhood must not ship. Naming where the user is standing is exactly the location exposure this product exists to avoid — and it appears on the least-protected screen in the app. Ship the count alone. This generalises: no neighbourhood, city, venue or landmark inferred from location, anywhere.

**Quest Mode toggle.** The mock's card is a display; in implementation it is also the app's only on/off control. Place the toggle top-right of the card with the radar pulse beneath it, and make sure the inactive card treatment above is applied — a card that looks identical when off is a bug.

**Signal cards degrade gracefully.** The mock's primary line is distance ("40 m away"). If per-user distance is not available outside debug, promote vibe match to the primary line and keep the glass tier chip; drop the line entirely when no match record backs a profile. Do not approximate a distance.

**Tab count follows real destinations.** The mock draws four; ship only what exists. The floating bar's geometry is unaffected — items stay 56×44 and the bar hugs its content.

## 7. Motion

| Interaction | Spec |
|---|---|
| Stage advance | blur + stepper + meter animate together, 400ms, ease-out |
| Live/presence dot | opacity 1 → 0.28 → 1, 2s, ease-in-out, infinite |
| Radar pulse | scale 0.6 → 2.4, opacity 0.6 → 0, 2.6s ease-out, two rings offset 1.3s |
| Quest sweep bar | translateX(−100% → 300%), 2.8s ease-in-out, infinite |
| Tier upgrade glow | box-shadow 0 → 26px platinum → 0, 3s ease-in-out, infinite |
| Button press | scale 0.97, 120ms |

---

## 8. Rules

**Do**
- Let the photo be the largest object on screen at every encounter stage.
- Keep exactly one primary pill per screen.
- Use the dark scrim + white text over imagery in both themes.
- Reserve `ember` for progress and commitment; let neutral `cta` carry ordinary progression.
- Keep the safety line on every pre-connect screen.

**Avoid**
- Pink/purple gradients, neon, heavy glows.
- `ember` as a large surface fill — it is an accent.
- Gamified trust: XP, badge shelves, confetti on verification.
- Partial face or eye reveal; any non-uniform blur.
- Neumorphic double/emboss shadows (softness was borrowed from the reference, the emboss was not).
- Auto-revealing without mutual consent.
- Rendering any place name — neighbourhood, city, venue, landmark — inferred from the user's location. The count of nearby signals is the only spatial fact that ships outside an active encounter.


---

## 9. Form primitives

The vocabulary for the ~30 views §5 has no words for: settings, profile setup, auth, reporting, data rights. Lives in `Views/Components/DQFormParts.swift`.

**Extends §3 geometry:** `rField` = **16** — text fields, text areas, segmented tracks. Sits below `rRow` 20.

### DQGroup / DQRow
Group: `rCard` 24, `surface` fill, 1pt `line` border, contents clipped. Row: min height **56**, padding 14×18, 14pt gap to trailing content. Label 600/14 `text`; sub-label 500/11.5 `text2`. Divider 1pt `line`, **inset 18** on the leading edge, never after the last row.
**Rows carry no icons** — leading glyphs stay reserved for trust, live and verify, which is also what keeps a settings list from reading as a badge shelf.

### DQSectionHeader / footnote
Header 600/9.5, +20% tracking, uppercase, `text3`, 18pt leading inset, 9pt above the group, **outside** the card. Footnote below a group: 500/11 `text3`, same inset.

### DQValueRow
`DQRow` + right-aligned mono value (500/13 `text2`) + `›` chevron 600/15 `text3`. Push navigation.

### DQTextField / DQTextArea
Height **52**, padding 0×16, background **always** `surface2` with 1pt `line` — identical on `bg` and inside a `surface` card. One rule, no context switch.
Label 600/9.5 +16% uppercase `text2`, 7pt above. Error 500/11 `danger`, 7pt below.
- **Focus:** border 1.5pt `cta`. No glow. **Never ember** — see the ember rule below.
- **Disabled:** opacity 0.45. Geometry and border unchanged.
- **Text area:** min height 84, padding 14×16, counter 500/10.5 mono `text3` right-aligned in the label row.

### DQToggleRow
Toggle 51×31, knob 27 white + `0 2px 6px rgba(0,0,0,0.28)`. On = `ember`; off = `track`.

### DQStepperRow
34×34 buttons, radius 11, `surface` fill, inside a 4pt-padded `surface2` track of radius 14. Value 500/15 mono, min width 30, centred. Disabled bound: glyph drops to `text3`.

### DQSliderRow
Header row: label 600/14 `text` left, value 500/13 mono **`emberText`** right. Track 6pt `track`, fill `ember`, knob 22 circle `surface` + 1pt `line` + `shadowSm`.

### DQSegmentedPicker
2–3 options only. 4pt-padded `surface2` track at `rField` 16; segments radius 12, 11pt vertical padding. Selected = `cta` fill + `ctaText` at 700/12.5 — the same solid-active-indicator idiom as the floating tab bar. Unselected 600/12.5 `text2`. Stands alone; not inside a `DQGroup`.

### DQDangerRow / DQConfirmSheet
Row: label text in `danger`, chevron unchanged. **A filled danger pill never appears on a settings row** — only inside the confirm step: `rCard`, `surface`, `rgba(229,72,77,0.28)` border, title 700/13, body 500/11.5 `text2`, 44pt `danger` pill with white 700/13 label.
Account deletion is covered by `danger`.

### DQEmptyState
Centred: 44pt `surface2` circle with a 17pt glyph in `text3`, title 700/14, body 500/11.5 `text2`, ghost pill action (11×20, 1pt `lineStrong`, 600/12.5 `text2`).

### DQSkeleton
Bars at radius 10 on `surface2`, shimmer sweep through `lineStrong`, 1.5s linear infinite. **Spinner only for waits under ~1 second**; anything longer gets skeletons shaped like the content that is coming.

### DQTopBar
Custom, **not a `NavigationStack` toolbar** — the floating round button is already the app's back language, and a system toolbar would import a second design system halfway through the app.
- Root: large title 800/21 at −2.5% tracking, optional 34pt circular `surface2` trailing action.
- Pushed: 38pt back circle (`surface` + 1pt `line`), title 700/15 centred, optional trailing text action 600/13 `emberText`.

### DQAuthButton
All 52pt, `rPill`. Filled = `cta`/`ctaText` 700/14. Ghost = 1pt `lineStrong`, 600/14 `text`, provider glyph 17pt. Plain text = 44pt, 600/13 `text2`.
**OAuth keeps the one-primary-pill rule:** Apple is the single filled neutral CTA, every other provider is ghost, and provider colour is confined to the glyph.

### Ember in forms
Ember appears in a form in **exactly one** place: a value the user is tuning live — the slider fill and its mono readout. Not focus, not selection, not validation success. This is what keeps ember meaningful on the encounter surfaces.

### Values are mono, words are Jakarta
Counts, distances, dates, ratings, IDs → IBM Plex Mono. Prose and labels → Plus Jakarta Sans. Extends §2's data voice from session codes to all numeric values.

### Not reusable: StageStepper
`StageStepper` reads as reveal progress and must not be reused for onboarding steps. Onboarding gets a plain dot row.

### XP is not gamified trust
§8 forbids gamified **trust**. XP is a separate axis and may be displayed in `StatsView`: mono, neutral ink, plain `surface` card. Never beside a tier badge, never a level-up moment, never confetti.


---

## 10. Onboarding progress & blocking commits

Two primitives §9 did not name. `ProfileSetupView` and the 7 step views are blocked on them.

### DQStepDots
Onboarding step progress. **Not `StageStepper`** — that meter means reveal progress and must not appear where nothing is being revealed.
- Dots **6pt**, gap **6pt**. The current step elongates to a **20×6** pill. That elongation is the *only* state difference, so a dot row can never be misread as a filled meter.
- Completed `text3` · current `text` · upcoming `track`. **Neutral throughout — no ember**, no fill sweep, no connecting line.
- Centred, **12pt below `DQTopBar`**, 24pt above content. Width animates `.28s ease-out`; colour crossfades on the same curve.
- **No mono "3 of 7" readout.** The dots are the count; a number beside them states it twice.
- **Not tappable.** Display only — reverse navigation belongs to `DQTopBar`.
- Above ~10 steps, stop. A flow that long needs sections, not more dots.

### DQBlockingSave
Full-screen overlay for a commit the user cannot cancel.
- **Skeleton vs spinner is fetch vs commit, not duration** — this supersedes §9's "under ~1 second" wording as the governing test. A *fetch* has a known incoming shape, so it skeletons. A *commit* has no shape to preview (the user is leaving the screen), so it spins, however long it takes.
- `scrimHeavy` + **14pt blur** over the form being committed; the form stays visible beneath at reduced contrast, so the user can see what is being saved.
- Card: `rCard` 24, `surface`, 1pt `line`, padding 24/26, min width 196, `shadow`.
- Spinner **22pt, 2pt stroke**, `track` ring with a `text` head, .8s linear. **Never ember** — ember is not a waiting colour.
- Title 600/13.5 `text`, present continuous ("Creating your profile…"). Sub-line 500/11.5 `text2`, centred, optional.
- **No cancel button, no progress bar.** If the work can be cancelled it is not blocking — use an inline field state instead.
- **Minimum 400ms on screen** so a fast save does not flash. Past **8s** the sub-line swaps to "Still working — you can keep waiting or try again later". Never a silent hang.
- Blocks all input including the back gesture until it resolves or fails.


---

## 11. RadarView

Mock: `RadarScreenV2.dc.html`. Live proximity HUD.

### The governing ruling: distance, not direction
The radar shows **how close, never which way**. Proximity comes from ranging, not bearing — a blip placed at a true heading would be a precision the data does not have, and it would invite the user to walk at a stranger.
- Blips sit on their **distance ring** at a stable but arbitrary angle. Angle must be **stable per person per session** (hash the peer id) so a blip does not jitter around the ring between refreshes.
- The caption "Direction isn't shown — only how close." is **required**, 500/11 `text3`, centred under the plot. It is not decoration; it is the thing that stops the screen lying.
- **No sweep line, no compass rose, no cardinal marks.** A rotating sweep is the radar cliché and it implies bearing.

### Plot
- Square, full content width, centred. Three rings: outer at 1pt `line`, middle 1pt `line`, inner (the encounter radius) 1pt `lineStrong` — the one ring that means something gets the stronger stroke.
- Ring labels in mono 9.5 `text3`, sitting **on** the ring at 12 o'clock with a `bg` gutter behind them. The encounter-radius label is `emberText`.
- Ring distances follow the user's radius setting: inner = radius, middle = radius×2.4, outer = radius×5, rounded to something legible. Do not hardcode 50/120/250.
- Self dot 13pt `ember` with a 5pt `emberSoft` halo, dead centre.
- Two `emberLine` pulse rings expand from the inner ring, 3.4s, offset 1.7s. This is the same pulse as `EncounterView` — same duration, same curve.

### Blips
- **In radius:** 15pt `ember` with a glow, label `emberText`. **Out of radius:** 11pt `text2`, label `text3`. **Far band:** 9pt `text3`. Size and ink carry proximity; nothing else does.
- Distance label mono 10, 5pt under the blip. **No names, no photos, no tier badges on the plot** — the plot is anonymous until an encounter starts.
- Idle breathing only (opacity .85→1, ~3s, staggered per blip). Blips never slide between positions; they cross-fade on refresh.

### In-radius card
Bottom of the screen, only when someone is inside the radius. `rCard` 24, `surface`, **1pt `emberLine` border** — the border is what marks it live.
- Avatar 50pt at `rField` 16, blurred by `revealProgress` per §4's reveal rule. Distance mono 14 `emberText`. Tier glyph allowed **here** (one 10pt diamond, no label) because the encounter is now a named relationship. Sub-line 500/11.5 `text2`.
- Trailing `Start` pill: filled `cta`, 40pt. One primary per screen, and on this screen it is the only pill.

### Empty and paused
- Nothing in range: keep the rings and the self dot, drop the card, and use `DQEmptyState` copy inline under the caption — never an empty circle with no explanation.
- Inside a pause zone: rings render at `track` instead of `line`, self dot goes `text3`, pulse stops, and a `surface` strip reads "You're invisible here." No blips at all — not greyed blips, **none**. Being paused must not leak who is nearby.
- Header count is a bare count: "4 signals · live". **No place name, ever** (§8).

---

## 12. LivenessCheckView — copy over a live feed

- The feed is a **viewfinder, not a background**: inset from the screen edges, `rHero` 28, 1pt `line`. Never full-bleed behind chrome.
- **Text never sits directly on the feed.** Instruction copy goes on a `scrimHeavy` plate (min 44pt tall, 16pt padding, `rField` 16) or in a `surface` card outside the feed. A live feed's luminance is unknowable, so contrast has to be manufactured, not hoped for.
- Instruction 600/15 `text` centred, one line where possible. Secondary 500/11.5 `text2`.
- Success ring uses `verify`, failure `danger`. **Never ember over the feed** — ember means proximity elsewhere in the app and must not pick up a second meaning here.
- No skeletons over a live feed. If the camera is warming, the frame is empty with the instruction plate already in place.
- Capture button follows `DQAuthButton` filled geometry, 52pt, on the plate — not floating on the feed.

## 13. OAuth in OnboardingView
Already governed by §8's one-primary-pill rule; no exception. Apple is the single filled neutral `cta` button. Every other provider is ghost (1pt `lineStrong`, 600/14 `text`) with the provider's colour confined to its 17pt glyph. Email is the plain-text variant. This satisfies both Apple's and Google's brand requirements — both permit a monochrome-wordmark-on-neutral treatment — while keeping one primary per screen.
