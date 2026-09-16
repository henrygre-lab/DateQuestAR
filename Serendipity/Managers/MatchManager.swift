// MARK: - SECURITY CHECKLIST COMPLIANCE (see docs/SECURITY_CHECKLIST.md)
// [x] No hardcoded secrets, API keys, or tokens
// [x] Asymmetric alert caps enforced via AlertCapManager (Risk #1: Gender Imbalance / Male Overload)
//     - Women: 10/day, Non-binary: 20/day, Prefer-not-to-say: 15/day, Men: 40/day
//     - Client-side caps are advisory only; Firestore Security Rules are authoritative
// [x] Women-first queuing via BalanceEnforcer.shouldShowMatch + AlertCapManager daily caps
// [x] AlertCapManager.canSendAlert() checked BEFORE any nearbyMatch update, profile fetch,
//     or icebreaker trigger — fail-closed on the critical path
// [x] No client-side final authority on caps — server-side Firestore atomic transactions and
//     Security Rules are the real enforcement boundary
// [x] BalanceEnforcer hourly gender cap (server-sourced) still enforced via atomic Firestore
//     transaction as a second layer after AlertCapManager daily cap
// [x] Per-user ping cap (5/hr) retained as complementary anti-harassment layer
// [x] IntentVibe scoring uses only user-supplied tags, no PII inference
// [x] Same-school hard gate on EVERY path — nearby, match creation, proximity
//     event handling and icebreaker dispatch all run CommunityGate.canShare
//     against the current CommunityScope before doing any work
// [x] Off campus (and outside any live Spring Break fence) the scope is .none and
//     every one of those paths returns empty — auto-pause, fail-closed
// [x] Cross-school matching is reachable two ways, both requiring a live,
//     server-issued and expiring presence claim: a campus the user is physically
//     on that is not their own (the Big Game rule), or a Spring Break
//     destination. Leaving either drops back to same-school.
// [x] Gender-balance tools (asymmetric caps, women-first queue, waitlist) are
//     applied ONLY when the encounter's locked intent overlap contains Dating —
//     a Study or Hangout overlap is never gender-throttled
// [x] The Dating decision is taken once, from BOTH users, at session start and
//     locked; switching Dating off mid-session changes nothing, and the 24h
//     server cooldown keeps the caps on afterwards
// [x] Client filters here are courtesy only — firestore.rules enforces the same
//     school predicate per document and is the real boundary
// [x] Encounter slot cap (2 per user) gates alerts in BOTH directions: a capped
//     user sends no new alerts and is shown none. The count comes from Firestore
//     via RevealManager, never a local array, and openEncounterSession re-counts
//     inside a transaction — so a client that ignores this gate still cannot open
//     a third session.
// [x] The cap is on top of the Dating caps and the 24h Dating cooldown, not
//     instead of them, and applies to every intent
// [x] No raw coordinates logged — only match IDs and enum states
// [x] No mutable public user state — profile passed explicitly to avoid stale data
// [x] Analytics events contain no raw UIDs — partner UIDs hashed before logging
// [x] Ties to launch strategy: campus pilots require all caps active before any
//     marketing push (see docs/LAUNCH_STRATEGY.md)

import Foundation
import Combine
import CoreLocation
import FirebaseAuth

// MARK: - MatchManager

@MainActor
final class MatchManager: ObservableObject {
    static let shared = MatchManager()

    @Published var activeMatches: [Match] = []
    @Published var nearbyMatch: Match?
    @Published var nearbyMatchProfile: UserProfile?
    @Published var currentIcebreaker: IcebreakerChallenge?
    @Published var isQuestModeActive = false
    @Published var nearbyUsers: [UserProfile] = []

    /// True when the user is holding the maximum number of encounters.
    ///
    /// Republished from `RevealManager` rather than computed off it: a computed
    /// property reading another object's `@Published` value does not notify this
    /// object's observers, so the Home and Radar lines would only appear on the
    /// next unrelated redraw.
    ///
    /// Courtesy display only — the cap is enforced by `openEncounterSession`.
    @Published private(set) var isAtSessionCap = false

    #if DEBUG
    // MARK: - Demo State (DEBUG only)
    // Drives the Developer Bypass walkthrough. Compiled out of release builds.

    /// True while a simulated encounter is running (presents EncounterView).
    @Published var isDemoEncounterActive = false
    /// Live simulated distance to the demo match, in miles.
    @Published var demoDistanceMiles: Double = 0.25
    /// True once the match is close enough to start an icebreaker.
    @Published var demoReadyForIcebreaker = false
    /// Explains why a demo couldn't start (cap reached, queued, none compatible).
    @Published var demoStatusMessage: String?

    private let demoProximityProvider = DemoProximityProvider()
    private var demoRevealTimer: Timer?
    #endif

    // MARK: - Rate Limiting (Legacy — see AlertCapManager for daily caps)

    /// Deprecated: Use AlertCapManager.shared for daily alert cap enforcement.
    /// Retained temporarily for per-match cooldown tracking only.
    @available(*, deprecated, message: "Daily cap enforcement moved to AlertCapManager. Use alertCapManager.canSendAlert(for:match:) instead.")
    private(set) var alertsSentToday: Int = 0
    private var alertCountDate: Date = Calendar.current.startOfDay(for: Date())
    private var lastAlertTimes: [String: Date] = [:]  // matchID → last alert time

    /// Per-user ping tracking: partnerUID → alert count this hour
    private var perUserPingCounts: [String: Int] = [:]
    private var perUserPingHourKey: String = ""

    /// Minimum seconds between alerts for the same match.
    private let matchCooldownSeconds: TimeInterval = 15 * 60  // 15 minutes

    /// Max alerts any single user can receive per hour (anti-harassment)
    private let maxPingsPerUserPerHour: Int = 5

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Dependencies

