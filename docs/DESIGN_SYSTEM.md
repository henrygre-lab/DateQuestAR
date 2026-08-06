# Serendipity DesignSystem v2 (DQ tokens)

Dual-theme (light + dark), warm, photo-forward. This file is the **single source of truth** for tokens.
Everything below is expressed as a semantic token — never hard-code a raw hex in a view.

> **This repo copy is canonical.** Design rulings are made in review and written
> in here by whoever implements them; there is no second copy to reconcile
> against. If the spec and a mock disagree, the spec wins on values — but where
> a mock is making a copy or intent argument the spec doesn't address, raise it
> rather than silently deferring. Implementation status, and every place the
> code knowingly departs from this file, lives in `UI_REWORK_STATUS.md`.

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
| `danger` | `#E5484D` | `#E5484D` | Report / destructive **only** — never decorative. Covers account and data deletion. As row-label ink in a list; as a filled pill **only** inside a confirm step, never on a settings row. |

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

### Scrims

| Token | Light | Dark | Use |
|---|---|---|---|
| `scrimHeavy` | `rgba(239,239,241,0.72)` | `rgba(10,11,13,0.72)` | Behind a blocking commit overlay — takes the form out of reading contrast while leaving it recognisable |

### Shadows

| Token | Light | Dark |
|---|---|---|
| `shadow` | `0 20px 44px rgba(18,20,24,0.14)` | `0 22px 48px rgba(0,0,0,0.50)` |
| `shadowSm` | `0 8px 20px rgba(18,20,24,0.08)` | `0 8px 22px rgba(0,0,0,0.34)` |

---

## 2. Typography

**Display / UI:** Plus Jakarta Sans. **Data / codes:** IBM Plex Mono.

**Values are mono, words are Jakarta.** Counts, distances, dates, ratings, session IDs and option letters set in IBM Plex Mono; all prose and every label in Plus Jakarta Sans. A word that happens to sit in a value slot — a selected reason, a status — is still a word, and stays Jakarta.
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
| `mono` | 9–12 | 500 | +6–14% | Counts, distances, dates, ratings, session codes, option letters |

**Minimum text size anywhere: 9px** (labels only). Body copy never below 11.5px.

---

## 3. Geometry

| Token | Value | Applied to |
|---|---|---|
| `rHero` | 28 | Photo hero cards, quest card, primary sheets |
| `rCard` | 24 | Score, rating, tier, partner-strip panels |
| `rRow` | 20 | Icebreaker option rows, message bubbles, safety rows |
| `rField` | 16 | Text fields and text areas |
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

### Liquid Glass — where the material may go

The app targets iOS 26, so the frosted surfaces this spec described in CSS terms
(`rgba(255,255,255,0.16)` + `backdrop-blur(14)`) are now the platform's own
material rather than something hand-rolled. Everything below that says "glass"
means `.glassEffect`, applied through `dqGlass` so the tints stay tokens.

**Glass is the layer above content, and only that layer.** It goes on:

- chrome floating over a photo or a camera feed — GlassChip, the over-photo
  RevealMeter, the radar and liveness HUD controls;
- chrome floating over app content — icon buttons, the FloatingTabBar, the chat
  composer.

It does **not** go on content: cards, rows, panels, form fields, sheets and the
blocking-save overlay all stay on the opaque `surface` tokens. A screen where
everything is glass has nothing left for glass to float above, and the
RevealHero in particular has to stay the brightest object on screen (§8).

Two consequences at every call site:

- **No border.** The material draws its own specular edge. The 1pt white
  strokes this spec previously asked for on GlassChip and the RevealMeter are
  gone — stacking a painted border on a lit edge is the exact look the material
  replaces.
- **No drop shadow under small chrome.** Glass carries its own separation.
  Shadows survive only where an element is genuinely lifted off the page — the
  tab bar keeps `shadow`, the 38pt icon buttons dropped `shadowSm`.

Reduce Transparency and Increase Contrast are handled by the material; no
surface branches on them.

### StageStepper
4 equal segments, `height 5`, `rPill`, `gap 6`. Completed/current = `ember`; the current segment also gets `shadow: 0 0 12px emberGlow`. Labels below: 8.5px/700, +8% tracking, uppercase — `emberText` when reached, `text3` when not.

