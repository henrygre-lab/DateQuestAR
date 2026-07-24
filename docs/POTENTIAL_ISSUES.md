# Serendipity — Known Risks & Design Mandates

Every risk here has a mandated mitigation implemented (or explicitly tracked as in-progress) at the code level. This doc is the canonical source of truth for why specific safety decisions were made.

## Risk Summary

| # | Risk | Severity | Implementation Status |
|---|------|----------|-----------------------|
| 1 | Gender Imbalance / Male Overload | Critical | **Implemented** — `AlertCapManager`, `BalanceEnforcer` |
| 2 | Misrepresentation & Lying | High | **Implemented** — `LivenessDetector`, trust tiers, post-meet rating |
| 3 | Swarm / Stratification | High | **Implemented** — `RevealManager`, per-user ping cap, `EncounterSession` |
| 4 | Intrusiveness / Wrong-Time Alerts | Medium | **Implemented** — geofence auto-pause, three sharing modes |
| 5 | Weekday / Low-Density Dead Zones | Medium | **Partial** — radius boost and calendar nudges pending |
| 6 | Coordinated Bad-Actor Groups | Critical | **Partial** — `SafetyVerifier` stub; group anomaly detection pending |

---

## 1. Gender Imbalance / Male Overload

**Consequence if unaddressed**: Women feel swarmed → mute/delete → men get silence → death spiral.

**Mandated mitigations**
- Asymmetric daily alert caps: women 10/day, non-binary 20/day, men 40/day (`AlertCapManager.swift`)
- `BalanceEnforcer` listens to real-time `global_gender_stats/current` (Cloud Function-managed). When male% > 55%, male match visibility is probabilistically throttled (floor: 10% pass rate)
- Women-first queuing toggled server-side via `BalanceEnforcer.womenFirstQueuingEnabled`
- Squad radar default in social/festival geohashes
- Aggressive early female user acquisition (see `docs/LAUNCH_STRATEGY.md`)

---

## 2. Misrepresentation & Lying (height, photos, intent)

**Consequence if unaddressed**: Awkward/bad meets → low post-meet ratings → trust collapse → "everyone lies" perception.

**Mandated mitigations**
- Liveness check during onboarding: Vision framework, 2 random actions (turn left/right, blink, smile), ≥3 consecutive confirmation frames (`LivenessDetector.swift`)
- Post-meet accuracy rating flows back into trust score (`RevealManager.swift`, `GamificationService.swift`)
- Trust tier system enforces graduated access: Bronze (email) → Silver (liveness) → Gold (ID face match) → Platinum (avg rating ≥ 4.0)
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
- Configurable geofence auto-pause zones (home, work, custom) — Quest Mode never fires inside them (`LocationService.swift`)
- Three sharing modes: `precise` (opt-in), `anonymized` (default), `hidden` (`UserProfile.PrivacySettings`)
- One-tap Quest Mode toggle accessible from Home and as a widget/Siri shortcut
- Raw coordinates never stored — geohash precision 7 only (`Geohash.swift`)

---

## 5. Weekday / Low-Density Dead Zones

**Consequence if unaddressed**: Mon–Thu silence → users assume the app is broken.

**Mandated mitigations** *(partial)*
- Commute/lunch radius boost (pending)
- Weekday nudge notifications and XP badges (pending)
- Campus → nightlife → festival launch sequencing maximizes density before open metro rollout (see `docs/LAUNCH_STRATEGY.md`)

---

## 6. Coordinated Bad-Actor Groups (Harassment / Assault Risk)

**Consequence if unaddressed**: Organized groups using the app to locate and harass women in nightlife/festival/campus settings → safety incidents, App Store rejection, mass female churn.

**Mandated mitigations** *(partial)*
- Server-side group/coordination anomaly detection: multiple male users pinging same woman in tight geohash/time window — architecture defined in `SafetyVerifier.swift`, Cloud Function pending
- Enhanced `SafetyVerifier` with stricter verification and behavioral flags
- Women-first queuing + temporary "safe mode" in high-density male clusters (`BalanceEnforcer.swift`)
- One-tap "Unsafe Proximity" report during/after icebreaker — immediate session termination + investigation
- Event-specific geofence rules for nightlife, festivals, and campuses
- No raw location history — only ephemeral geohash + session data
- Post-incident auto-flagging and tiered penalties (including propagation to correlated accounts)

> **Launch-Specific Gate**: All campus, nightlife, spring-break, and festival zones require these controls before any marketing push.

---

## Beta Monitoring Targets

| Metric | Target |
|--------|--------|
| Gender ping ratio per session | ≥ 40% women in target zones within 30 days |
| Avg alerts/user/hour (by gender) | Within asymmetric caps at all times |
| Post-meet mismatch rate | < 15% |
| Unsafe report rate | < 0.5% |
| Suspicious cluster rate (coordinated pings) | Alert at > 0.1% of sessions |
| Weekday vs. weekend activation % | < 3× weekend/weekday ratio |
| % of sessions terminated via safety report | Monitor; no fixed target yet |
