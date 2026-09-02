import XCTest
import FirebaseFirestore
@testable import Serendipity

// Core model and value-type tests. These do not require a live Firebase connection.

// The app module builds with MainActor-by-default isolation, so the model
// conformances these tests exercise (Comparable, Decodable) are MainActor-isolated.
// Annotating the whole case keeps that consistent rather than sprinkling
// per-test annotations — and it is an error, not a warning, under Swift 6.
@MainActor
final class SerendipityTests: XCTestCase {

    // MARK: - RevealStage Ordering

    func test_revealStageOrder_blurredFirst() {
        XCTAssertLessThan(RevealStage.blurred, RevealStage.partial)
        XCTAssertLessThan(RevealStage.partial, RevealStage.revealed)
        XCTAssertLessThan(RevealStage.revealed, RevealStage.connected)
    }

    func test_revealStageOrder_connectedIsMax() {
        for stage in RevealStage.allCases where stage != .connected {
            XCTAssertLessThan(stage, RevealStage.connected)
        }
    }

    // MARK: - EncounterSession Progress Clamping

    func test_clampProgress_clampsBelowZero() {
        XCTAssertEqual(EncounterSession.clampProgress(-0.5), 0.0)
    }

    func test_clampProgress_clampsAboveOne() {
        XCTAssertEqual(EncounterSession.clampProgress(1.5), 1.0)
    }

    func test_clampProgress_passesValidValue() {
        XCTAssertEqual(EncounterSession.clampProgress(0.7), 0.7, accuracy: 0.001)
    }

    func test_clampProgress_boundaryZero() {
        XCTAssertEqual(EncounterSession.clampProgress(0.0), 0.0)
    }

    func test_clampProgress_boundaryOne() {
        XCTAssertEqual(EncounterSession.clampProgress(1.0), 1.0)
    }

    // MARK: - EncounterSession Window Constants

    func test_session_windowIsTenToFifteenMinutes() {
        // The demo (and production) rely on these bounds for the 10–15 min window.
        XCTAssertEqual(EncounterSession.defaultDurationSeconds, 10 * 60)
        XCTAssertEqual(EncounterSession.maxDurationSeconds, 15 * 60)
    }

    // MARK: - Demo Candidate Integrity

    func test_demoCandidate_isVerifiedAndAligned() {
        let maya = DemoProximityProvider.makeDemoCandidate()
        XCTAssertEqual(maya.verificationStatus, .verified)
        XCTAssertEqual(maya.trustLevel, .gold)
        XCTAssertEqual(maya.accountStatus, .active)
        XCTAssertFalse(maya.intentVibes.isEmpty)
        // Shares interests with the Developer Bypass persona so real scoring clears the bar.
        XCTAssertTrue(maya.preferences.interests.contains("coffee"))
    }

    func test_demoPool_secondaryIsLowerCompatibility() {
        let pool = DemoProximityProvider.makeDemoCandidatePool()
        XCTAssertEqual(pool.count, 2)
        // The secondary candidate is intentionally thin so the compatibility
        // threshold filters it out of the surfaced results.
        let secondary = DemoProximityProvider.makeSecondaryDemoCandidate()
        XCTAssertLessThan(secondary.preferences.interests.count,
                          DemoProximityProvider.makeDemoCandidate().preferences.interests.count)
    }

    // MARK: - Gate 1: canEnterCampusCommunity

    func test_canEnterCampusCommunity_requiresSchoolId() {
        var user = TestProfiles.verifiedStudent()
        user.schoolId = nil
        XCTAssertFalse(user.canEnterCampusCommunity)
    }

    func test_canEnterCampusCommunity_rejectsEmptySchoolId() {
        var user = TestProfiles.verifiedStudent()
        user.schoolId = ""
        XCTAssertFalse(user.canEnterCampusCommunity)
    }

    func test_canEnterCampusCommunity_allowsEnrolledAndIncoming() {
        for status in [EnrollmentStatus.enrolled, .incoming] {
            var user = TestProfiles.verifiedStudent()
            user.enrollmentStatus = status
            XCTAssertTrue(user.canEnterCampusCommunity, "\(status) should grant access")
        }
    }

