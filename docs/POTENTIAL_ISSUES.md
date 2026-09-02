# Serendipity — Known Risks & Design Mandates

Every risk here has a mandated mitigation implemented (or explicitly tracked as in-progress) at the code level. This doc is the canonical source of truth for why specific safety decisions were made.

## Risk Summary

| # | Risk | Severity | Implementation Status |
|---|------|----------|-----------------------|
| 0 | Ungated pool / cross-campus exposure | Critical | **Implemented** — school gate, `CommunityGate`, `firestore.rules` |
| 1 | Gender Imbalance / Male Overload (Dating only) | Critical | **Implemented** — `AlertCapManager`, `BalanceEnforcer`, intent lock + 24h cooldown |
| 2 | Misrepresentation & Lying | High | **Implemented** — `LivenessDetector`, trust tiers, post-meet rating |
| 3 | Swarm / Stratification | High | **Implemented** — `RevealManager`, per-user ping cap, `EncounterSession` |
| 4 | Intrusiveness / Wrong-Time Alerts | Medium | **Implemented** — geofence auto-pause, three sharing modes |
| 5 | Weekday / Low-Density Dead Zones | Medium | **Partial** — radius boost and calendar nudges pending |
| 6 | Coordinated Bad-Actor Groups | Critical | **Partial** — `SafetyVerifier` stub; group anomaly detection pending |
| 7 | Spring Break cross-school widening | High | **Implemented** — server-dated window + dual presence confirmation |

---

## 0. Ungated Pool / Cross-Campus Exposure

**Consequence if unaddressed**: the product's entire safety story rests on "these are your classmates". A pool anyone can enter, or one that quietly spans campuses, makes every other mitigation cosmetic — the caps, the reveal gating and the trust tiers all assume a bounded, accountable community.

**Mandated mitigations**
- Fizz-style school gate: phone + allowlisted `.edu` magic link, school Google/Microsoft OAuth, or reviewed enrollment proof (`schoolGate.ts`). `schoolId` and `enrollmentStatus` are issued server-side and written to Firebase Auth custom claims; the client never self-promotes.
- Student ID card photo + liveness before Quest Mode (`studentIdVerification.ts`). Stricter than Fizz on purpose: an `.edu` address gets you a feed, not a signal telling someone where to walk.
- `CommunityGate.canShare` on every nearby, match, icebreaker and proximity path (`Models/School.swift`).
- `firestore.rules` evaluates the same-school predicate **per document** on list queries, so an unconstrained nearby query fails outright rather than returning a filtered set.
- Campus geofence auto-pause: off campus, `CommunityScope` is `.none` and every path returns empty (`LocationService.reevaluateScope`).
- 48 unit tests cover the three gates, the same-school predicate and the fail-closed decoders.

**Known limit, stated rather than hidden**: security rules cannot read device location, so they cannot verify physical presence. They enforce membership, verification depth, the server-dated window and server-confirmed destination presence. Presence itself is enforced by `LocationService` and re-checked by `confirmDestinationPresence`.

## 1. Gender Imbalance / Male Overload — Dating only

**Consequence if unaddressed**: Women feel swarmed → mute/delete → men get silence → death spiral.

**Scope note.** All of the following applies **only to Dating-gated encounters**. Study, Hangout, Friendship and Event overlaps are never gender-throttled. Applying romantic-marketplace throttling to someone looking for a lab partner would be both useless and insulting, and it would push women out of the intents that are not imbalanced in the first place.

**Mandated mitigations**
- Asymmetric daily alert caps: women 10/day, non-binary 20/day, men 40/day (`AlertCapManager.swift`). `canSendAlert` requires the session's locked intents as an argument — there is no overload that skips it.
- `BalanceEnforcer` listens to **per-school** `global_gender_stats/{schoolId}`, counting Dating-gated users only. When that campus's male% > 55%, male Dating visibility is probabilistically throttled (floor: 10% pass rate). A national ratio would be meaningless — people meet on their own campus.
- Women-first queuing toggled server-side via `BalanceEnforcer.womenFirstQueuingEnabled`.
- The male waitlist queues someone **for Dating**, and only if they selected it. The other four intents keep working while queued.
- Squad Radar default after dusk inside a Spring Break destination.
- Aggressive early female user acquisition (see `docs/LAUNCH_STRATEGY.md`).

