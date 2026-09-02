// MARK: - SECURITY CHECKLIST COMPLIANCE (see docs/SECURITY_CHECKLIST.md)
// [x] No hardcoded secrets, API keys, or tokens
// [x] Carries schoolId so a proximity event from outside the viewer's community
//     can be dropped at the handler rather than deep in the match path
// [x] No raw coordinates — distance only, never a coordinate or geohash
// [x] No photo URLs, student ID data, phone number or school email
// [x] In-memory transport type only; never written to Firestore

import Foundation

// MARK: - Proximity Event

struct ProximityEvent {
    var matchID: String
    var partnerUID: String

    /// School of the partner who triggered the event. `MatchManager` drops any
    /// event whose school does not match the current `CommunityScope` before
    /// doing any further work — the same-school gate runs at the edge.
    var partnerSchoolId: String?

    var distanceMiles: Double
    var hapticIntensity: Float          // 0.0–1.0, ramps with closeness
    var shouldRevealPhotos: Bool        // true when < 0.1 miles
    var timestamp: Date
}