    func test_canEnterCampusCommunity_rejectsAlumniPendingRevokedUnverified() {
        for status in [EnrollmentStatus.alumni, .pending, .revoked, .unverified] {
            var user = TestProfiles.verifiedStudent()
            user.enrollmentStatus = status
            XCTAssertFalse(user.canEnterCampusCommunity, "\(status) must not grant access")
        }
    }

    func test_canEnterCampusCommunity_rejectsNonActiveAccount() {
        for status in [AccountStatus.suspended, .banned, .waitlisted] {
            var user = TestProfiles.verifiedStudent()
            user.accountStatus = status
            XCTAssertFalse(user.canEnterCampusCommunity, "\(status) must not grant access")
        }
    }

    func test_enrollmentStatus_unknownRawValueDecodesToUnverified() throws {
        // Fail-closed: a backend value this build doesn't know must not grant access.
        let decoded = try JSONDecoder().decode(EnrollmentStatus.self,
                                               from: Data("\"transfer_pending\"".utf8))
        XCTAssertEqual(decoded, .unverified)
        XCTAssertFalse(decoded.grantsCommunityAccess)
    }

    // MARK: - Gate 2: canStartQuestMode

    func test_canStartQuestMode_requiresStudentIDVerification() {
        var user = TestProfiles.verifiedStudent()
        user.studentIDStatus = .none
        XCTAssertTrue(user.canEnterCampusCommunity, "school gate alone still passes")
        XCTAssertFalse(user.canStartQuestMode, "but Quest Mode needs the student ID")
    }

    func test_canStartQuestMode_pendingAndRejectedDoNotCount() {
        for status in [StudentIDStatus.pending, .rejected, .none] {
            var user = TestProfiles.verifiedStudent()
            user.studentIDStatus = status
            XCTAssertFalse(user.canStartQuestMode, "\(status) must not open Quest Mode")
        }
    }

    func test_canStartQuestMode_verifiedOrFaceMatchedBothCount() {
        for status in [StudentIDStatus.verified, .faceMatched] {
            var user = TestProfiles.verifiedStudent()
            user.studentIDStatus = status
            XCTAssertTrue(user.canStartQuestMode, "\(status) should open Quest Mode")
        }
    }

    func test_canStartQuestMode_deniedWhenSchoolGateFails() {
        var user = TestProfiles.verifiedStudent()
        user.studentIDStatus = .faceMatched
        user.enrollmentStatus = .alumni
        XCTAssertFalse(user.canStartQuestMode, "an ID cannot substitute for enrollment")
    }

    func test_studentIDStatus_unknownRawValueDecodesToNone() throws {
        let decoded = try JSONDecoder().decode(StudentIDStatus.self,
                                               from: Data("\"manually_approved\"".utf8))
        XCTAssertEqual(decoded, .none)
        XCTAssertFalse(decoded.isIDVerified)
        XCTAssertFalse(decoded.isFaceMatched)
    }

    // MARK: - Gate 3: canUseDatingIntent

    func test_canUseDatingIntent_requiresFaceMatch() {
        var user = TestProfiles.datingEligible()
        user.studentIDStatus = .verified   // ID checked, faces not matched
        XCTAssertTrue(user.canStartQuestMode)
        XCTAssertFalse(user.canUseDatingIntent)
    }

    func test_canUseDatingIntent_requiresVerifiedAdult() {
        var user = TestProfiles.datingEligible()
        user.verifiedAge = 17
        XCTAssertFalse(user.canUseDatingIntent,
                       "an incoming 17-year-old must not reach Dating")
    }

    func test_canUseDatingIntent_ignoresSelfReportedAge() {
        var user = TestProfiles.datingEligible()
        user.age = 22          // self-reported
        user.verifiedAge = nil // never verified
        XCTAssertFalse(user.canUseDatingIntent,
                       "self-reported age must not satisfy the adult gate")
    }

