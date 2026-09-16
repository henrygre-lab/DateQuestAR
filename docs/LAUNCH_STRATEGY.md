# Serendipity Launch Strategy (Phase 1 — Campus-Only, Female-First)

**Goal**: prove the campus loop on a small number of schools before adding any more. The product is campus-gated by construction — there is no non-campus mode to launch into — so "expansion" here means *more schools*, not more surfaces.

## What is in scope

1. **College Campuses** (Q3–Q4 2026 pilot)
   Top 20–30 U.S. universities (UCLA, USC, NYU, UT Austin, University of Florida, etc.), added one `schools/{schoolId}` document at a time.
   Tactics: female student ambassadors, sorority partnerships, on-campus AR demo pop-ups, Study-first positioning during midterms.

   Note the framing: **this is not a dating launch.** Home defaults to Hangout and Study, and those are the intents the marketing leads with. Dating is available, optional, and behind an extra verification step.

2. **Spring Break destinations** (March 2027)
   Ft. Lauderdale / Miami Beach, South Beach, Cancún, Cabo — as server-dated `spring_break_destinations` documents, not as a permanent mode. Inside a live window, verified students from any allowlisted school can see each other at that destination. Locals and unverified tourists cannot appear.

   When the window closes or a user leaves the fence, the app returns to same-school and the cross-school claim is dropped. There is no residual cross-campus radar.

## What is deliberately out of scope

- **City nightlife.** No metro-wide nightlife surface, no bar geohashes, no sponsor quests in bars. A city is not a community, and the same-school rule is the product.
- **Festivals.** Coachella, Lollapalooza and EDC are not campus communities and do not get a national surface.
- **Open metro rollout.** There is no plan for one. Growth is more schools, not fewer gates.

Both were in earlier drafts of this document. They are removed rather than deferred: shipping them would mean building a second, ungated pool, which is the thing the architecture exists to prevent.

## Success Metrics (Tied to Beta Monitoring)

- School gate completion rate ≥ 60% of phone-verified starts.
- Student ID verification completion ≥ 70% of gate completions (this is the real activation step — Quest Mode is dark until it passes).
- Share of active users on Study or Hangout only ≥ 50%. If this collapses toward Dating, the positioning is not landing.
- Gender ping ratio per session ≥ 40% women **among Dating-gated sessions** in target zones within first 30 days.
- Average Dating alerts per user per hour stays within asymmetric caps.
- Post-meet mismatch rate < 15%.
- Unsafe report rate < 0.5%.
- Off-campus auto-pause rate — sanity check that the geofence is sized correctly and not stranding students in libraries at the campus edge.

## Non-Negotiable Risk Controls (Before Any Marketing Push)

- `firestore.rules` deployed and verified against the emulator for the school it is about to open. A campus opened without rules is an ungated pool.
- Campus geofence for that `schoolId` reviewed on a map by a human. An oversized fence quietly imports the surrounding neighbourhood.
- Enhanced `SafetyVerifier` (group anomaly detection, stricter verification).
- Women-first queuing + temporary "safe mode" during high-density male clusters — Dating only.
- One-tap "Unsafe Proximity" reporting.
- 50%+ of early marketing budget on female acquisition.
- Aggressive monitoring of suspicious cluster rate and safety reports.

For Spring Break specifically, additionally:

- The destination fence and its dates reviewed before the window opens; both live in a backend document and neither is client-editable.
- After dusk inside a fence: Squad Radar default, tighter radius, Dating caps and women-first queuing still on.
- A tested kill switch — `isActive: false` on the destination document closes the cross-school pool immediately, independent of the dates.

See `POTENTIAL_ISSUES.md` for full risk mitigations.
