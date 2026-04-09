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

    // MARK: - Rate Limiting

    private(set) var alertsSentToday: Int = 0
    private var alertCountDate: Date = Calendar.current.startOfDay(for: Date())
    private var lastAlertTimes: [String: Date] = [:]  // matchID → last alert time

    /// Minimum seconds between alerts for the same match.
    private let matchCooldownSeconds: TimeInterval = 15 * 60  // 15 minutes

    private var cancellables = Set<AnyCancellable>()

    private init() {
        observeProximityEvents()
    }

    // MARK: - Quest Mode

    func enableQuestMode(for user: UserProfile) {
        guard user.privacySettings.questModeEnabled else { return }
        isQuestModeActive = true
        userAlertLimit = user.privacySettings.alertLimit
        LocationService.shared.startQuestScanning()
        Task { await fetchPotentialMatches(for: user) }
        NotificationCenter.default.post(name: .questModeChanged, object: true)
    }

    func disableQuestMode() {
        isQuestModeActive = false
        LocationService.shared.stopQuestScanning()
        NotificationCenter.default.post(name: .questModeChanged, object: false)
    }

    // MARK: - AI Compatibility Scoring

    /// Scores compatibility between two profiles. Returns a value 0.0–1.0.
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

    func fetchPotentialMatches(for user: UserProfile) async {
        do {
            let candidates = try await FirestoreService.shared.fetchNearbyUsers(
                geohash: LocationService.shared.currentGeohash ?? "",
                excludeUID: user.uid
            )
            let scored = candidates.compactMap { candidate -> Match? in
                let breakdown = computeCompatibilityScore(userA: user, userB: candidate)
                guard isMutualMatch(breakdown, threshold: user.preferences.compatibilityThreshold) else { return nil }
                return Match(
                    id: UUID().uuidString,
                    userAUID: user.uid,
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
        guard let match = activeMatches.first(where: { $0.id == event.matchID }) else { return }
        guard canSendAlert(for: event.matchID) else { return }

        var updated = match
        if event.distanceMiles < 0.1 {
            updated.status = .revealed
            nearbyMatch = updated
            fetchPartnerProfile(uid: event.partnerUID)
            triggerIcebreaker()
        } else if event.distanceMiles < 0.25 {
            updated.status = .inProximity
            nearbyMatch = updated
            fetchPartnerProfile(uid: event.partnerUID)
        }

        recordAlert(for: event.matchID)

        if let idx = activeMatches.firstIndex(where: { $0.id == match.id }) {
            activeMatches[idx] = updated
        }
    }

    // MARK: - Partner Profile

    private var cachedPartnerUID: String?

    private func fetchPartnerProfile(uid: String) {
        guard uid != cachedPartnerUID else { return }
        cachedPartnerUID = uid
        Task {
            do {
                nearbyMatchProfile = try await FirestoreService.shared.fetchUser(uid: uid)
            } catch {
                cachedPartnerUID = nil
                print("[MatchManager] Failed to fetch partner profile: \(error)")
            }
        }
    }

    // MARK: - Alert Throttling

    /// Checks daily cap and per-match cooldown before allowing an alert.
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

    /// Records an alert for daily cap and per-match cooldown tracking.
    func recordAlert(for matchID: String) {
        alertsSentToday += 1
        lastAlertTimes[matchID] = Date()
    }

    /// Resets all throttling state. Intended for testing.
    func resetThrottling() {
        alertsSentToday = 0
        alertCountDate = Calendar.current.startOfDay(for: Date())
        lastAlertTimes.removeAll()
    }

    /// Resets the daily counter at midnight.
    private func resetDailyCountIfNeeded() {
        let today = Calendar.current.startOfDay(for: Date())
        if today > alertCountDate {
            alertsSentToday = 0
            lastAlertTimes.removeAll()
            alertCountDate = today
        }
    }

    /// The active user's configured alert limit, falling back to a sensible default.
    var userAlertLimit: Int = 20

    private var currentAlertLimit: Int { userAlertLimit }

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

    // MARK: - Post-Meet Rating

    func submitPostMeetRating(matchID: String, rating: Int) async {
        guard (1...5).contains(rating) else { return }
        do {
            try await FirestoreService.shared.updateMatchRating(matchID: matchID, rating: rating)
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
            try await FirestoreService.shared.submitPhotoAccuracyRating(
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
            guard let profile = try await FirestoreService.shared.fetchUser(uid: uid) else { return }
            let ratings = try await FirestoreService.shared.fetchPhotoAccuracyRatings(forUID: uid)

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
                try await FirestoreService.shared.updateTrustLevel(uid: uid, level: level)
            }
        } catch {
            print("[MatchManager] Trust recalculation failed: \(error)")
        }
    }
}