    func test_canUseDatingIntent_grantedWhenAllThreeGatesPass() {
        XCTAssertTrue(TestProfiles.datingEligible().canUseDatingIntent)
    }

    func test_canNameDrop_requiresFaceMatchEvenForStudyIntent() {
        var user = TestProfiles.datingEligible()
        user.activeIntents = [.study]
        XCTAssertTrue(user.canNameDrop, "face match carries NameDrop, not the intent")

        user.studentIDStatus = .verified
        XCTAssertFalse(user.canNameDrop)
    }

    // MARK: - Intent Defaults and Eligibility

    func test_intentDefaults_areHangoutAndStudy_notDating() {
        XCTAssertEqual(Intent.defaults, [.hangout, .study])
        XCTAssertFalse(Intent.defaults.contains(.dating))
    }

    func test_onlyDatingUsesGenderBalanceTools() {
        for intent in Intent.allCases where intent != .dating {
            XCTAssertFalse(intent.usesGenderBalanceTools, "\(intent) must not be gender-throttled")
        }
        XCTAssertTrue(Intent.dating.usesGenderBalanceTools)
    }

    func test_intent_unknownRawValueDecodesToHangout_neverDating() throws {
        let decoded = try JSONDecoder().decode(Intent.self, from: Data("\"romance\"".utf8))
        XCTAssertEqual(decoded, .hangout)
    }

    func test_eligibleIntents_stripsDatingWithoutFaceMatch() {
        var user = TestProfiles.datingEligible()
        user.activeIntents = [.study, .dating]
        XCTAssertEqual(user.eligibleIntents, [.study, .dating])

        user.studentIDStatus = .verified
        XCTAssertEqual(user.eligibleIntents, [.study],
                       "Dating drops out when the face match is missing")
    }

    // MARK: - Intent Lock (toggle exploit)

    func test_lockIntents_isTheOverlapOfEligibleIntents() {
        var a = TestProfiles.datingEligible()
        var b = TestProfiles.datingEligible()
        a.activeIntents = [.hangout, .study, .dating]
        b.activeIntents = [.study, .event, .dating]
        XCTAssertEqual(EncounterSession.lockIntents(a, b), [.study, .dating])
    }

    func test_locksDatingGate_requiresBothSides() {
        var a = TestProfiles.datingEligible()
        var b = TestProfiles.datingEligible()
        a.activeIntents = [.dating]
        b.activeIntents = [.study]
        XCTAssertFalse(EncounterSession.locksDatingGate(a, b),
                       "one-sided Dating must not gender-throttle a Study overlap")
    }

    func test_locksDatingGate_survivesDatingOffDuringCooldown() {
        let now = Date()
        var a = TestProfiles.datingEligible()
        var b = TestProfiles.datingEligible()
        a.activeIntents = [.dating]
        // b switched Dating off 1 hour ago; the server set a 24h cooldown.
        b.activeIntents = [.hangout]
        b.datingCooldownUntil = Timestamp(date: now.addingTimeInterval(23 * 3600))
        XCTAssertTrue(b.isDatingGated(at: now))
        XCTAssertTrue(EncounterSession.locksDatingGate(a, b, at: now),
                      "toggling Dating off must not shed Dating caps during cooldown")
    }

    func test_datingCooldown_expires() {
        let now = Date()
        var user = TestProfiles.datingEligible()
        user.activeIntents = [.hangout]
        user.datingCooldownUntil = Timestamp(date: now.addingTimeInterval(-60))
        XCTAssertFalse(user.isInDatingCooldown(at: now))
        XCTAssertFalse(user.isDatingGated(at: now))
    }

    func test_engagesGenderBalance_onlyForDatingLock() {
        XCTAssertFalse(Intent.engagesGenderBalance([.study, .hangout, .event, .friendship]))
        XCTAssertTrue(Intent.engagesGenderBalance([.study, .dating]))
    }

    // MARK: - Same-School Gate