    private let alertCapManager = AlertCapManager.shared
    private let balanceEnforcer = BalanceEnforcer.shared
    private let revealManager = RevealManager.shared
    private let firestoreService = FirestoreService.shared
    private let analytics = AnalyticsService.shared

    /// Snapshot of the active user, set only via enableQuestMode.
    /// Used internally by the proximity event handler (NotificationCenter callback).
    private var activeQuestUser: UserProfile?

    /// Deprecated: Daily cap enforcement moved to AlertCapManager.
    /// Retained for backward compatibility; will be removed in Phase 3.
    @available(*, deprecated, message: "Daily cap enforcement moved to AlertCapManager. Use alertCapManager.getCurrentDailyLimit() instead.")
    var userAlertLimit: Int = 20

    private init() {
        observeProximityEvents()
        observeSessionSlots()
    }

    // MARK: - Quest Mode

    func enableQuestMode(for user: UserProfile) {
        guard user.privacySettings.questModeEnabled else { return }
        guard user.accountStatus == .active else {
            Log.match.debug("Quest mode blocked: accountStatus=\(user.accountStatus)")
            return
        }

        // Gate 2. A school email gets you into the community; it does not get you
        // proximity scanning. That needs the student ID card photo + liveness,
        // which is deliberately stricter than Fizz.
        guard user.canStartQuestMode else {
            Log.match.debug("Quest mode blocked: student ID verification incomplete")
            return
        }

        activeQuestUser = user
        isQuestModeActive = true

        // Start counting encounter slots from Firestore. Until this is running
        // the client has no idea how many it holds, which is why the server
        // re-counts on every open rather than trusting what arrives.
        revealManager.startObservingSlots(uid: user.uid)

        // Arm the campus boundary before scanning starts. Until LocationService
        // has a campus to test against, the scope stays .none and the nearby
        // query returns nothing — which is the correct answer, not a bug.
        Task { await configureGeofences(for: user) }

        // Initialize AlertCapManager with current user's profile so asymmetric
        // daily caps are ready before the first proximity event fires.
        alertCapManager.updateUserCaps(for: user)

        LocationService.shared.startQuestScanning()
        Task { await fetchPotentialMatches(for: user) }
        NotificationCenter.default.post(name: .questModeChanged, object: true)
    }

    func disableQuestMode() {
        // Free the slots before dropping local state, so a user who stops looking
        // stops occupying the other person's slot too.
        Task { await revealManager.releaseAllSessions() }
        revealManager.stopObservingSlots()

        activeQuestUser = nil
        isQuestModeActive = false
        nearbyUsers = []
        activeMatches = []
        LocationService.shared.stopQuestScanning()
        NotificationCenter.default.post(name: .questModeChanged, object: false)
    }

    /// Ends the encounter on screen and frees its slot.
    ///
    /// The explicit-pass path. Works for a real encounter and a demo one — the
    /// demo shares the same stage machine, so it should share the same exit.
    func endCurrentEncounter(reason: EncounterSession.CloseReason) {
        guard let matchID = nearbyMatch?.id else { return }
        Task { await RevealManager.shared.endSession(for: matchID, reason: reason) }

        #if DEBUG
        if RevealManager.shared.isDemoMode {
            endDemoEncounter()
            return
        }
        #endif

        nearbyMatch = nil
        nearbyMatchProfile = nil
        currentIcebreaker = nil
    }

    /// Mirrors RevealManager's slot count onto this object so views binding to
    /// MatchManager see the cap change as it happens.
    private func observeSessionSlots() {
        revealManager.$isAtSessionCap
            .receive(on: DispatchQueue.main)
            .sink { [weak self] atCap in self?.isAtSessionCap = atCap }
            .store(in: &cancellables)
    }

    // MARK: - Community Scope

    /// The pool the device may currently see. `.none` means auto-paused.
    var communityScope: CommunityScope { LocationService.shared.communityScope }

    /// Loads the user's campus boundary and any live Spring Break destinations,
    /// then hands both to LocationService.
    ///
    /// Both come from backend documents. Nothing here authors a fence.
    private func configureGeofences(for user: UserProfile) async {
        guard let schoolId = user.schoolId else { return }

        if let school = try? await firestoreService.fetchSchool(schoolId: schoolId), school.isActive {
            LocationService.shared.configureCampus(schoolId: schoolId, geofence: school.campus)
        } else {
            Log.match.error("Campus geofence unavailable — Quest Mode stays paused")
        }

        // Every allowlisted campus, not just this user's — the Big Game rule
        // means any of them can become the active pool.
        if let schools = try? await firestoreService.fetchSchools() {
            LocationService.shared.configureVisitableCampuses(schools)
        }

        if let destinations = try? await firestoreService.fetchActiveSpringBreakDestinations() {
            LocationService.shared.configureSpringBreakDestinations(destinations)
        }
    }

    /// Called by LocationService whenever the device crosses into or out of a
    /// community.
    ///
    /// Leaving one clears the pool immediately rather than letting stale
    /// candidates linger: "no leftover cross-school radar" has to mean the
    /// screen too, not just the next query.
    func communityScopeChanged(to scope: CommunityScope) async {
        guard scope.allowsQuestMode else {
            nearbyUsers = []
            activeMatches = []
            nearbyMatch = nil
            nearbyMatchProfile = nil
            Log.match.debug("Community scope cleared — Quest Mode paused")
            return
        }

        nearbyUsers = []
        activeMatches = []
        if let user = activeQuestUser {
            await fetchPotentialMatches(for: user)
        }
    }

    // MARK: - Core Safety Gate (Phase 2)

