import Foundation

// MARK: - AppError
// Cross-cutting error type surfaced by services (Firestore, location, verification).

enum AppError: LocalizedError {
    case missingUID
    case locationUnavailable
    case verificationFailed
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .missingUID:             return "User ID is missing."
        case .locationUnavailable:    return "Location services are unavailable."
        case .verificationFailed:     return "Verification could not be completed."
        case .networkError(let msg):  return "Network error: \(msg)"
        }
    }
}