    func test_campusScope_rejectsDifferentSchool() {
        let ucla = TestProfiles.verifiedStudent(uid: "a", schoolId: "ucla")
        let michigan = TestProfiles.verifiedStudent(uid: "b", schoolId: "michigan")
        XCTAssertFalse(CommunityGate.canShare(viewer: ucla, candidate: michigan,
                                              in: .campus(schoolId: "ucla")))
    }

    func test_campusScope_rejectsVisitorFromAnotherSchoolStandingOnCampus() {
        let ucla = TestProfiles.verifiedStudent(uid: "a", schoolId: "ucla")
        var visitor = TestProfiles.verifiedStudent(uid: "b", schoolId: "michigan")
        visitor.studentIDStatus = .faceMatched
        XCTAssertFalse(CommunityGate.canShare(viewer: ucla, candidate: visitor,
                                              in: .campus(schoolId: "ucla")),
                       "belonging to some campus is not belonging to this one")
    }

    func test_campusScope_allowsSameSchool() {
        let a = TestProfiles.verifiedStudent(uid: "a", schoolId: "ucla")
        let b = TestProfiles.verifiedStudent(uid: "b", schoolId: "ucla")
        XCTAssertTrue(CommunityGate.canShare(viewer: a, candidate: b,
                                             in: .campus(schoolId: "ucla")))
    }

    func test_noneScope_sharesNothing() {
        let a = TestProfiles.verifiedStudent(uid: "a", schoolId: "ucla")
        let b = TestProfiles.verifiedStudent(uid: "b", schoolId: "ucla")
        XCTAssertFalse(CommunityGate.canShare(viewer: a, candidate: b, in: .none),
                       "off campus and outside every live window means no pool")
    }

    func test_springBreakScope_allowsCrossSchoolVerifiedStudents() {
        let ucla = TestProfiles.verifiedStudent(uid: "a", schoolId: "ucla")
        let michigan = TestProfiles.verifiedStudent(uid: "b", schoolId: "michigan")
        let scope = CommunityScope.springBreak(destinationId: "cancun",
                                               displayLabel: "Cancún · Spring Break")
        XCTAssertTrue(CommunityGate.canShare(viewer: ucla, candidate: michigan, in: scope))
    }

    func test_springBreakScope_excludesUnverifiedTourist() {
        let ucla = TestProfiles.verifiedStudent(uid: "a", schoolId: "ucla")
        var tourist = TestProfiles.verifiedStudent(uid: "b", schoolId: "michigan")
        tourist.studentIDStatus = .none      // no student ID
        let scope = CommunityScope.springBreak(destinationId: "cancun",
                                               displayLabel: "Cancún · Spring Break")
        XCTAssertFalse(CommunityGate.canShare(viewer: ucla, candidate: tourist, in: scope))
    }

    func test_springBreakScope_excludesLocalWithNoSchool() {
        let ucla = TestProfiles.verifiedStudent(uid: "a", schoolId: "ucla")
        var local = TestProfiles.verifiedStudent(uid: "b", schoolId: "michigan")
        local.schoolId = nil
        local.enrollmentStatus = .unverified
        let scope = CommunityScope.springBreak(destinationId: "cancun",
                                               displayLabel: "Cancún · Spring Break")
        XCTAssertFalse(CommunityGate.canShare(viewer: ucla, candidate: local, in: scope))
    }

    func test_canShareForDating_deniedWhenPartnerLacksFaceMatch() {
        let a = TestProfiles.datingEligible(uid: "a", schoolId: "ucla")
        var b = TestProfiles.datingEligible(uid: "b", schoolId: "ucla")
        b.studentIDStatus = .verified
        XCTAssertTrue(CommunityGate.canShare(viewer: a, candidate: b,
                                             in: .campus(schoolId: "ucla")))
        XCTAssertFalse(CommunityGate.canShareForDating(viewer: a, candidate: b,
                                                       in: .campus(schoolId: "ucla")))
    }

    func test_canShare_rejectsSelf() {
        let a = TestProfiles.verifiedStudent(uid: "a", schoolId: "ucla")
        XCTAssertFalse(CommunityGate.canShare(viewer: a, candidate: a,
                                              in: .campus(schoolId: "ucla")))
    }

