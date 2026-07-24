import Foundation
import FirebaseFirestore

// MARK: - Waitlist Entry

struct WaitlistEntry: Codable, Identifiable {
    @DocumentID var id: String?
    var uid: String
    var gender: String
    var status: String                      // "queued", "activating", "activated"
    var entryTime: Timestamp
    var estimatedActivation: Timestamp?
    var activatedAt: Timestamp?
}

// MARK: - Gender Stats

struct GenderStats: Codable {
    var totalActive: Int
    var maleCount: Int
    var femaleCount: Int
    var nonBinaryCount: Int
    var preferNotToSayCount: Int
    var malePct: Double
    var femalePct: Double
    var lastUpdated: Timestamp
    var femaleAlertCap: Int?
    var maleAlertCap: Int?
    var womenFirstQueuingEnabled: Bool?
}