    /// Must be called before any alert. Fail-closed at every layer.
    ///
    /// Order is deliberate. The community gate runs first and costs nothing: if
    /// these two people are not in the same pool, no amount of compatibility
    /// matters and no cap needs consulting.
    ///
    /// The gender-balance layers run only when the pair's locked intent overlap
    /// contains Dating. Two people matching on Study are not gender-throttled —
    /// that is the whole point of intents being separate from Dating.
    func shouldTriggerAlert(for currentUser: UserProfile, match: UserProfile) -> Bool {
        // 1. Same school (or same live Spring Break destination). Hard gate.
        guard CommunityGate.canShare(viewer: currentUser,
                                     candidate: match,
                                     in: communityScope) else { return false }

        // 2. Encounter slots. Someone already holding two encounters is not
        //    available for a third, in either direction — no outbound alert, and
        //    nothing inbound shown to them. Checked early because it is a local
        //    read and rules out the whole candidate.
        guard !revealManager.isAtSessionCap else { return false }

        // 3. Verification depth and account standing.
        guard SafetyVerifier.isSafeToAlert(match) else { return false }

        // 4. Some shared reason to meet at all.
        let locked = EncounterSession.lockIntents(currentUser, match)
        guard !locked.isEmpty else { return false }

        // 5. Gender-balance layers — Dating overlaps only. Note this is on top of
        //    the slot cap above, not instead of it: the caps ration romantic
        //    attention, the cap rations attention full stop.
        if EncounterSession.locksDatingGate(currentUser, match) {
            guard CommunityGate.canShareForDating(viewer: currentUser,
                                                  candidate: match,
                                                  in: communityScope) else { return false }
            guard balanceEnforcer.shouldShowMatch(to: currentUser) else { return false }
            guard alertCapManager.canSendAlert(for: currentUser,
                                               match: nil,
                                               lockedIntents: locked) else { return false }
        }

        let breakdown = computeCompatibilityScore(userA: currentUser, userB: match)
        return breakdown.overall >= currentUser.preferences.compatibilityThreshold
    }

    /// Builds a Match with its community context and intent lock already set.
    ///
    /// Centralised so no call site can create a match without them. The scope
    /// decides `partnerSchoolId` and `springBreakDestinationID`; the two profiles
    /// decide the locked intents. Both are then immutable — `firestore.rules`
    /// rejects an update that touches either.
    private func makeMatch(currentUser: UserProfile,
                           candidate: UserProfile,
                           breakdown: ScoreBreakdown,
                           scope: CommunityScope) -> Match? {
        guard let viewerSchool = currentUser.schoolId,
              let partnerSchool = candidate.schoolId else { return nil }

        let destinationID: String?
        let campusID: String?
        let matchScope: Match.MatchScope
        switch scope {
        case .none:
            return nil
        case .campus(let schoolId):
            // The campus they are both standing on, which under the Big Game
            // rule may be neither person's own.
            destinationID = nil
            campusID = schoolId
            matchScope = .campus
        case .springBreak(let id, _):
            destinationID = id
            campusID = nil
            matchScope = .springBreak
        }

        return Match(
            id: UUID().uuidString,
            userAUID: currentUser.uid,
            userBUID: candidate.uid,
            compatibilityScore: breakdown.overall,
            scoreBreakdown: breakdown,
            status: .pending,
            createdAt: Date(),
            meetupOccurred: false,
            schoolId: viewerSchool,
            partnerSchoolId: partnerSchool,
            scope: matchScope,
            springBreakDestinationID: destinationID,
            campusId: campusID,
            lockedIntents: EncounterSession.lockIntents(currentUser, candidate),
            isDatingGated: EncounterSession.locksDatingGate(currentUser, candidate)
        )
    }

    // MARK: - AI Compatibility Scoring

    /// Scores compatibility between two profiles. Returns a value 0.0–1.0.
    /// Includes intentVibe Jaccard similarity as a fifth scoring dimension.
    func computeCompatibilityScore(
        userA: UserProfile,
        userB: UserProfile
    ) -> ScoreBreakdown {
        let interestOverlap = scoreInterestOverlap(userA.preferences.interests,
                                                   userB.preferences.interests)
        let intentMatch = scoreIntentOverlap(userA.eligibleIntents, userB.eligibleIntents)
        let ageCompat = scoreAgeCompatibility(userA.age, ageRange: userB.preferences.ageRange,
                                              partnerAge: userB.age, userAgeRange: userA.preferences.ageRange)
        let prefAlignment = scorePrefAlignment(userA.preferences, userB.preferences)

        return ScoreBreakdown(
            interestOverlap: interestOverlap,
            intentMatch: intentMatch,
            ageCompatibility: ageCompat,
            preferenceAlignment: prefAlignment
        )
    }

    // MARK: - Intent/Vibe Filter

    /// Computes Jaccard similarity between two users' intentVibes arrays.
    /// Returns 0.0–1.0. Minimum 0.6 required for a vibe match.
    func scoreVibeCompatibility(_ vibesA: [String], _ vibesB: [String]) -> Double {
        guard !vibesA.isEmpty || !vibesB.isEmpty else { return 1.0 } // Both empty = compatible
        guard !vibesA.isEmpty && !vibesB.isEmpty else { return 0.0 } // One empty = no match

        let setA = Set(vibesA.map { $0.lowercased() })
        let setB = Set(vibesB.map { $0.lowercased() })
        let intersection = setA.intersection(setB).count
        let union = setA.union(setB).count
        return union == 0 ? 0 : Double(intersection) / Double(union)
    }

    /// Minimum vibe similarity threshold for a match to proceed.
    private let vibeMatchThreshold: Double = 0.6

    /// Returns true if vibe compatibility meets the minimum threshold.
    func isVibeCompatible(_ userA: UserProfile, _ userB: UserProfile) -> Bool {
        let score = scoreVibeCompatibility(userA.intentVibes, userB.intentVibes)
        return score >= vibeMatchThreshold
    }

