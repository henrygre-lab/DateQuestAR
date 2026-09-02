// MARK: - SECURITY CHECKLIST COMPLIANCE (see docs/SECURITY_CHECKLIST.md)
// [x] No hardcoded secrets, API keys, or tokens
// [x] DEBUG-only: entire type is compiled out of release builds (#if DEBUG)
// [x] No Firestore / network access — purely in-memory simulation for portfolio demos
// [x] No real location or UWB hardware touched — synthetic distance values only
// [x] Mock candidate contains no real PII — fabricated demo persona
// [x] Demo candidates carry the same demo schoolId as the bypass persona, and are
//     student-ID verified, so the walkthrough runs the real community gate rather
//     than modelling a cross-campus pairing production would refuse
// [x] Production proximity path (ProximityService + MatchManager.handleProximityEvent)
//     is untouched; this provider only feeds MatchManager's explicit demo entry points

#if DEBUG
import Foundation
import Combine

// MARK: - DemoProximityProvider

/// Simulates a compatible user physically approaching from 0.25 mi to arm's length.
/// Used only by `MatchManager.startDemoEncounter` when running via Developer Bypass,
/// so the full proximity → reveal → icebreaker → NameDrop flow can be demoed on a
/// device (or Simulator) with no location/UWB hardware and no backend.
@MainActor
final class DemoProximityProvider: ObservableObject {

    /// The community every demo persona belongs to. Shared by the bypass user
    /// and both candidates so `CommunityGate.canShare` passes honestly.
    static let demoSchoolId = "demo_school"
    static let demoSchoolName = "Demo University"

    /// Current simulated distance to the demo match, in miles.
    @Published private(set) var distanceMiles: Double = 0.25

    private var timer: Timer?
    private var onUpdate: ((Double) -> Void)?

    /// Distance the approach starts at (edge of Quest Mode range).
    private let startDistance: Double = 0.25
    /// Distance the approach settles at (essentially face-to-face).
    private let arrivalDistance: Double = 0.02
    /// How much closer the match gets on each tick.
    private let step: Double = 0.023
    /// Seconds between ticks — tuned so the walk-up reads as deliberate, ~3s total.
    private let interval: TimeInterval = 0.32

    // MARK: - Approach Simulation

    /// Begins the simulated walk-up. `onUpdate` fires on the main actor for every
    /// distance change (including the initial value) until arrival, then stops.
    func startApproach(onUpdate: @escaping (Double) -> Void) {
        stop()
        self.onUpdate = onUpdate
        distanceMiles = startDistance
        onUpdate(distanceMiles)

        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    /// Immediately jumps to arrival distance — used if the reviewer skips ahead.
    func snapToArrival() {
        distanceMiles = arrivalDistance
        onUpdate?(distanceMiles)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let next = max(arrivalDistance, distanceMiles - step)
        distanceMiles = next
        onUpdate?(next)
        if next <= arrivalDistance {
            stop()
        }
    }

    // MARK: - Mock Candidates

    /// The nearby demo pool. `MatchManager` runs each candidate through the real
    /// scoring, vibe filter, safety gate, and BalanceEnforcer/AlertCapManager
    /// checks — so which candidate (if any) surfaces is decided by those systems,
    /// not hard-coded. The secondary candidate is a genuine low-compatibility
    /// nearby user that the compatibility threshold is expected to filter out.
    static func makeDemoCandidatePool() -> [UserProfile] {
        [makeDemoCandidate(), makeSecondaryDemoCandidate()]
    }

    /// A verified but low-compatibility nearby user. Included to prove the
    /// compatibility threshold genuinely filters the pool: shared interests and
    /// relationship goals are thin, so `computeCompatibilityScore` lands below
    /// the 0.80 threshold and this profile is not surfaced.
    static func makeSecondaryDemoCandidate() -> UserProfile {
        UserProfile(
            uid: "demo_match_jordan",
            displayName: "Jordan Blake",
            age: 31,
            bio: "New in town, mostly here for the coffee.",
            photoURLs: [],
            selfDescriptors: ["easygoing"],
            verificationStatus: .verified,
            trustLevel: .silver,
            verifiedAge: 31,
            verificationCompletedAt: Date(),
            preferences: MatchPreferences(
                ageRange: 28...40,
                maxDistanceMiles: 0.25,
                genderPreferences: [],
                interests: ["coffee"],
                dealbreakers: [],
                compatibilityThreshold: 0.80
            ),
            privacySettings: PrivacySettings(
                questModeEnabled: true,
                visibilityRadius: 0.25,
                autoPauseZones: [],
                alertLimit: 40,
                locationSharingMode: .anonymized,
                showInCommunityEvents: true
            ),
            gamification: GamificationProfile(),
            isProfileComplete: true,
            trustScore: 0.6,
            createdAt: Date(),
            lastActive: Date(),
            // Same demo campus as the bypass persona: the walkthrough must not be
            // able to show a cross-campus pairing production would refuse.
            schoolId: DemoProximityProvider.demoSchoolId,
            schoolDisplayName: DemoProximityProvider.demoSchoolName,
            enrollmentStatus: .enrolled,
            studentIDStatus: .verified,
            activeIntents: [.hangout, .study],
            gender: .male,
            accountStatus: .active,
            intentVibes: ["genuine", "spontaneous"],
            socialContextPreference: true
        )
    }

    /// Builds a fully-formed, verified demo match designed to score highly against
    /// the Developer Bypass profile so the real scoring + safety gates pass honestly.
    /// Interests, relationship type, age window, and intent vibes are aligned with
    /// the bypass persona defined in `OnboardingView`.
    static func makeDemoCandidate() -> UserProfile {
        UserProfile(
            uid: "demo_match_maya",
            displayName: "Maya Chen",
            age: 26,
            bio: "Design lead who over-orders at coffee shops and reorganizes her bookshelf by color. Ask me about my last spontaneous trip.",
            photoURLs: [],
            selfDescriptors: ["adventurous", "creative", "warm"],
            verificationStatus: .verified,
            trustLevel: .gold,
            verifiedAge: 26,
            verificationCompletedAt: Date(),
            preferences: MatchPreferences(
                ageRange: 22...34,
                maxDistanceMiles: 0.25,
                genderPreferences: [],
                interests: ["coding", "coffee", "hiking"],
                dealbreakers: [],
                compatibilityThreshold: 0.80
            ),
            privacySettings: PrivacySettings(
                questModeEnabled: true,
                visibilityRadius: 0.25,
                autoPauseZones: [],
                alertLimit: 10,
                locationSharingMode: .anonymized,
                showInCommunityEvents: true
            ),
            gamification: GamificationProfile(),
            isProfileComplete: true,
            trustScore: 0.88,
            createdAt: Date(),
            lastActive: Date(),
            schoolId: DemoProximityProvider.demoSchoolId,
            schoolDisplayName: DemoProximityProvider.demoSchoolName,
            enrollmentStatus: .enrolled,
            // Face-matched so the walkthrough can exercise both the non-Dating
            // and the Dating branch of the intent lock.
            studentIDStatus: .faceMatched,
            activeIntents: [.hangout, .study],
            gender: .female,
            accountStatus: .active,
            intentVibes: ["adventurous", "genuine", "spontaneous"],
            socialContextPreference: true
        )
    }
}
#endif
