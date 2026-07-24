import XCTest
@testable import Serendipity

// Core model and value-type tests. These do not require a live Firebase connection.

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

    @MainActor
    func test_demoCandidate_isVerifiedAndAligned() {
        let maya = DemoProximityProvider.makeDemoCandidate()
        XCTAssertEqual(maya.verificationStatus, .verified)
        XCTAssertEqual(maya.trustLevel, .gold)
        XCTAssertEqual(maya.accountStatus, .active)
        XCTAssertFalse(maya.intentVibes.isEmpty)
        // Shares interests with the Developer Bypass persona so real scoring clears the bar.
        XCTAssertTrue(maya.preferences.interests.contains("coffee"))
    }

    @MainActor
    func test_demoPool_secondaryIsLowerCompatibility() {
        let pool = DemoProximityProvider.makeDemoCandidatePool()
        XCTAssertEqual(pool.count, 2)
        // The secondary candidate is intentionally thin so the compatibility
        // threshold filters it out of the surfaced results.
        let secondary = DemoProximityProvider.makeSecondaryDemoCandidate()
        XCTAssertLessThan(secondary.preferences.interests.count,
                          DemoProximityProvider.makeDemoCandidate().preferences.interests.count)
    }
}