**Not reusable for onboarding.** The stepper reads as *reveal* progress — borrowing it for a signup flow imports a meaning that isn't there. Multi-step onboarding gets a plain dot row instead.

### RevealMeter
Two variants.
- **Over photo:** inside a glass pill tinted `rgba(255,255,255,0.14)`, white track at 24% opacity, white fill, white % label. No border — see the Liquid Glass rules above.
- **On surface:** `track` background, `ember` fill, `emberText` % label. Bare — no pill, it sits directly on the card.
Height 5–6, `rPill`.

### RevealHero
`rHero` card, fills available vertical space (`min-height 200`). Layers bottom→top:
1. Blurred photo, `scale(1.18)`, `blur(Npx)`
2. Scrim: `linear-gradient(180deg, rgba(12,13,15,.5) 0%, transparent 32%, transparent 46%, rgba(12,13,15,.9) 100%)`
3. Glass chips top-left (tier, ID verified); radar pulse top-right at stage 1 only
4. Bottom: name or hidden-name + reveal meter

**Text over imagery is always white, in both themes.** The scrim guarantees contrast.

### GlassChip
`padding 8×13`, `rPill`, glass tinted `rgba(255,255,255,0.16)`, white text 11px/600–700, no border. Only used **on top of photos**.

### Chip (on surface)
`padding 9×14`, `rPill`, `surface2` fill, `line` border, `text` ink, 11–12px/600.
Variants: **selected** = `cta` fill + `ctaText`; **accent** = `emberSoft` + `emberLine` + `emberText`; **removable** prefixes a 11px `✕`.

### Buttons
- **Primary (commit):** `ember` fill, white text, height 54, `rPill`, `shadow 0 12px 30px emberGlow`. **One per screen, and only for the commit action.**
- **Primary (neutral progression):** `cta` fill / `ctaText`, height 54, `rPill`, `shadowSm`.
- **Ghost:** transparent, `1px lineStrong`, `text2`, height 52.
- **Icon button:** 38–46 circle of interactive glass, `text` glyph. The material supplies what was previously `surface` + `line` + `shadowSm`, and reacts to the press as well.
- **Send FAB:** 42–48 circle, `ember`, white glyph. **Stays solid** — it is a commit action and ember has to read at full strength.

The pill buttons stay solid too. `.glass` / `.glassProminent` button styles are **not** used anywhere: the ember commit pill is the loudest thing on its screen by design, and a translucent version of it is a weaker CTA, not a more modern one.

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

### Form, auth & system chrome

Built in `Views/Components/DQFormParts.swift`.

**Rows & groups.** Row min height 56, padding 14 vertical / 18 horizontal, 14 between the label block and trailing content. Label 600/14; sub-label 500/11.5 `text2`. Divider 1pt `line`, inset 18 on the leading edge, never after the last row. Group `rCard`, `surface`, 1pt `line`, contents clipped. Section header 600/9.5 at +20% tracking, uppercase, `text3`, 18 leading inset, 9 above the group and outside the card. Footnote below a group 500/11 `text3` on the same inset. `DQValueRow` adds a mono value and a 600/15 `text3` chevron.

**Fields.** Height 52, horizontal padding 16, `rField`. Background is **always** `surface2` with a 1pt `line` border — identical on `bg` and inside a `surface` card; never varied by context. Field label 600/9.5 +16% uppercase `text2`, 7 above; error 500/11 `danger`, 7 below. Focus: 1.5pt `cta` border, caret `text`. Disabled: opacity 0.45, geometry and border unchanged. Text area min height 84, padding 14/16, counter 500/10.5 mono `text3` right-aligned in the label row.

**Controls.** Toggle 51×31, knob 27 white with a soft shadow, on = `ember`, off = `track`. Stepper: 34×34 buttons at radius 11 on `surface`, inside a 4-padded `surface2` track at radius 14; value 500/15 mono, min width 30, centred. Slider: 6pt track, `ember` fill, knob 22 `surface` + 1pt `line` + `shadowSm`; header value 500/13 mono `emberText`. Segmented picker: 4-padded `surface2` track at radius 16, segments radius 12, 11 vertical padding; selected = `cta` + `ctaText` 700/12.5, unselected 600/12.5 `text2`. Stands alone, never inside a group, **2–3 options only** — beyond that the choice belongs in a menu or a pushed list.