### The intent-toggle exploit

Scoping caps to Dating creates the obvious dodge: switch Dating off, shed the caps, keep the alerts. Four mitigations close it, and all four are needed:

1. `EncounterSession.lockedIntents` and `isDatingGated` are computed once from **both** users at session start and frozen. A mid-session intent change does not touch a session in flight.
2. `activeIntents` is server-owned — `firestore.rules` refuses a client write. Intents change only through `setActiveIntents` (`intents.ts`).
3. Switching Dating off sets a **24-hour server-written cooldown** (`datingCooldownUntil`). During it, `isDatingGated()` stays true and every Dating protection still applies. Re-enabling does not clear it, so an on/off/on cycle cannot shorten the window.
4. An alert counts as Dating only if **both** users were Dating-gated at session start.

`balanceMonitor` counts cooldown users in the ratio for the same reason: otherwise a wave of men switching Dating off would leave the denominator and make a skewed campus read as balanced.

---

## 2. Misrepresentation & Lying (height, photos, intent)

**Consequence if unaddressed**: Awkward/bad meets → low post-meet ratings → trust collapse → "everyone lies" perception.

**Mandated mitigations**
- Liveness check during onboarding: Vision framework, 2 random actions (turn left/right, blink, smile), ≥3 consecutive confirmation frames (`LivenessDetector.swift`)
- **The decision is server-side.** `studentIdVerification.ts` runs the face match against the student ID; the on-device Vision comparison is a pre-flight hint only and gates nothing. A client that could decide its own face match could decide to pass.
- Student ID images and liveness frames go to a write-only Storage prefix that no client can read back, and are deleted once the outcome is recorded. They never touch a profile document, so they cannot reach a nearby or match payload.
- Post-meet accuracy rating flows back into trust score (`RevealManager.swift`, `GamificationService.swift`)
- Trust tier system enforces graduated access: Bronze (school email) → Silver (student ID + liveness) → Gold (student ID ↔ selfie face match) → Platinum (avg rating ≥ 4.0)
- Tiered penalties: warning → visibility drop → suspension → ban (`SafetyVerifier.swift`)
- `TrustBadgeView` surfaces tier visibly in match cards

---

## 3. Swarm / Stratification around Attractive Users

**Consequence if unaddressed**: Top 10–20% capture most alerts → average users quit → jealousy/bad vibes.

**Mandated mitigations**
- Progressive photo reveal: no photos until AR icebreaker interaction begins (`RevealManager.swift`, `EncounterSession.swift`)
- `RevealStage` enum is fail-closed: default is `.blurred`; advancement requires mutual engagement
- Per-user ping cap: max 5 alerts/hour from any single partner (`MatchManager.swift`)
- 15-minute cooldown between alerts for the same match pair
- Random alert rotation when multiple qualifying matches are nearby

---

## 4. Intrusiveness / Wrong-Time Alerts

**Consequence if unaddressed**: Creepy tracking perception → immediate uninstalls.

**Mandated mitigations**
- Campus geofence: Quest Mode runs inside the verified campus boundary and **auto-pauses everywhere else** (`LocationService.reevaluateScope`). Off campus, the scope is `.none` and nothing scans.
- Configurable geofence auto-pause zones (home, work, custom) — Quest Mode never fires inside them, and a user zone wins even on campus (`LocationService.swift`)
- Three sharing modes: `precise` (opt-in), `anonymized` (default), `hidden` (`UserProfile.PrivacySettings`)
- One-tap Quest Mode toggle accessible from Home and as a widget/Siri shortcut
- Raw coordinates never stored — geohash precision 7 only (`Geohash.swift`)

---

## 5. Weekday / Low-Density Dead Zones

**Consequence if unaddressed**: Mon–Thu silence → users assume the app is broken.

