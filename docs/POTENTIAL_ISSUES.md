# Critical Risks & Design Mandates

These are the highest-priority systemic risks for DateQuest AR. Ignoring them will likely cause network failure, high churn, or safety complaints.

## 1. Gender Imbalance / Male Overload
**Consequences if unaddressed**
Women feel swarmed → mute/delete → men get silence → death spiral.

**Mandated mitigations**
- Asymmetric alert caps (women lower than men)
- Women-first queuing in dense areas
- Squad radar default in social settings
- Intent/vibe filtering
- Aggressive early female user acquisition

## 2. Misrepresentation & Lying (height, photos, intent, etc.)
**Consequences if unaddressed**
Awkward/bad meets → low post-meet ratings → trust collapse → "everyone lies" perception.

**Mandated mitigations**
- Mandatory ID + live selfie at signup
- Instagram consistency check
- Post-meet accuracy rating → trust score impact
- Tiered penalties: warning → visibility drop → suspension → ban
- Visible trust badges

## 3. Swarm / Stratification around Attractive Users
**Consequences if unaddressed**
Top 10–20% capture most alerts → average users quit → jealousy/bad vibes.

**Mandated mitigations**
- Delayed/blurred photo reveal
- Per-user ping cap
- Random alert rotation
- Forced group merge on high attention
- Vibe-first matching default

## 4. Intrusiveness / Wrong-Time Alerts
**Consequences if unaddressed**
Creepy tracking perception → immediate uninstalls.

**Mandated mitigations**
- Geo-fence auto-pause (home/office/custom)
- Calendar-aware quiet periods
- One-tap toggle everywhere (widget/Siri)

## 5. Weekday / Low-Density Dead Zones
**Consequences if unaddressed**
Mon–Thu silence → users assume app is broken.

**Mandated mitigations**
- Commute/lunch radius boost
- Weekday nudges & badges
- Calendar + geo integration

## Beta Monitoring Targets
- Gender ping ratio per session
- Average alerts per user per hour (by gender)
- Post-meet mismatch rate
- Trust score distribution
- Weekday vs weekend activation %

## 6. Coordinated Bad-Actor Groups (Harassment / Assault Risk)
**Consequences if unaddressed**  
Organized groups of men using the app to locate and harass women in public/nightlife/festival settings → safety incidents, bad press, regulatory issues, App Store rejection, mass female churn.

**Mandated Mitigations**  
- Server-side group/coordination anomaly detection (multiple male users pinging same woman in tight geohash/time window).  
- Enhanced `SafetyVerifier` with stricter verification + behavioral flags.  
- Aggressive women-first queuing + temporary "safe mode" in high-density male clusters.  
- One-tap "Unsafe Proximity" reporting during/after icebreaker (immediate session termination + investigation).  
- Event-specific geo-fence rules for nightlife/festivals/campuses.  
- No raw location history; only ephemeral geohash + session data.  
- Post-incident auto-flagging and tiered penalties (including propagation to correlated accounts).

**Launch-Specific Note**  
All campus, nightlife, spring-break, and festival zones require these controls before any marketing push.

### Updated Beta Monitoring Targets (add)
- Suspicious cluster rate (coordinated pings).  
- Unsafe report rate by gender and location type.  
- % of sessions terminated via safety reports.