**Top bars.** Root title 800/21 at −2.5%. Pushed title 700/15, centred. Back button 38 circle, `surface`, 1pt `line`. Trailing text action 600/13 `emberText`.

**Auth buttons.** 52pt, pill. Filled = `cta`/`ctaText` 700/14. Ghost = 1pt `lineStrong`, 600/14 `text`, provider glyph 17. Plain text = 44pt, 600/13 `text2`.

**Empty & loading.** Empty state: 44 `surface2` circle with a 17 glyph in `text3`, title 700/14, body 500/11.5 `text2`, ghost pill action padded 11×20. Skeletons radius 10 on `surface2`, shimmer through `lineStrong`, 1.5s linear infinite, shaped like the content they stand in for.

**Skeleton vs spinner is FETCH vs COMMIT, not duration.** A fetch has a known incoming shape, so it skeletons. A commit has no shape to preview — the user is leaving the screen — so it spins, however long it takes. (This supersedes any earlier "under about a second" wording.)

**Step dots** — onboarding step progress. Dots 6, gap 6; the current step elongates to a 20×6 pill, and that elongation is the **only** state difference, so a dot row can never be misread as a filled meter. Completed `text3` · current `text` · upcoming `track`. Neutral throughout — no ember, no fill sweep, no connecting line. Centred, 12 below the top bar and 24 above content. Width animates 0.28s ease-out, colour crossfades on the same curve. No mono "3 of 7" readout — the dots are the count. Not tappable: reverse navigation is the top bar's job. Above ~10 steps it stops scaling; a flow that long needs sections, so assert or clamp rather than render 14 dots.

**Blocking save** — a commit the user cannot cancel. `scrimHeavy` + 14 blur over the form, which stays visible beneath at reduced contrast so the user can see what is being saved. Card `rCard`, `surface`, 1pt `line`, padding 24/26, min width 196, `shadow`. Spinner 22 at 2pt stroke — a `track` ring with a `text` head, 0.8s linear. **Never ember: ember is not a waiting colour.** Title 600/13.5 `text`, present continuous ("Creating your profile…"); optional sub-line 500/11.5 `text2`, centred. No cancel button, no progress bar — if the work can be cancelled it is not blocking, and belongs in an inline field state. Minimum 400ms on screen so a fast save does not flash; past 8s the sub-line swaps to "Still working — you can keep waiting or try again later". Never a silent hang. Blocks all input including the back gesture until it resolves or fails.

### QuestCard
`rHero`, `surface`, `shadow`. The active-state card for the app's scanning mode.

**Active:** **`emberLine` border** (the only ember-bordered surface in the app), a 3px sweeping `ember` indeterminate bar pinned to the top edge, live dot + state label, ember radar pulse, title describing what is happening, description, constraint chips.

**Inactive:** `line` border, **no sweep bar, no radar pulse**, state label in `text2`. The card must read as unmistakably off — the ember border and the motion are the entire signal that the app is live.

The progress bar and `n / m quests` row are **conditional on a quest content model existing**. If the product's quest mode is a scanning boolean with no quest objects, omit both and let the title describe the actual behaviour. Do not invent counts or an end time.

### DemoControl (`#if DEBUG`)
`rCard 22`, `demoBg` fill, **1px dashed `demoLine`**. A `DEBUG` mono chip in `demoChip`/`demoInk` at a **squared 7pt radius — deliberately not a pill**: every interactive element in the product is a pill, so a squared chip puts the debug affordance in a different visual register and stops it reading as product UI. Then the caption "Developer bypass · not shipped", a ghost pill "Simulate encounter" and a 44px reset circle. Dashed border + squared mono chip are the only signals — no yellow/black hazard styling, no warning tint, no emoji.

### FloatingTabBar
`rPill`, glass tinted with `nav`, `padding 8`, `shadow`. 4 items at 56×44. Active = `navActive` pill with `navActiveInk` glyph; inactive glyphs `navInk`.

`nav` is near-opaque, so it lands as a tint at reduced strength rather than as a fill — used raw it would cancel the material out. Tinting rather than dropping the token is what keeps the bar reading as dark chrome in *both* palettes; untinted glass would put `navInk` grey on light glass the moment a light theme ships.