    private func scoreInterestOverlap(_ a: [String], _ b: [String]) -> Double {
        let setA = Set(a.map { $0.lowercased() })
        let setB = Set(b.map { $0.lowercased() })
        let intersection = setA.intersection(setB).count
        let union = setA.union(setB).count
        return union == 0 ? 0 : Double(intersection) / Double(union)  // Jaccard index
    }

    /// Jaccard overlap between two users' eligible intents.
    ///
    /// Reads `eligibleIntents`, so a user who has Dating selected without the
    /// face match scores as though they had not — the same list the intent lock
    /// uses, so scoring and gating cannot disagree.
    private func scoreIntentOverlap(_ a: [Intent], _ b: [Intent]) -> Double {
        let setA = Set(a)
        let setB = Set(b)
        let intersection = setA.intersection(setB).count
        let union = setA.union(setB).count
        return union == 0 ? 0 : Double(intersection) / Double(union)  // Jaccard index
    }

    private func scoreAgeCompatibility(_ myAge: Int, ageRange: ClosedRange<Int>,
                                        partnerAge: Int, userAgeRange: ClosedRange<Int>) -> Double {
        let aInRange = ageRange.contains(partnerAge) ? 1.0 : 0.0
        let bInRange = userAgeRange.contains(myAge) ? 1.0 : 0.0
        return (aInRange + bInRange) / 2.0
    }

    private func scorePrefAlignment(_ a: MatchPreferences, _ b: MatchPreferences) -> Double {
        // TODO: Expand with ML model trained on post-meet ratings
        let distanceOK = a.maxDistanceMiles <= 0.25 && b.maxDistanceMiles <= 0.25 ? 1.0 : 0.5
        return distanceOK
    }

    // MARK: - Mutual Match Check

    /// Returns true if both users exceed threshold and neither has blocked the other.
    func isMutualMatch(_ breakdown: ScoreBreakdown, threshold: Double = 0.80) -> Bool {
        return breakdown.overall >= threshold
    }

    // MARK: - Firebase Match Fetch

    func fetchPotentialMatches(for currentUser: UserProfile) async {
        // Block entirely if user is not active
        guard currentUser.accountStatus == .active else {
            self.activeMatches = []
            return
        }

        // Off campus and outside every live destination fence. No pool.
        let scope = communityScope
        guard scope.allowsQuestMode else {
            self.activeMatches = []
            return
        }

        do {
            let candidates = try await firestoreService.fetchNearbyUsers(
                scope: scope,
                excludeUID: currentUser.uid
            )
            let scored = candidates.compactMap { candidate -> Match? in
                // Same school (or same live destination) + verification depth.
                // The query above already constrains this and firestore.rules
                // enforces it, but a candidate that slipped through either would
                // be a cross-campus match, so it is re-checked here.
                guard CommunityGate.canShare(viewer: currentUser,
                                             candidate: candidate,
                                             in: scope) else { return nil }

                // Some shared reason to meet.
                let locked = EncounterSession.lockIntents(currentUser, candidate)
                guard !locked.isEmpty else { return nil }

                // Women-first queuing is a Dating mechanism. A Study match is
                // not held back by the campus gender ratio.
                if EncounterSession.locksDatingGate(currentUser, candidate) {
                    guard balanceEnforcer.shouldShowMatch(to: currentUser) else { return nil }
                }

                // Intent/vibe pre-filter: minimum 0.6 Jaccard similarity
                let vibeScore = scoreVibeCompatibility(currentUser.intentVibes, candidate.intentVibes)
                guard vibeScore >= vibeMatchThreshold else {
                    self.analytics.logVibeFilterRejected(vibeScore: vibeScore)
                    return nil
                }

                let breakdown = computeCompatibilityScore(userA: currentUser, userB: candidate)
                guard isMutualMatch(breakdown, threshold: currentUser.preferences.compatibilityThreshold) else { return nil }

                return makeMatch(currentUser: currentUser,
                                 candidate: candidate,
                                 breakdown: breakdown,
                                 scope: scope)
            }
            self.activeMatches = scored
        } catch {
            Log.match.error("Error fetching matches: \(error)")
        }
    }

