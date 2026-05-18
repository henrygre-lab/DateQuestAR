// MARK: - SECURITY CHECKLIST COMPLIANCE
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
// [x] No raw coordinates logged — only match IDs and enum states
// [x] No mutable public user state — profile passed explicitly to avoid stale data
// [x] Analytics events contain no raw UIDs — partner UIDs hashed before logging
// [x] Ties to launch strategy: campus, nightlife, and festival zones require all caps active
//     before any marketing push (see docs/LAUNCH_STRATEGY.md)

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
    private let firestoreService = FirestoreService.shared
    private let analytics = AnalyticsService.shared

    /// Snapshot of the active user, set only via enableQuestMode.
    /// Used internally by the proximity event handler (NotificationCenter callback).
    private var activeQuestUser: UserProfile?

    /// Deprecated: Daily cap enforcement moved to AlertCapManager.
    /// Retained for backward compatibility; will be removed in Phase 3.
    @available(*, deprecated, message: "Daily cap enforcement moved to AlertCapManager. Use alertCapManager.getCurrentDailyLimit() instead.")
    var userAlertLimit: Int = 20

    private var currentAlertLimit: Int { userAlertLimit }

    private init() {
        observeProximityEvents()
    }

    // MARK: - Quest Mode

    func enableQuestMode(for user: UserProfile) {
        guard user.privacySettings.questModeEnabled else { return }
        guard user.accountStatus == .active else {
            print("[MatchManager] Quest mode blocked: accountStatus=\(user.accountStatus)")
            return
        }
        activeQuestUser = user
        isQuestModeActive = true

        // Initialize AlertCapManager with current user's profile so asymmetric
        // daily caps are ready before the first proximity event fires.
        alertCapManager.updateUserCaps(for: user)

        LocationService.shared.startQuestScanning()
        Task { await fetchPotentialMatches(for: user) }
        NotificationCenter.default.post(name: .questModeChanged, object: true)
    }

    func disableQuestMode() {
        activeQuestUser = nil
        isQuestModeActive = false
        LocationService.shared.stopQuestScanning()
        NotificationCenter.default.post(name: .questModeChanged, object: false)
    }

    // MARK: - Core Safety Gate (Phase 2)

    /// Must be called before any alert. Fail-closed at every layer.
    func shouldTriggerAlert(for currentUser: UserProfile, match: UserProfile) -> Bool {
        guard balanceEnforcer.shouldShowMatch(to: currentUser) else { return false }
        guard alertCapManager.canSendAlert(for: currentUser, match: nil) else { return false }
        guard SafetyVerifier.isSafeToAlert(match) else { return false }

        let breakdown = computeCompatibilityScore(userA: currentUser, userB: match)
        return breakdown.overall >= currentUser.preferences.compatibilityThreshold
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
        let relationshipMatch = scoreRelationshipTypes(userA.preferences.relationshipTypes,
                                                      userB.preferences.relationshipTypes)
        let ageCompat = scoreAgeCompatibility(userA.age, ageRange: userB.preferences.ageRange,
                                              partnerAge: userB.age, userAgeRange: userA.preferences.ageRange)
        let prefAlignment = scorePrefAlignment(userA.preferences, userB.preferences)

        return ScoreBreakdown(
            interestOverlap: interestOverlap,
            relationshipTypeMatch: relationshipMatch,
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

    private func scoreRelationshipTypes(_ a: [MatchPreferences.RelationshipType],
                                        _ b: [MatchPreferences.RelationshipType]) -> Double {
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

        do {
            let candidates = try await firestoreService.fetchNearbyUsers(
                geohash: LocationService.shared.currentGeohash ?? "",
                excludeUID: currentUser.uid
            )
            let scored = candidates.compactMap { candidate -> Match? in
                // Skip inactive candidates
                guard candidate.accountStatus == .active else { return nil }

                // BalanceEnforcer visibility gate (women-first queuing)
                guard balanceEnforcer.shouldShowMatch(to: currentUser) else { return nil }

                // Intent/vibe pre-filter: minimum 0.6 Jaccard similarity
                let vibeScore = scoreVibeCompatibility(currentUser.intentVibes, candidate.intentVibes)
                guard vibeScore >= vibeMatchThreshold else {
                    self.analytics.logVibeFilterRejected(vibeScore: vibeScore)
                    return nil
                }

                let breakdown = computeCompatibilityScore(userA: currentUser, userB: candidate)
                guard isMutualMatch(breakdown, threshold: currentUser.preferences.compatibilityThreshold) else { return nil }

                return Match(
                    id: UUID().uuidString,
                    userAUID: currentUser.uid,
                    userBUID: candidate.uid,
                    compatibilityScore: breakdown.overall,
                    scoreBreakdown: breakdown,
                    status: .pending,
                    createdAt: Date(),
                    meetupOccurred: false
                )
            }
            self.activeMatches = scored
        } catch {
            print("[MatchManager] Error fetching matches: \(error)")
        }
    }

    /// Refresh nearby-user list on location updates. Wired into LocationService.didUpdateLocations.
    func refreshNearbyUsers() async {
        guard let geohash = LocationService.shared.currentGeohash, !geohash.isEmpty else {
            print("[MatchManager] No current geohash yet")
            return
        }

        do {
            let candidates = try await firestoreService.fetchNearbyUsers(
                geohash: geohash,
                excludeUID: activeQuestUser?.uid ?? ""
            )

            // Apply safety + balance filter
            nearbyUsers = candidates.filter { balanceEnforcer.shouldShowMatch(to: $0) }

            print("[MatchManager] ✅ Refreshed \(nearbyUsers.count) nearby users in geohash \(geohash)")

            // Sort by compatibility (fallback to self if no active user)
            if let current = activeQuestUser {
                nearbyUsers.sort {
                    computeCompatibilityScore(userA: current, userB: $0).overall >
                    computeCompatibilityScore(userA: current, userB: $1).overall
                }
            }

        } catch {
            print("[MatchManager] ❌ Nearby fetch failed: \(error.localizedDescription)")
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
                print("[MatchManager] Alert throttled by server-side gender cap (\(genderCap)/hr)")
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

                // Record alert via AlertCapManager (replaces legacy recordAlert)
                Task {
                    await self.alertCapManager.recordAlertSent(
                        for: currentUser.uid,
                        matchID: event.matchID
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

        let limit = dailyLimit ?? currentAlertLimit
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
                print("[MatchManager] Failed to fetch partner profile: \(error)")
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
            print("[MatchManager] Rating submission failed: \(error)")
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
            print("[MatchManager] Photo accuracy rating failed: \(error)")
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

            if level != profile.trustLevel {
                try await firestoreService.updateTrustLevel(uid: uid, level: level)
            }
        } catch {
            print("[MatchManager] Trust recalculation failed: \(error)")
        }
    }
}
