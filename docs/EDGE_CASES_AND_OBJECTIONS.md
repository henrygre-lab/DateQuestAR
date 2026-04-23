# Serendipity Edge Cases & Objections Handbook

This document captures all stress-tested edge cases and common objections from product discussions. It serves as a living reference for engineering, marketing, pitching, and safety hardening. Every item ties back to `POTENTIAL_ISSUES.md` risks and must be mitigated before launch.

## 1. Technical & Location Accuracy Edge Cases

| Edge Case | Objection / Criticism | Why It Matters | Proposed Mitigation |
|-----------|-----------------------|----------------|---------------------|
| Skyscrapers / vertical density (e.g., NYC Central Park Tower vs. Nordstrom downstairs) | "I got pinged by someone 40 floors above me — useless!" | Risk #3 (swarm) + Risk #5 (dead zones) | 3D proximity in active `EncounterSession` using `CLLocation.altitude` + `CMAltimeter`. Auto-shrink radius in high-density geohashes. |
| Moving vehicles / trains / opposite directions / same bus/train | "Why am I getting alerts from people driving by?" or "Session died because the bus moved" | Risk #4 (intrusiveness) + session persistence | `CMMotionActivityManager` strict `.walking`/`.running` filter for new sessions. Persist `EncounterSession` 10–15 min + speed similarity check once active. |
| Indoor / subway / tunnel / poor GPS | "App doesn't work where I actually meet people" | Risk #5 | Fallback to last-known geohash + Wi-Fi hints. Degrade to non-AR icebreakers. |
| Battery drain from Quest Mode | "This app kills my battery — deleted after one day" | Retention killer | Significant-change + visit monitoring. Visible Low Power Mode toggle + auto-pause. |
| Older iPhone / ARKit incompatibility | "Works only on latest phones — excludes users" | Adoption barrier | Graceful degradation: non-AR icebreakers for older devices. |

## 2. Privacy, Safety & Trust Edge Cases (Critical)

| Edge Case | Objection / Criticism | Why It Matters | Proposed Mitigation |
|-----------|-----------------------|----------------|---------------------|
| Stalking / persistent tracking | "It knows exactly where I am — creepy" | Risk #4 + Risk #2 | Mandatory geo-fence auto-pause, calendar quiet periods, one-tap Ghost Mode. Ephemeral geohash only. |
| Coordinated male groups with mal-intent | "Groups of men using the app to harass women" | New high-severity risk (added to POTENTIAL_ISSUES) | Server-side group anomaly detection, enhanced `SafetyVerifier`, women-first queuing + safe mode, one-tap "Unsafe Proximity" report, tiered penalties. |
| Mandatory ID verification friction | "Too invasive for a dating app" | Onboarding drop-off | Tiered verification: basic = blurred reveal; full reveal requires verified badge. |
| Post-meet harassment | "We met, it was bad, now they have my profile" | Risk #2 | NameDrop is opt-in only. Immediate block/report triggers trust score penalties and visibility drop. |

## 3. Social / Adoption / Market Edge Cases

- **"Sausage party" persists**: Aggressive female-first acquisition + public gender-ratio dashboards.
- **Social stigma of AR in public**: Haptic-first alerts + discreet AR mode.
- **Low-density cities**: Micro-Quest boosts + dynamic radius based on local density.
- **Multiple simultaneous matches**: Per-user ping caps + forced Squad Radar in dense areas.

## Objection-Handling Copy (for Pitching / Marketing / Support)
- **"This sounds creepy / stalky"**: "Quest Mode is opt-in with mandatory geo-fence auto-pause and one-tap toggles everywhere. We never store raw location history — only ephemeral geohash during active sessions."
- **"What about bad actors or groups?"**: "We require ID + live selfie verification and run server-side anomaly detection for coordinated behavior. Any unsafe report immediately terminates the session and triggers investigation. Safety is non-negotiable."
- **"Won't it miss people on the same bus/train?"**: "Strict walking filter prevents vehicle noise, but active sessions persist with motion context so promising connections stay alive."

All mitigations will be implemented with full enforcement of `SECURITY_CHECKLIST.md`.
