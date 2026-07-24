import Foundation

// MARK: - Gamification (Simplified XP System)
// [x] No secrets or tokens — pure value type
// [x] Level is derived from totalXP via deterministic formula — no client-editable level field
// [x] lastLoginDate uses client Date; streak logic is advisory (server can re-derive)
// [x] Minimal data stored — badges, questsCompleted, totalConnections removed

struct GamificationProfile: Codable {
    var totalXP: Int = 0
    var level: Int = 1                      // Cached; recalculate via computedLevel
    var lastLoginDate: Date = Date()
    var currentStreakDays: Int = 0

    /// Derives level from totalXP. Formula: 1 + floor(sqrt(totalXP / 80)).
    /// Level 1 at 0 XP, level 2 at 80 XP, level 5 at 1280 XP, etc.
    var computedLevel: Int {
        return 1 + Int(sqrt(Double(totalXP) / 80.0))
    }

    /// Syncs the cached `level` field to the current `computedLevel`.
    /// Call before writing to Firestore so the stored value stays consistent.
    mutating func recacheLevel() {
        level = computedLevel
    }
}
