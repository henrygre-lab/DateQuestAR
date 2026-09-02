# Serendipity Edge Cases & Objections Handbook

This document captures all stress-tested edge cases and common objections from product discussions. It serves as a living reference for engineering, marketing, pitching, and safety hardening. Every item ties back to `POTENTIAL_ISSUES.md` risks and must be mitigated before launch.

## 1. Technical & Location Accuracy Edge Cases

| Edge Case | Objection / Criticism | Why It Matters | Proposed Mitigation |
|-----------|-----------------------|----------------|---------------------|
| Multi-storey campus buildings (library stacks, residence towers, lecture halls) | "I got pinged by someone four floors above me in the stacks" | Risk #3 (swarm) + Risk #5 (dead zones) | 3D proximity in active `EncounterSession` using `CLLocation.altitude` + `CMAltimeter`. Auto-shrink radius in high-density geohashes. **Still unimplemented** — neither framework is referenced in the codebase. |
| Moving vehicles / trains / opposite directions / same bus/train | "Why am I getting alerts from people driving by?" or "Session died because the bus moved" | Risk #4 (intrusiveness) + session persistence | `CMMotionActivityManager` strict `.walking`/`.running` filter for new sessions. Persist `EncounterSession` 10–15 min + speed similarity check once active. |
| Indoor / basement lab / poor GPS | "App doesn't work where I actually meet people" | Risk #5 | Fallback to last-known geohash + Wi-Fi hints. Degrade to non-AR icebreakers. |
| Campus geofence edge | "I'm in the library at the edge of campus and it keeps pausing" | Retention + trust in the gate | Geofence comes from `schools/{schoolId}.campus` and is reviewed on a map before a school opens. Sizing it is a launch gate, not a runtime fix — an oversized fence quietly imports the surrounding neighbourhood. |
| Studying off campus (a coffee shop two blocks away) | "Half my study sessions happen off campus and the app is dead there" | The central trade-off of a campus product | **Accepted, not mitigated.** Off campus is `.none` and Quest Mode pauses. Widening the fence to cover nearby cafés would import non-students into the pool, which is the one thing the architecture exists to prevent. The Home screen states the pause plainly rather than showing an empty list. |
| Battery drain from Quest Mode | "This app kills my battery — deleted after one day" | Retention killer | Significant-change + visit monitoring. Visible Low Power Mode toggle + auto-pause. |
| Older iPhone / ARKit incompatibility | "Works only on latest phones — excludes users" | Adoption barrier | Graceful degradation: non-AR icebreakers for older devices. |

## 2. Privacy, Safety & Trust Edge Cases (Critical)

| Edge Case | Objection / Criticism | Why It Matters | Proposed Mitigation |
|-----------|-----------------------|----------------|---------------------|
| Stalking / persistent tracking | "It knows exactly where I am — creepy" | Risk #4 + Risk #2 | Mandatory geo-fence auto-pause, calendar quiet periods, one-tap Ghost Mode. Ephemeral geohash only. |
| Coordinated male groups with mal-intent | "Groups of men using the app to harass women" | New high-severity risk (added to POTENTIAL_ISSUES) | Server-side group anomaly detection, enhanced `SafetyVerifier`, women-first queuing + safe mode, one-tap "Unsafe Proximity" report, tiered penalties. |
| Student ID verification friction | "Too invasive just to see who's around" | Onboarding drop-off — this is the real activation step | Tiered: the school gate gets you the community; the student ID gets you Quest Mode; the ID ↔ selfie face match gets you Dating and NameDrop. Each step buys something visible. The ID image is uploaded where nobody can read it back — including the uploader — and is deleted once checked; the UI says so at the point of upload. |
| Cross-school exposure at Spring Break | "I signed up for my campus and now strangers from other schools can see me" | The one place the same-school rule relaxes | Server-dated window, dual server-confirmed presence, verified students only, 45-minute claim TTL, and a kill switch on the destination document. Leaving the fence or the window drops the claim and the profile flag together. |
| Incoming students and age | "A 17-year-old admit is in an adult dating pool" | Safety + App Store | Dating requires `verifiedAge >= 18` read off the student ID by the server, on top of the face match. `enrollmentStatus == .incoming` is explicitly *not* evidence of adulthood. The other four intents remain open. |
| Post-meet harassment | "We met, it was bad, now they have my profile" | Risk #2 | NameDrop is opt-in only. Immediate block/report triggers trust score penalties and visibility drop. |

## 3. Social / Adoption / Market Edge Cases

- **"Sausage party" persists**: Aggressive female-first acquisition + per-campus gender-ratio dashboards. Note the ratio that matters is the *Dating* ratio on that campus — a school can be male-skewed overall and balanced on Dating, or the reverse.
- **Social stigma of AR in public**: Haptic-first alerts + discreet AR mode.
- **A small or quiet campus**: dynamic radius; Study intent has natural weekday demand that Dating does not.
- **Multiple simultaneous matches**: Per-user ping caps + forced Squad Radar in dense areas.
- **"Dating is buried, so nobody will find it"**: intentional. Burying it is the positioning, and the five-intent picker in Settings makes it one tap for anyone who wants it.

## Objection-Handling Copy (for Pitching / Marketing / Support)
- **"So it's a dating app"**: "No. There are five intents — Hangout, Study, Friendship, Event and Dating — and the app opens on Hangout and Study. Dating is optional, off unless you turn it on, and needs an extra verification step. Most sessions are people finding someone to study or grab coffee with."
- **"This sounds creepy / stalky"**: "It only works inside your own campus, only shows people from your own school, and pauses the moment you leave. We never store raw location — only an ephemeral geohash — and no screen ever names a place."
- **"Anyone could say they go to my school"**: "The school email gets you in. Seeing who's nearby needs a photo of your student ID and a liveness check, and swapping contact details needs your ID to match your selfie. All three decisions are made on our servers, not on the phone."
- **"What about bad actors or groups?"**: "Everyone in your pool is an enrolled student at your school with a verified student ID — a much smaller and more accountable set than an open app. On top of that we run server-side anomaly detection for coordinated behaviour, and any unsafe report immediately terminates the session."
- **"Why can women get fewer alerts than men?"**: "Those caps only apply to Dating. Study, Hangout, Friendship and Events aren't gender-throttled at all. And turning Dating off doesn't shed the caps for 24 hours, precisely so they can't be gamed."
- **"Won't it miss people on the same bus/train?"**: "The strict walking filter is a *proposed* mitigation and is not built yet — vehicle noise is currently unmitigated. Active sessions do persist for 10–15 minutes, so a connection survives a brief drift apart."

All mitigations will be implemented with full enforcement of `SECURITY_CHECKLIST.md`.