**Mandated mitigations** *(partial)*
- Commute/lunch radius boost (pending)
- Weekday nudge notifications and XP badges (pending)
- Campus density is the whole strategy: a single campus is already a dense, bounded community, which is why the product is gated to one rather than opened to a city. Study intent in particular has natural weekday demand — a library at 9pm on a Tuesday is the opposite of a dead zone (see `docs/LAUNCH_STRATEGY.md`)

---

## 6. Coordinated Bad-Actor Groups (Harassment / Assault Risk)

**Consequence if unaddressed**: Organized groups using the app to locate and harass women on campus or at a Spring Break destination → safety incidents, App Store rejection, mass female churn.

The campus gate helps here more than anywhere else: a coordinated group has to be enrolled students with verified student IDs at a single named school, which is both a much smaller pool of potential bad actors and a much more accountable one. It is not a substitute for detection.

**Mandated mitigations** *(partial)*
- Server-side group/coordination anomaly detection: multiple male users pinging same woman in tight geohash/time window — architecture defined in `SafetyVerifier.swift`, Cloud Function pending
- Enhanced `SafetyVerifier` with stricter verification and behavioral flags
- Women-first queuing + temporary "safe mode" in high-density male clusters (`BalanceEnforcer.swift`)
- One-tap "Unsafe Proximity" report during/after icebreaker — immediate session termination + investigation
- Campus and Spring Break destination geofence rules; no nightlife or festival surfaces exist to need them
- No raw location history — only ephemeral geohash + session data
- Post-incident auto-flagging and tiered penalties (including propagation to correlated accounts)

> **Launch-Specific Gate**: every campus and every Spring Break destination requires these controls before any marketing push. City nightlife and festival surfaces are out of scope entirely (see `LAUNCH_STRATEGY.md`) — they would mean building a second, ungated pool.

---

## 7. Spring Break Cross-School Widening

**Consequence if unaddressed**: the one place the same-school rule relaxes is the one place it would be most valuable to attack. A window that stayed open, a fence that could be spoofed, or a claim that outlived the trip would turn a time-boxed exception into a permanent cross-campus pool.

**Mandated mitigations**
- The window and the fence live in `spring_break_destinations/{id}`, written by admins only. There is no client-supplied polygon and no client-supplied date.
- `SpringBreakDestination.isLive(at:)` is fail-closed: inactive, out of window, or a malformed (inverted) window all return false.
- Presence is confirmed **server-side**. The client sends a precision-7 geohash; `confirmDestinationPresence` decodes it, checks it against the destination's own centre and radius, re-checks the window, and only then issues the short-lived `sbDest` claim.
- Cross-school reads require four conditions simultaneously (`firestore.rules`): a live window, the viewer confirmed at that destination, the subject confirmed at the **same** destination, and the subject school-verified. Locals and unverified tourists satisfy none.
- The `sbDest` claim has a 45-minute TTL, and `clearDestinationPresence` drops both the claim and the profile flag on leaving. No cross-school radar survives the trip home.
- `isActive: false` on the destination document is a kill switch independent of the dates.
- After dusk: Squad Radar default, tighter radius, Dating caps and women-first queuing unchanged, one-tap Unsafe Proximity.

**Open**: the TTL is not currently re-confirmed on a timer, so a user standing at a destination for over 45 minutes silently drops back to same-school until the next region crossing. Tracked in the README's limitations table.

---

## Beta Monitoring Targets

| Metric | Target |
|--------|--------|
| Gender ping ratio per **Dating** session | ≥ 40% women in target zones within 30 days |
| Avg Dating alerts/user/hour (by gender) | Within asymmetric caps at all times |
| Share of sessions that are non-Dating | ≥ 50% — if this collapses, the "not a dating app" positioning is not landing |
| Cross-school sessions outside a live window | **Zero.** Any non-zero value is a rules failure, not a metric |
| Post-meet mismatch rate | < 15% |
| Unsafe report rate | < 0.5% |
| Suspicious cluster rate (coordinated pings) | Alert at > 0.1% of sessions |
| Weekday vs. weekend activation % | < 3× weekend/weekday ratio |
| % of sessions terminated via safety report | Monitor; no fixed target yet |