    // MARK: - Spring Break Window

    func test_springBreakDestination_inertOutsideWindow() {
        let now = Date()
        let dest = TestProfiles.destination(
            start: now.addingTimeInterval(86_400),
            end: now.addingTimeInterval(2 * 86_400)
        )
        XCTAssertFalse(dest.isLive(at: now), "a fence before its window is inert")
    }

    func test_springBreakDestination_inertWhenDeactivated() {
        let now = Date()
        var dest = TestProfiles.destination(start: now.addingTimeInterval(-3600),
                                            end: now.addingTimeInterval(3600))
        XCTAssertTrue(dest.isLive(at: now))
        dest.isActive = false
        XCTAssertFalse(dest.isLive(at: now), "the kill switch overrides the window")
    }

    func test_springBreakDestination_inertOnInvertedWindow() {
        let now = Date()
        let dest = TestProfiles.destination(start: now.addingTimeInterval(3600),
                                            end: now.addingTimeInterval(-3600))
        XCTAssertFalse(dest.isLive(at: now), "a malformed window must fail closed")
    }

    func test_communityScope_noneBlocksQuestMode() {
        XCTAssertFalse(CommunityScope.none.allowsQuestMode)
        XCTAssertTrue(CommunityScope.campus(schoolId: "ucla").allowsQuestMode)
        XCTAssertFalse(CommunityScope.campus(schoolId: "ucla").isSpringBreak)
        XCTAssertTrue(CommunityScope.springBreak(destinationId: "cancun",
                                                 displayLabel: "Cancún · Spring Break").isSpringBreak)
    }
}

// MARK: - Test Fixtures

/// Profiles at each gate boundary. Every field these set is one the server owns
/// in production — the fixtures exist to test the gates, not to model a client
/// that could write them.
@MainActor
enum TestProfiles {

    /// School gate passed + student ID verified. Quest Mode yes, Dating no.
    static func verifiedStudent(uid: String = "test-uid",
                                schoolId: String = "ucla") -> UserProfile {
        var profile = base(uid: uid)
        profile.schoolId = schoolId
        profile.schoolDisplayName = schoolId.uppercased()
        profile.enrollmentStatus = .enrolled
        profile.studentIDStatus = .verified
        profile.accountStatus = .active
        return profile
    }

    /// All three gates passed: school, student ID, ID ↔ liveness face match,
    /// verified adult.
    static func datingEligible(uid: String = "test-uid",
                               schoolId: String = "ucla") -> UserProfile {
        var profile = verifiedStudent(uid: uid, schoolId: schoolId)
        profile.studentIDStatus = .faceMatched
        profile.verifiedAge = 20
        profile.activeIntents = [.hangout, .study, .dating]
        return profile
    }

    static func destination(id: String = "cancun",
                            start: Date,
                            end: Date) -> SpringBreakDestination {
        SpringBreakDestination(
            id: id,
            displayLabel: "Cancún · Spring Break",
            centerGeohash: "d5fs2yn",
            radiusMeters: 4_000,
            windowStart: Timestamp(date: start),
            windowEnd: Timestamp(date: end),
            isActive: true,
            duskLocalHour: 20,
            duskRadiusMiles: 0.1
        )
    }

    private static func base(uid: String) -> UserProfile {
        UserProfile(
            uid: uid,
            displayName: "Test",
            age: 20,
            bio: "",
            photoURLs: [],
            selfDescriptors: [],
            verificationStatus: .verified,
            trustLevel: .silver,
            preferences: MatchPreferences(
                ageRange: 18...30,
                maxDistanceMiles: 0.25,
                genderPreferences: [],
                interests: [],
                dealbreakers: [],
                compatibilityThreshold: 0.80
            ),
            privacySettings: PrivacySettings(
                questModeEnabled: true,
                visibilityRadius: 0.25,
                autoPauseZones: [],
                alertLimit: 20,
                locationSharingMode: .anonymized,
                showInCommunityEvents: true
            ),
            gamification: GamificationProfile(),
            createdAt: Date(),
            lastActive: Date()
        )
    }
}