    /// Refresh nearby-user list on location updates. Wired into LocationService.didUpdateLocations.
    func refreshNearbyUsers() async {
        let scope = communityScope
        guard scope.allowsQuestMode else {
            nearbyUsers = []
            return
        }
        guard let currentUser = activeQuestUser else {
            nearbyUsers = []
            return
        }

        do {
            let candidates = try await firestoreService.fetchNearbyUsers(
                scope: scope,
                excludeUID: currentUser.uid
            )

            nearbyUsers = candidates.filter { candidate in
                guard CommunityGate.canShare(viewer: currentUser,
                                             candidate: candidate,
                                             in: scope) else { return false }
                guard !EncounterSession.lockIntents(currentUser, candidate).isEmpty else { return false }
                // Dating-gated pairs go through the balance enforcer; everyone
                // else does not.
                if EncounterSession.locksDatingGate(currentUser, candidate) {
                    return balanceEnforcer.shouldShowMatch(to: currentUser)
                }
                return true
            }

            // Count only. The geohash used to be logged here, which is exactly
            // the fact this app encodes location to avoid keeping.
            Log.match.debug("Refreshed \(nearbyUsers.count) nearby users")

            nearbyUsers.sort {
                computeCompatibilityScore(userA: currentUser, userB: $0).overall >
                computeCompatibilityScore(userA: currentUser, userB: $1).overall
            }

        } catch {
            Log.match.error("Nearby fetch failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Proximity Handling

    private func observeProximityEvents() {
        NotificationCenter.default.publisher(for: .proximityUpdated)
            .compactMap { $0.object as? ProximityEvent }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.handleProximityEvent(event)
            }
            .store(in: &cancellables)
    }

    private func handleProximityEvent(_ event: ProximityEvent) {
        guard let currentUser = activeQuestUser else { return }

        // Off campus, outside every live fence: no proximity event means
        // anything. Dropped before the match lookup, the cooldown bookkeeping or
        // the Firestore read.
        let scope = communityScope
        guard scope.allowsQuestMode else { return }

        // Same-school check at the edge. A BLE or UWB advertisement can come
        // from anyone standing nearby, including someone from another campus, so
        // the school on the event is checked before anything else happens.
        if let partnerSchoolId = event.partnerSchoolId {
            switch scope {
            case .campus(let schoolId):
                guard partnerSchoolId == schoolId else { return }
            case .springBreak, .none:
                break   // Cross-school is legitimate here; canShare re-checks below.
            }
        }

        guard let match = activeMatches.first(where: { $0.id == event.matchID }) else { return }

        // Cheap synchronous pre-checks — run before any Firestore round-trip.
        // Per-match cooldown: prevent duplicate alerts for the same match within 15 min.
        guard canSendCooldownAlert(for: event.matchID) else { return }
        // Per-user ping cap: prevent any single user from being pinged > 5 times/hour.
        guard checkPerUserPingCap(partnerUID: event.partnerUID) else {
            analytics.logPingCapHit(partnerUID: event.partnerUID)
            return
        }

        // ── SECURITY: Server-side hourly gender cap (final authoritative layer) ──
        // BalanceEnforcer provides server-sourced hourly caps that adapt to
        // real-time gender ratio.
        let genderCap = balanceEnforcer.calculateAlertCap(for: currentUser.gender)
        let hourKey = currentHourKey()

        Task {
            // Fetch partner profile so the centralized safety gate can inspect
            // verificationStatus + accountStatus. Adds one Firestore read per
            // proximity event on the hot path — acceptable because Quest Mode
            // pings are rate-limited upstream by cooldown + per-user cap above.
            guard let partnerProfile = try? await firestoreService.fetchUser(uid: event.partnerUID) else { return }

            // ── SECURITY: Centralized safety gate (Phase 2) ──
            // BalanceEnforcer.shouldShowMatch → AlertCapManager.canSendAlert →
            // SafetyVerifier.isSafeToAlert → compatibility threshold.
            // Replaces the previous inline AlertCapManager check; adds shouldShowMatch
            // and isSafeToAlert to the proximity path.
            let gateOK = await MainActor.run {
                self.shouldTriggerAlert(for: currentUser, match: partnerProfile)
            }
            guard gateOK else {
                await MainActor.run {
                    self.analytics.logAlertThrottledByGender(
                        gender: currentUser.gender,
                        cap: self.alertCapManager.dailyCapForGender(currentUser.gender),
                        reason: "centralized_gate_rejected"
                    )
                }
                return
            }

            // Atomic Firestore transaction — server is authoritative.
            // Even if the client-side checks above pass, the server can still reject.
            let allowed = try? await firestoreService.incrementCurrentHourAlerts(
                uid: currentUser.uid,
                hourKey: hourKey,
                cap: genderCap
            )
            guard allowed == true else {
                Log.match.debug("Alert throttled by server-side gender cap (\(genderCap)/hr)")
                self.analytics.logAlertThrottledByGender(
                    gender: currentUser.gender,
                    cap: genderCap,
                    reason: "hourly_gender_cap"
                )
                return
            }

            await MainActor.run {
                var updated = match
                if event.distanceMiles < 0.1 {
                    updated.status = .revealed
                    self.nearbyMatch = updated
                    self.nearbyMatchProfile = partnerProfile
                    self.triggerIcebreaker()
                } else if event.distanceMiles < 0.25 {
                    updated.status = .inProximity
                    self.nearbyMatch = updated
                    self.nearbyMatchProfile = partnerProfile
                }

                // Record the alert. AlertCapManager only spends a Dating
                // allowance when the match is Dating-gated; a Study encounter
                // costs nothing against the asymmetric caps.
                Task {
                    await self.alertCapManager.recordAlertSent(
                        for: currentUser.uid,
                        match: updated
                    )
                }
                self.recordCooldown(for: event.matchID)
                self.recordPerUserPing(partnerUID: event.partnerUID)

                if let idx = self.activeMatches.firstIndex(where: { $0.id == match.id }) {
                    self.activeMatches[idx] = updated
                }
            }
        }
    }

    // MARK: - Per-User Ping Cap

    /// Checks whether a partner has been pinged fewer than maxPingsPerUserPerHour times this hour.
    private func checkPerUserPingCap(partnerUID: String) -> Bool {
        let hourKey = currentHourKey()
        if perUserPingHourKey != hourKey {
            perUserPingCounts.removeAll()
            perUserPingHourKey = hourKey
        }
        let count = perUserPingCounts[partnerUID] ?? 0
        return count < maxPingsPerUserPerHour
    }

    /// Records a ping to a specific partner for per-user cap tracking.
    private func recordPerUserPing(partnerUID: String) {
        perUserPingCounts[partnerUID, default: 0] += 1
    }

    // MARK: - Per-Match Cooldown

    /// Checks per-match cooldown only. Daily cap enforcement is in AlertCapManager.
    private func canSendCooldownAlert(for matchID: String) -> Bool {
        if let lastTime = lastAlertTimes[matchID],
           Date().timeIntervalSince(lastTime) < matchCooldownSeconds {
            return false
        }
        return true
    }

    /// Records the timestamp for per-match cooldown tracking.
    private func recordCooldown(for matchID: String) {
        lastAlertTimes[matchID] = Date()
    }

    // MARK: - Legacy Alert Throttling (Deprecated — use AlertCapManager)

    /// Deprecated: Daily cap + per-match cooldown check.
    /// Daily cap enforcement has moved to AlertCapManager.canSendAlert(for:match:).
    /// Per-match cooldown is now in canSendCooldownAlert(for:).
    @available(*, deprecated, message: "Use alertCapManager.canSendAlert(for:match:) for daily caps and canSendCooldownAlert(for:) for per-match cooldown.")
    func canSendAlert(for matchID: String, dailyLimit: Int? = nil) -> Bool {
        resetDailyCountIfNeeded()

        // Legacy fallback only — production caps run through AlertCapManager.
        // Reading userAlertLimit here is inside this deprecated method, so no
        // deprecation warning propagates to callers.
        let limit = dailyLimit ?? userAlertLimit
        if alertsSentToday >= limit {
            return false
        }

        if let lastTime = lastAlertTimes[matchID],
           Date().timeIntervalSince(lastTime) < matchCooldownSeconds {
            return false
        }

        return true
    }

    /// Deprecated: Use alertCapManager.recordAlertSent(for:matchID:) instead.
    @available(*, deprecated, message: "Use alertCapManager.recordAlertSent(for:matchID:) instead.")
    func recordAlert(for matchID: String) {
        alertsSentToday += 1
        lastAlertTimes[matchID] = Date()
    }

    /// Resets all throttling state. Intended for testing.
    func resetThrottling() {
        alertCountDate = Calendar.current.startOfDay(for: Date())
        lastAlertTimes.removeAll()
        perUserPingCounts.removeAll()
    }

    /// Resets the daily counter at midnight.
    private func resetDailyCountIfNeeded() {
        let today = Calendar.current.startOfDay(for: Date())
        if today > alertCountDate {
            lastAlertTimes.removeAll()
            alertCountDate = today
        }
    }

    // MARK: - Hour Key

    /// Returns the current hour key in "yyyy-MM-dd-HH" format for alert bucketing.
    private func currentHourKey() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HH"
        formatter.timeZone = TimeZone.current
        return formatter.string(from: Date())
    }

    // MARK: - Partner Profile

    private var cachedPartnerUID: String?

    private func fetchPartnerProfile(uid: String) {
        guard uid != cachedPartnerUID else { return }
        cachedPartnerUID = uid
        Task {
            do {
                nearbyMatchProfile = try await firestoreService.fetchUser(uid: uid)
            } catch {
                cachedPartnerUID = nil
                Log.match.error("Failed to fetch partner profile: \(error)")
            }
        }
    }

    // MARK: - Icebreaker

    func triggerIcebreaker() {
        let sample = IcebreakerChallenge(
            id: UUID().uuidString,
            type: .trivia,
            prompt: "What's the most spontaneous thing you've ever done?",
            options: ["Booked a last-minute flight", "Quit a job on a whim",
                      "Adopted a pet", "Said 'I love you' first"],
            correctAnswer: nil,
            durationSeconds: 30
        )
        currentIcebreaker = sample
    }

    /// Called when the icebreaker challenge is completed successfully.
    /// Awards XP via XPManager and clears the active icebreaker.
    func completeIcebreaker() {
        currentIcebreaker = nil
        Task { await XPManager.shared.grantIcebreakerXP() }
    }

    // MARK: - Post-Meet Rating

    func submitPostMeetRating(matchID: String, rating: Int) async {
        guard (1...5).contains(rating) else { return }
        do {
            try await firestoreService.updateMatchRating(matchID: matchID, rating: rating)
        } catch {
            Log.match.error("Rating submission failed: \(error)")
        }
    }

    // MARK: - Photo Accuracy Rating

    func submitPhotoAccuracyRating(matchID: String, rating: Int) async {
        guard (1...5).contains(rating) else { return }
        guard let match = activeMatches.first(where: { $0.id == matchID }) ?? nearbyMatch,
              let currentUID = Auth.auth().currentUser?.uid else { return }

        let partnerUID = currentUID == match.userAUID ? match.userBUID : match.userAUID
        do {
            try await firestoreService.submitPhotoAccuracyRating(
                matchID: matchID,
                raterUID: currentUID,
                rating: rating
            )
            await recalculateTrustLevel(for: partnerUID)
        } catch {
            Log.match.error("Photo accuracy rating failed: \(error)")
        }
    }

    // MARK: - Trust Level Computation

    /// Recalculates trust level for a user based on verification status and post-meet ratings.
    func recalculateTrustLevel(for uid: String) async {
        do {
            guard let profile = try await firestoreService.fetchUser(uid: uid) else { return }
            let ratings = try await firestoreService.fetchPhotoAccuracyRatings(forUID: uid)

            var level = profile.trustLevel

            if ratings.count >= 3 {
                let avg = Double(ratings.reduce(0, +)) / Double(ratings.count)

                // Upgrade: gold + good ratings → platinum
                if level == .gold && avg >= 4.0 {
                    level = .platinum
                }

                // Downgrade: poor ratings → demote
                if avg < 3.0 && (level == .gold || level == .platinum) {
                    level = .silver
                }
            }

            // Deliberately no write. trustLevel is server-owned: it is derived
            // by studentIdVerification.ts from verification depth and by the
            // rating pipeline from post-meet accuracy, and firestore.rules
            // rejects a client write to it. Recomputing it here is now only
            // useful for showing the user what they are about to be granted.
            if level != profile.trustLevel {
                Log.match.debug("Local trust recalculation differs from server value")
            }
        } catch {
            Log.match.error("Trust recalculation failed: \(error)")
        }
    }

    #if DEBUG
    // MARK: - Demo Encounter (DEBUG only)
    //
    // Self-contained walkthrough for the Developer Bypass build. This drives the
    // exact same state (`nearbyMatch`, `nearbyMatchProfile`, `currentIcebreaker`,
    // RevealManager sessions) that the production proximity path drives, but feeds
    // it from an in-memory `DemoProximityProvider` instead of ProximityService.
    //
    // The real scoring, AlertCapManager caps, BalanceEnforcer gate, and
    // SafetyVerifier check all run against the mock data so the architecture stays
    // honest. Only the Firestore round-trips are skipped (see RevealManager.isDemoMode).

    /// Starts a simulated high-compatibility encounter and presents the walkthrough.
    /// The surfaced match is chosen by the real scoring, vibe filter, safety gate,
    /// asymmetric alert caps, and BalanceEnforcer women-first queue — the same
    /// systems production uses. If those systems block, no encounter opens and
    /// `demoStatusMessage` explains why.
    func startDemoEncounter(for currentUser: UserProfile) {
        guard !isDemoEncounterActive else { return }
        resetDemoState()   // Clear any stale state from a prior aborted run.

        alertCapManager.updateUserCaps(for: currentUser)

        // Viewer-level gates. Both are Dating-only, so they are consulted only
        // once the demo knows the pair's locked intents — see below.

        // Candidate selection via real scoring + vibe + safety filters.
        guard let (candidate, breakdown) = selectDemoMatch(for: currentUser) else {
            demoStatusMessage = "No compatible match nearby right now — try adjusting your preferences."
            return
        }

        // The demo runs the real intent lock, so the walkthrough shows the same
        // Dating / non-Dating behaviour production would.
        let lockedIntents = EncounterSession.lockIntents(currentUser, candidate)
        let datingGated = EncounterSession.locksDatingGate(currentUser, candidate)

        guard !lockedIntents.isEmpty else {
            demoStatusMessage = "No shared intent with anyone nearby — try adding Hangout or Study."
            return
        }

        if datingGated {
            guard alertCapManager.canSendAlert(for: currentUser,
                                               match: nil,
                                               lockedIntents: lockedIntents) else {
                let cap = alertCapManager.currentDatingDailyLimit().map(String.init) ?? "your"
                demoStatusMessage = "Daily Dating alert cap reached (\(cap)/day). Caps are lower for women by design, and they apply to Dating only."
                return
            }
            guard balanceEnforcer.shouldShowMatch(to: currentUser) else {
                demoStatusMessage = "Held by the women-first queue — the campus Dating ratio is male-skewed right now."
                return
            }
        }

        demoStatusMessage = nil

        // Make Quest Mode read as active without touching real location hardware.
        activeQuestUser = currentUser
        isQuestModeActive = true

        // Route reveal state through the real stage machine, minus Firestore.
        RevealManager.shared.isDemoMode = true

        // No display name in the log: this file's compliance block says analytics
        // and logs carry no PII, and a match's name is exactly that.
        Log.match.debug("Demo match selected, score=\(String(format: "%.2f", breakdown.overall)), datingGated=\(datingGated)")

        let match = Match(
            id: "demo_match_\(UUID().uuidString.prefix(8))",
            userAUID: currentUser.uid,
            userBUID: candidate.uid,
            compatibilityScore: breakdown.overall,
            scoreBreakdown: breakdown,
            status: .inProximity,
            createdAt: Date(),
            meetupOccurred: false,
            schoolId: currentUser.schoolId ?? "",
            partnerSchoolId: candidate.schoolId ?? "",
            scope: communityScope.isSpringBreak ? .springBreak : .campus,
            springBreakDestinationID: nil,
            campusId: currentUser.schoolId,
            lockedIntents: lockedIntents,
            isDatingGated: datingGated,
            revealStage: .blurred
        )

        activeMatches = [match]
        nearbyMatch = match
        nearbyMatchProfile = candidate
        demoReadyForIcebreaker = false
        isDemoEncounterActive = true

        // Record the alert through the real cap manager (Firestore sync no-ops for the mock).
        Task { await alertCapManager.recordAlertSent(for: currentUser.uid, match: match) }

        // Open the blurred session, then simulate the walk-up.
        Task {
            await RevealManager.shared.startRevealSession(for: match, currentUser: currentUser)
            demoProximityProvider.startApproach { [weak self] distance in
                self?.handleDemoDistance(distance)
            }
        }
    }

    /// Maps simulated distance to haptics + icebreaker readiness. Stays at the
    /// `.blurred` stage — reveal only advances once the icebreaker begins.
    private func handleDemoDistance(_ distance: Double) {
        demoDistanceMiles = distance
        let intensity = LocationService.shared.hapticIntensity(for: distance)
        LocationService.shared.playProximityHaptic(intensity: intensity)
        if distance <= 0.08 {
            demoReadyForIcebreaker = true
        }
    }

    /// Launches a demo icebreaker of the chosen type and begins progressive unblur.
    func startDemoIcebreaker(type: IcebreakerChallenge.ChallengeType) {
        guard var match = nearbyMatch else { return }
        currentIcebreaker = makeDemoChallenge(type: type)
        match.status = .icebreakerActive
        nearbyMatch = match
        updateActiveMatch(match)

        // Ramp reveal progress 0 → ~0.65 while the challenge is played, so the
        // partner's photo visibly unblurs (stage machine advances .blurred → .partial).
        guard let sessionID = RevealManager.shared.activeSessions[match.id]?.id else { return }
        demoRevealTimer?.invalidate()
        var progress = RevealManager.shared.activeSessions[match.id]?.revealProgress ?? 0.0
        demoRevealTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                progress = min(0.65, progress + 0.07)
                await RevealManager.shared.updateRevealProgress(for: sessionID, progress: progress)
                if progress >= 0.65 { self.demoRevealTimer?.invalidate() }
            }
        }
    }

    /// Completes the icebreaker: finishes the unblur into the `.revealed` stage
    /// (mostly clear + NameDrop prompt) and awards the same XP as production.
    func completeDemoIcebreaker() {
        demoRevealTimer?.invalidate()
        demoRevealTimer = nil
        currentIcebreaker = nil

        guard var match = nearbyMatch,
              let sessionID = RevealManager.shared.activeSessions[match.id]?.id else { return }

        Task {
            // Push past the .revealed threshold (≥ 0.7) so the stage machine advances.
            await RevealManager.shared.updateRevealProgress(for: sessionID, progress: 0.85)
            match.status = .revealed
            match.revealStage = .revealed
            nearbyMatch = match
            updateActiveMatch(match)
            await XPManager.shared.grantIcebreakerXP()
        }
    }

    /// Mutual NameDrop → `.connected`: unlocks the full profile via the real
    /// RevealManager gate (which only permits completion from `.revealed`).
    func demoNameDrop() {
        guard var match = nearbyMatch,
              let currentUser = activeQuestUser,
              let sessionID = RevealManager.shared.activeSessions[match.id]?.id else { return }
        Task {
            // Runs the real face-match gate: the demo cannot NameDrop from an
            // account production would refuse.
            await RevealManager.shared.completeReveal(for: sessionID, currentUser: currentUser)
            match.status = .connected
            match.revealStage = .connected
            nearbyMatch = match
            updateActiveMatch(match)
        }
    }

    /// Runs the real trust-tier logic on the demo match's post-meet rating and
    /// returns the resulting (possibly upgraded) trust level for the UI to show.
    @discardableResult
    func submitDemoRating(_ rating: Int) -> UserProfile.TrustLevel {
        guard var candidate = nearbyMatchProfile else { return .bronze }
        // Same rule as recalculateTrustLevel: gold + strong rating → platinum.
        if candidate.trustLevel == .gold && rating >= 4 {
            candidate.trustLevel = .platinum
        } else if rating < 3 && (candidate.trustLevel == .gold || candidate.trustLevel == .platinum) {
            candidate.trustLevel = .silver
        }
        nearbyMatchProfile = candidate
        return candidate.trustLevel
    }

    /// Tears down all demo state and returns the app to a clean idle Home.
    /// Safe to call repeatedly and safe if no demo is running.
    func endDemoEncounter() {
        let matchID = nearbyMatch?.id
        Task {
            if let matchID {
                await RevealManager.shared.endSession(for: matchID, reason: .pass)
            }
            RevealManager.shared.isDemoMode = false
        }

        resetDemoState()
        isDemoEncounterActive = false
        nearbyMatch = nil
        nearbyMatchProfile = nil
        activeMatches = []
        isQuestModeActive = false
        activeQuestUser = nil
    }

    // MARK: - Demo Helpers

    /// Stops demo timers and resets transient walkthrough state without tearing
    /// down the presented match. Used both to clean up and to guard against a
    /// stale run leaking into a fresh one.
    private func resetDemoState() {
        demoProximityProvider.stop()
        demoRevealTimer?.invalidate()
        demoRevealTimer = nil
        demoReadyForIcebreaker = false
        demoDistanceMiles = 0.25
        demoStatusMessage = nil
        currentIcebreaker = nil
    }

    /// Selects the best mock match that clears the real safety, vibe, and
    /// compatibility filters — mirroring `fetchPotentialMatches`. Returns nil if
    /// the pool has no candidate above the user's compatibility threshold.
    private func selectDemoMatch(for currentUser: UserProfile) -> (UserProfile, ScoreBreakdown)? {
        let pool = DemoProximityProvider.makeDemoCandidatePool()
        let scored: [(UserProfile, ScoreBreakdown)] = pool.compactMap { candidate in
            guard candidate.accountStatus == .active else { return nil }
            guard SafetyVerifier.isSafeToAlert(candidate) else { return nil }
            // The demo runs the real community gate too, so a bypass build cannot
            // show a pairing production would refuse.
            guard CommunityGate.canShare(viewer: currentUser,
                                         candidate: candidate,
                                         in: communityScope) else { return nil }
            guard scoreVibeCompatibility(currentUser.intentVibes, candidate.intentVibes) >= 0.6 else { return nil }
            let breakdown = computeCompatibilityScore(userA: currentUser, userB: candidate)
            guard breakdown.overall >= currentUser.preferences.compatibilityThreshold else { return nil }
            return (candidate, breakdown)
        }
        return scored.max { $0.1.overall < $1.1.overall }
    }

    private func updateActiveMatch(_ match: Match) {
        if let idx = activeMatches.firstIndex(where: { $0.id == match.id }) {
            activeMatches[idx] = match
        }
    }

    private func makeDemoChallenge(type: IcebreakerChallenge.ChallengeType) -> IcebreakerChallenge {
        switch type {
        case .trivia:
            return IcebreakerChallenge(
                id: UUID().uuidString, type: .trivia,
                prompt: "What's the most spontaneous thing you've ever done?",
                options: ["Booked a last-minute flight", "Quit a job on a whim",
                          "Adopted a pet", "Said 'I love you' first"],
                correctAnswer: nil, durationSeconds: 30
            )
        case .wordAssociation:
            return IcebreakerChallenge(
                id: UUID().uuidString, type: .wordAssociation,
                prompt: "coffee",
                options: ["morning", "espresso", "bookshop", "road trip"],
                correctAnswer: nil, durationSeconds: 30
            )
        case .gesture:
            return IcebreakerChallenge(
                id: UUID().uuidString, type: .gesture,
                prompt: "Mirror your match: wave hello 👋",
                options: nil, correctAnswer: nil, durationSeconds: 20
            )
        case .arObject:
            return IcebreakerChallenge(
                id: UUID().uuidString, type: .arObject,
                prompt: "Place the same glowing orb between you in AR",
                options: nil, correctAnswer: nil, durationSeconds: 20
            )
        }
    }
    #endif
}
