import XCTest
@testable import DateQuestAR

final class MatchManagerTests: XCTestCase {
    var matchManager: MatchManager!

    override func setUp() {
        super.setUp()
        matchManager = MatchManager.shared
    }

    // MARK: - Interest Overlap

    func test_interestOverlap_perfectMatch() {
        let (a, b) = makeProfiles(interestsA: ["hiking", "coffee"],
                                   interestsB: ["hiking", "coffee"])
        let score = matchManager.computeCompatibilityScore(userA: a, userB: b)
        XCTAssertEqual(score.interestOverlap, 1.0, accuracy: 0.01)
    }

    func test_interestOverlap_noMatch() {
        let (a, b) = makeProfiles(interestsA: ["hiking"], interestsB: ["gaming"])
        let score = matchManager.computeCompatibilityScore(userA: a, userB: b)
        XCTAssertEqual(score.interestOverlap, 0.0, accuracy: 0.01)
    }

    func test_interestOverlap_partial() {
        let (a, b) = makeProfiles(interestsA: ["hiking", "coffee", "travel"],
                                   interestsB: ["hiking", "gaming"])
        let score = matchManager.computeCompatibilityScore(userA: a, userB: b)
        // Intersection: {hiking} = 1, Union: {hiking, coffee, travel, gaming} = 4 → 0.25
        XCTAssertEqual(score.interestOverlap, 0.25, accuracy: 0.01)
    }

    // MARK: - Mutual Match Threshold

    func test_isMutualMatch_aboveThreshold() {
        let breakdown = ScoreBreakdown(interestOverlap: 1.0, relationshipTypeMatch: 1.0,
                                       ageCompatibility: 1.0, preferenceAlignment: 1.0)
        XCTAssertTrue(matchManager.isMutualMatch(breakdown, threshold: 0.80))
    }

    func test_isMutualMatch_belowThreshold() {
        let breakdown = ScoreBreakdown(interestOverlap: 0.5, relationshipTypeMatch: 0.5,
                                       ageCompatibility: 0.5, preferenceAlignment: 0.5)
        XCTAssertFalse(matchManager.isMutualMatch(breakdown, threshold: 0.80))
    }

    func test_isMutualMatch_exactThreshold() {
        let breakdown = ScoreBreakdown(interestOverlap: 0.8, relationshipTypeMatch: 0.8,
                                       ageCompatibility: 0.8, preferenceAlignment: 0.8)
        XCTAssertTrue(matchManager.isMutualMatch(breakdown, threshold: 0.80))
    }

    // MARK: - Age Compatibility

    func test_ageCompatibility_bothInRange() {
        var prefs = defaultPrefs()
        prefs.ageRange = 25...35
        var prefsB = defaultPrefs()
        prefsB.ageRange = 22...30
        var a = makeProfile(uid: "a", age: 27, prefs: prefs)
        var b = makeProfile(uid: "b", age: 28, prefs: prefsB)
        let score = matchManager.computeCompatibilityScore(userA: a, userB: b)
        XCTAssertEqual(score.ageCompatibility, 1.0, accuracy: 0.01)
    }

    func test_ageCompatibility_oneOutOfRange() {
        var prefs = defaultPrefs()
        prefs.ageRange = 21...24  // excludes B's age (28)
        var prefsB = defaultPrefs()
        prefsB.ageRange = 25...35  // includes A's age (22)
        let a = makeProfile(uid: "a", age: 22, prefs: prefs)
        let b = makeProfile(uid: "b", age: 28, prefs: prefsB)
        let score = matchManager.computeCompatibilityScore(userA: a, userB: b)
        XCTAssertEqual(score.ageCompatibility, 0.5, accuracy: 0.01)
    }

    // MARK: - Haptic Intensity

    func test_hapticIntensity_atMaxDistance() {
        let intensity = LocationService.shared.hapticIntensity(for: 0.25)
        XCTAssertEqual(intensity, 0.0, accuracy: 0.01)
    }

    func test_hapticIntensity_atZeroDistance() {
        let intensity = LocationService.shared.hapticIntensity(for: 0.0)
        XCTAssertEqual(intensity, 1.0, accuracy: 0.01)
    }

    func test_hapticIntensity_midpoint() {
        let intensity = LocationService.shared.hapticIntensity(for: 0.125)
        XCTAssertEqual(intensity, 0.5, accuracy: 0.05)
    }

    // MARK: - Daily Alert Cap

    func test_dailyAlertCap_allowsUnderLimit() {
        matchManager.resetThrottling()
        matchManager.userAlertLimit = 3

        XCTAssertTrue(matchManager.canSendAlert(for: "match-1"))
        matchManager.recordAlert(for: "match-1")
        XCTAssertEqual(matchManager.alertsSentToday, 1)
    }

    func test_dailyAlertCap_blocksAtLimit() {
        matchManager.resetThrottling()
        matchManager.userAlertLimit = 2

        matchManager.recordAlert(for: "match-1")
        matchManager.recordAlert(for: "match-2")

        XCTAssertFalse(matchManager.canSendAlert(for: "match-3"))
    }

    // MARK: - Per-Match Cooldown

    func test_matchCooldown_blocksSameMatchWithinWindow() {
        matchManager.resetThrottling()
        matchManager.userAlertLimit = 100

        matchManager.recordAlert(for: "match-1")
        // Immediately after, same match should be blocked by cooldown
        XCTAssertFalse(matchManager.canSendAlert(for: "match-1"))
    }

    func test_matchCooldown_allowsDifferentMatch() {
        matchManager.resetThrottling()
        matchManager.userAlertLimit = 100

        matchManager.recordAlert(for: "match-1")
        // Different match should still be allowed
        XCTAssertTrue(matchManager.canSendAlert(for: "match-2"))
    }

    // MARK: - Helpers

    private func makeProfiles(interestsA: [String],
                               interestsB: [String]) -> (UserProfile, UserProfile) {
        var pa = defaultPrefs(); pa.interests = interestsA
        var pb = defaultPrefs(); pb.interests = interestsB
        return (makeProfile(uid: "a", age: 27, prefs: pa),
                makeProfile(uid: "b", age: 28, prefs: pb))
    }

    private func defaultPrefs() -> MatchPreferences {
        MatchPreferences(ageRange: 22...35, maxDistanceMiles: 0.25,
                         relationshipTypes: [.longTerm], genderPreferences: [],
                         interests: [], dealbreakers: [], compatibilityThreshold: 0.80)
    }

    private func makeProfile(uid: String, age: Int, prefs: MatchPreferences) -> UserProfile {
        UserProfile(uid: uid, displayName: "Test", age: age, bio: "",
                    photoURLs: [], selfDescriptors: [],
                    verificationStatus: .verified, preferences: prefs,
                    privacySettings: PrivacySettings(questModeEnabled: true, visibilityRadius: 0.25,
                                                     autoPauseZones: [], alertLimit: 5,
                                                     locationSharingMode: .anonymized,
                                                     showInCommunityEvents: true),
                    gamification: GamificationProfile(level: 1, xp: 0, badges: [],
                                                      questsCompleted: 0, totalConnections: 0),
                    createdAt: Date(), lastActive: Date())
    }
}
