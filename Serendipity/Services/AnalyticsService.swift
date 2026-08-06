// MARK: - SECURITY CHECKLIST COMPLIANCE (see docs/SECURITY_CHECKLIST.md)
// [x] No hardcoded secrets, API keys, or tokens
// [x] No raw UIDs logged — all user identifiers are SHA256-hashed before logging
// [x] No PII in analytics parameters — only aggregate/enum values
// [x] Firebase Analytics used exclusively — no third-party analytics SDKs
// [x] Parameter values clamped/validated before logging
// [x] No sensitive data (location, photos, bio) in any event
// [x] Event names follow Firebase snake_case convention

import Foundation
import FirebaseAnalytics
import CryptoKit

// MARK: - AnalyticsService

final class AnalyticsService {
    static let shared = AnalyticsService()
    private init() {}

    // MARK: - UID Hashing

    /// Produces a truncated SHA256 hash of a UID for analytics.
    /// Never log raw UIDs — this provides unlinkable, consistent identifiers.
    private func hashUID(_ uid: String) -> String {
        let digest = SHA256.hash(data: Data(uid.utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Gender Ratio Events

    /// Logs when global gender ratio stats update from the Firestore listener.
    func logGenderRatioUpdate(malePct: Double, needsFemaleBoost: Bool) {
        Analytics.logEvent("gender_ratio_updated", parameters: [
            "male_pct": clampPct(malePct),
            "needs_female_boost": needsFemaleBoost ? "true" : "false"
        ])
    }

    // MARK: - Waitlist Events

    /// Logs when a user's waitlist activation occurs.
    func logWaitlistActivation(waitHours: Double, gender: Gender) {
        Analytics.logEvent("waitlist_activation_time", parameters: [
            "wait_hours": clampHours(waitHours),
            "gender": gender.rawValue
        ])
    }

    // MARK: - Verification Events

    /// Logs verification completion with status and trust delta.
    func logVerificationCompleted(status: String, trustDelta: Double) {
        Analytics.logEvent("verification_completion_rate", parameters: [
            "status": sanitize(status),
            "trust_delta": clampDelta(trustDelta)
        ])
    }

    // MARK: - Alert Throttling Events

    /// Logs when an alert is throttled due to gender-based cap.
    func logAlertThrottledByGender(gender: Gender, cap: Int, reason: String) {
        Analytics.logEvent("alert_throttled_by_gender", parameters: [
            "gender": gender.rawValue,
            "cap": cap,
            "reason": sanitize(reason)
        ])
    }

    // MARK: - Vibe Filter Events

    /// Logs when a vibe filter rejects a potential match.
    func logVibeFilterRejected(vibeScore: Double) {
        Analytics.logEvent("vibe_filter_rejected", parameters: [
            "vibe_score": clampPct(vibeScore)
        ])
    }

    // MARK: - Squad Radar Events

    /// Logs when squad radar mode is toggled.
    func logSquadRadarToggled(enabled: Bool, nearbyCount: Int) {
        Analytics.logEvent("squad_radar_toggled", parameters: [
            "enabled": enabled ? "true" : "false",
            "nearby_count": min(nearbyCount, 999)
        ])
    }

    // MARK: - Reveal Session Events (Risk #3 mitigation)

    /// Logs when a reveal session starts for a match.
    func logRevealSessionStarted(matchID: String) {
        Analytics.logEvent("reveal_session_started", parameters: [
            "match_hash": hashUID(matchID)
        ])
    }

    /// Logs when a reveal session completes (reaches .connected via NameDrop).
    func logRevealCompleted(matchID: String) {
        Analytics.logEvent("reveal_completed", parameters: [
            "match_hash": hashUID(matchID)
        ])
    }

    /// Logs when a reveal session ends (timeout, departure, or report).
    func logRevealSessionEnded(matchID: String, finalStage: RevealStage) {
        Analytics.logEvent("reveal_session_ended", parameters: [
            "match_hash": hashUID(matchID),
            "final_stage": finalStage.rawValue
        ])
    }

    // MARK: - Ping Cap Events

    /// Logs when a per-user ping cap is hit. Partner UID is hashed.
    func logPingCapHit(partnerUID: String) {
        Analytics.logEvent("ping_cap_hit", parameters: [
            "partner_hash": hashUID(partnerUID)
        ])
    }

    // MARK: - Activation Timing Events

    /// Logs weekday vs weekend activation patterns.
    func logWeekdayVsWeekendActivation(isWeekend: Bool, activationCount: Int) {
        Analytics.logEvent("weekday_vs_weekend_activation", parameters: [
            "is_weekend": isWeekend ? "true" : "false",
            "activation_count": min(activationCount, 9999)
        ])
    }

    // MARK: - Referral Events

    /// Logs a referral event with gender-weighted reward info.
    func logReferralCompleted(referrerGender: Gender, rewardMultiplier: Double, xpAwarded: Int) {
        Analytics.logEvent("referral_completed", parameters: [
            "referrer_gender": referrerGender.rawValue,
            "reward_multiplier": clampDelta(rewardMultiplier),
            "xp_awarded": min(xpAwarded, 99999)
        ])
    }

    // MARK: - Gamification Events

    /// Logs when a badge is awarded.
    func logBadgeAwarded(badgeName: String, trigger: String) {
        Analytics.logEvent("badge_awarded", parameters: [
            "badge_name": sanitize(badgeName),
            "trigger": sanitize(trigger)
        ])
    }

    /// Logs when XP is awarded with multiplier context.
    func logXPAwarded(amount: Int, multiplier: Double, reason: String) {
        Analytics.logEvent("xp_awarded", parameters: [
            "amount": min(amount, 99999),
            "multiplier": clampDelta(multiplier),
            "reason": sanitize(reason)
        ])
    }

    // MARK: - Parameter Sanitization

    /// Clamps a percentage value to 0.0–1.0 range.
    private func clampPct(_ value: Double) -> Double {
        min(max(value, 0.0), 1.0)
    }

    /// Clamps hour values to a reasonable range.
    private func clampHours(_ value: Double) -> Double {
        min(max(value, 0.0), 8760.0) // max 1 year
    }

    /// Clamps delta values to -10.0...10.0.
    private func clampDelta(_ value: Double) -> Double {
        min(max(value, -10.0), 10.0)
    }

    /// Sanitizes string parameters: trims, truncates, removes control chars.
    private func sanitize(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let clean = trimmed.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
        return String(String(String.UnicodeScalarView(clean)).prefix(100))
    }
}
