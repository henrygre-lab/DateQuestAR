import Foundation

// MARK: - Proximity Event

struct ProximityEvent {
    var matchID: String
    var partnerUID: String
    var distanceMiles: Double
    var hapticIntensity: Float          // 0.0–1.0, ramps with closeness
    var shouldRevealPhotos: Bool        // true when < 0.1 miles
    var timestamp: Date
}