**The active pill stays opaque.** It carries `navActiveInk` at full contrast, and a second glass layer inside the bar would either merge with it or wash the ink out. It slides between items instead (~320ms, springy), which is the motion the material implies anyway.

### SafetySheet
Scrim `rgba(8,9,11,0.66)` + `blur(3)` over the dimmed screen. Sheet: `rSheet` top corners, `bg` fill, 40×5 grabber. Rows are `rRow` with a 34px circular icon. Only the report row uses `danger` (ink, icon, and a `rgba(229,72,77,0.34)` border).

---

## 6. Screens

| Screen | Purpose | Key notes |
|---|---|---|
| **HomeView** | Quest mode + nearby signals + demo entry | Quest card is the hero. Nearby signals are blurred photo cards (22–26px) with glass tier chips. Glass tab bar floats over content, which scrolls under it behind a soft scroll-edge effect. |
| **EncounterView** | The reveal ladder, 4 stages | Top bar → stepper → RevealHero → score/chips (stages 1–3) or rating + tier upgrade (stage 4) → CTA → safety line. CTA copy per stage: `Start icebreaker` / `Resume icebreaker` / `NameDrop to connect` / `Say hello`. Only stage 3 uses the ember CTA. See §6.1 for stage-1 gating, the icebreaker chooser, and the top bar. |
| **IcebreakerView** | Trivia + Word chain | Persistent partner strip (blurred thumb + live reveal meter) so the unblur is visible during play. Feedback banner above the CTA. |
| **Connected chat** | Post-NameDrop conversation | Unblurred avatar + verify check, "You connected" summary card, shared-interest chips, persistent safety prompt above the composer. The composer is glass — pinned chrome the transcript scrolls under — with a solid ember send FAB. |
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
| Tab selection | active pill slides between items, ~320ms, springy — not a cross-fade |

---

## 8. Rules

**Do**
- Let the photo be the largest object on screen at every encounter stage.
- Keep exactly one primary pill per screen.
- Use the dark scrim + white text over imagery in both themes.
- Reserve `ember` for progress and commitment; let neutral `cta` carry ordinary progression.
- Keep the safety line on every pre-connect screen.
- **Focus is neutral.** A focused field takes a 1.5pt `cta` border — no glow, no ember. Ember appears in a form in exactly one place: a value the user is tuning live (a slider fill and its readout). Not focus, not selection, not validation success.
- **Custom top bars, not `NavigationStack` toolbars.** The floating round back button is the app's language. `NavigationStack` stays where it drives real pushes; its bar is hidden.
- **Rows carry no icons.** Leading glyphs stay reserved for trust, live and verify states, so they keep meaning something.
- **In auth, the one primary pill is the neutral filled button.** Every other provider is ghost, and provider colour is confined to the glyph.
- **Reach for glass over a camera feed.** Fixed fills are the wrong tool there — a 50%-black disc disappears in a dark room, and a 6%-white one disappears everywhere. The material is the only chrome that holds against a frame the user is actively moving.

**Avoid**
- Pink/purple gradients, neon, heavy glows.
- `ember` as a large surface fill — it is an accent.
- **Glass on the content layer.** Cards, rows, panels, fields, sheets and the blocking-save overlay stay opaque. Glass is what floats *above* content; make everything glass and nothing is floating.
- **Borders and drop shadows on small glass chrome.** The material already draws an edge and its own separation. Painting another one over it is the look Liquid Glass replaced.
- Gamified *trust*: badge shelves, tier celebrations, confetti on verification. This is about the trust ladder, not XP — XP may be displayed (mono, neutral ink, plain surface card), just never beside a tier badge, never as a level-up celebration.
- Partial face or eye reveal; any non-uniform blur.
- Neumorphic double/emboss shadows (softness was borrowed from the reference, the emboss was not).
- Auto-revealing without mutual consent.
- Rendering any place name — neighbourhood, city, venue, landmark — inferred from the user's location. The count of nearby signals is the only spatial fact that ships outside an active encounter. *Inside* an active encounter a live distance to the one person you are already meeting is permissible; a place name still is not. And a distance is never approximated to fill the slot — if the figure is not available, the line goes.
