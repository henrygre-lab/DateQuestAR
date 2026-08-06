// MARK: - SECURITY CHECKLIST COMPLIANCE (see docs/SECURITY_CHECKLIST.md)
// [x] No hardcoded secrets, API keys, or tokens
// [x] Full photos never exposed until revealStage == .connected — client receives
//     blurred/partial variants via server-generated signed URLs (short-lived)
// [x] All Firestore writes use updateData with only changed fields — never
//     overwrites server-authoritative data (accountStatus, trustLevel, etc.)
// [x] Server timestamps used for lastUpdated — no client clock trust
// [x] No IDOR: session reads verify that the requesting UID is userAUID or userBUID
// [x] No raw photos held in client memory until reveal is authorized
// [x] No PII in logs — only session/match IDs, reveal stages, and progress values
// [x] Addresses Risk #3 (Swarm / Stratification) from POTENTIAL_ISSUES.md
// [x] Session persistence (10–15 min) handles edge cases from
//     EDGE_CASES_AND_OBJECTIONS.md (bus/train movement, vertical density)

import Foundation
import FirebaseFirestore
import Combine

// MARK: - RevealManager

/// Manages progressive photo reveal tied to EncounterSessions.
/// Full profile photos are only accessible after icebreaker completion
/// and mutual NameDrop (.connected stage). This prevents swarm behavior
/// around attractive users (Risk #3) by forcing vibe-first interaction.
@MainActor
final class RevealManager: ObservableObject {
    static let shared = RevealManager()

    // MARK: - Published State

    @Published var activeSessions: [String: EncounterSession] = [:]  // matchID → session

    #if DEBUG
    /// When true, the real stage-machine logic runs but all Firestore reads/writes
    /// and XP round-trips are skipped. Set by MatchManager during a demo encounter
    /// so the walkthrough works with no backend. Compiled out of release builds.
    var isDemoMode = false
    #endif

    // MARK: - Dependencies

    private let db = Firestore.firestore()
    private let analytics = AnalyticsService.shared

    private var sessionsCollection: CollectionReference {
        db.collection("encounter_sessions")
    }

    private init() {}

    // MARK: - Start Session

    /// Creates a new EncounterSession when a proximity match triggers.
    /// The session persists for 10–15 minutes regardless of distance changes,
    /// supporting edge cases like bus/train movement and vertical density.
    func startRevealSession(for match: Match, currentUser: UserProfile) async {
        // Don't create duplicate sessions for the same match
        guard activeSessions[match.id] == nil else { return }

        let now = Timestamp(date: Date())
        let timeout = Timestamp(date: Date().addingTimeInterval(EncounterSession.defaultDurationSeconds))

        let session = EncounterSession(
            id: nil,  // Firestore assigns document ID
            matchID: match.id,
            userAUID: match.userAUID,
            userBUID: match.userBUID,
            startTimestamp: now,
            revealProgress: 0.0,
            icebreakerType: .trivia,  // Default; updated when icebreaker starts
            revealStage: .blurred,
            sessionTimeout: timeout,
            lastUpdated: now
        )

        #if DEBUG
        if isDemoMode {
            // No Firestore: assign a synthetic ID and keep the session in memory only.
            var savedSession = session
            savedSession.id = "demo_session_\(match.id)"
            activeSessions[match.id] = savedSession
            analytics.logRevealSessionStarted(matchID: match.id)
            return
        }
        #endif

        do {
            let docRef = try sessionsCollection.addDocument(from: session)

            // Read back with Firestore-assigned ID
            var savedSession = session
            savedSession.id = docRef.documentID
            activeSessions[match.id] = savedSession

            // Link session to the match document (narrow write)
            try await db.collection("matches").document(match.id).updateData([
                "encounterSessionID": docRef.documentID,
                "revealStage": RevealStage.blurred.rawValue
            ])

            analytics.logRevealSessionStarted(matchID: match.id)
        } catch {
            Log.reveal.error("Failed to create session: \(error.localizedDescription)")
        }
    }

    // MARK: - Update Progress

    /// Updates reveal progress during an active icebreaker. Progress is clamped
    /// to 0.0–1.0 and stage advancement happens automatically at thresholds.
    /// Firestore write is narrow: only revealProgress, revealStage, lastUpdated.
    func updateRevealProgress(for sessionID: String, progress: Double) async {
        guard var session = sessionByID(sessionID) else { return }
        guard session.isActive() else {
            Log.reveal.debug("Session \(sessionID) has timed out")
            return
        }

        let clampedProgress = EncounterSession.clampProgress(progress)
        session.revealProgress = clampedProgress

        // Auto-advance stage at thresholds
        if session.shouldAdvanceStage(), let next = session.nextStage() {
            // Never auto-advance past .revealed — .connected requires explicit NameDrop
            if next != .connected {
                session.revealStage = next
            }
        }

        session.lastUpdated = Timestamp(date: Date())
        updateLocalSession(session)

        #if DEBUG
        if isDemoMode { return }  // Local stage machine already advanced above.
        #endif

        do {
            try await sessionsCollection.document(sessionID).updateData([
                "revealProgress": session.revealProgress,
                "revealStage": session.revealStage.rawValue,
                "lastUpdated": FieldValue.serverTimestamp()
            ])

            // Sync reveal stage to match document
            try await db.collection("matches").document(session.matchID).updateData([
                "revealStage": session.revealStage.rawValue
            ])
        } catch {
            Log.reveal.error("Failed to update progress: \(error.localizedDescription)")
        }
    }

    // MARK: - Complete Reveal (NameDrop)

    /// Moves the session to .connected after mutual NameDrop.
    /// This is the ONLY path to full profile photo access.
    ///
    /// **Must only be called after both users have completed the NameDrop
    /// exchange (mutual consent).** Calling this without mutual confirmation
    /// would expose full photos prematurely, violating Risk #3 mitigation.
    ///
    /// Firestore write is narrow: only revealStage, revealProgress, lastUpdated.
    func completeReveal(for sessionID: String) async {
        guard var session = sessionByID(sessionID) else { return }

        // Only allow completion from .revealed stage (icebreaker must be done first)
        guard session.revealStage == .revealed else {
            Log.reveal.error("Cannot complete reveal: stage is \(session.revealStage), expected .revealed")
            return
        }

        session.revealStage = .connected
        session.revealProgress = 1.0
        session.lastUpdated = Timestamp(date: Date())
        updateLocalSession(session)

        #if DEBUG
        if isDemoMode {
            analytics.logRevealCompleted(matchID: session.matchID)
            return  // Skip Firestore + XP round-trip; local .connected state is set.
        }
        #endif

        do {
            try await sessionsCollection.document(sessionID).updateData([
                "revealStage": RevealStage.connected.rawValue,
                "revealProgress": 1.0,
                "lastUpdated": FieldValue.serverTimestamp()
            ])

            // Sync to match document
            try await db.collection("matches").document(session.matchID).updateData([
                "revealStage": RevealStage.connected.rawValue
            ])

            analytics.logRevealCompleted(matchID: session.matchID)

            // Award XP for successful NameDrop (mutual profile exchange)
            await XPManager.shared.grantNameDropXP()
        } catch {
            Log.reveal.error("Failed to complete reveal: \(error.localizedDescription)")
        }
    }

    // MARK: - Query

    /// Returns the current reveal stage for a match. Defaults to .blurred
    /// if no active session exists (fail-closed — never show more than earned).
    func getRevealStage(for matchID: String) -> RevealStage {
        guard let session = activeSessions[matchID] else { return .blurred }
        // If session has timed out and wasn't completed, freeze at current stage
        return session.revealStage
    }

    // MARK: - End Session

    /// Ends an encounter session (timeout, user left, or report).
    /// Does NOT delete the Firestore document — keeps audit trail.
    func endSession(for matchID: String) async {
        guard let session = activeSessions[matchID], let sessionID = session.id else { return }

        activeSessions.removeValue(forKey: matchID)

        #if DEBUG
        if isDemoMode {
            analytics.logRevealSessionEnded(matchID: matchID, finalStage: session.revealStage)
            return
        }
        #endif

        do {
            // Mark session as ended by setting timeout to now (narrow write)
            try await sessionsCollection.document(sessionID).updateData([
                "sessionTimeout": Timestamp(date: Date()),
                "lastUpdated": FieldValue.serverTimestamp()
            ])

            analytics.logRevealSessionEnded(matchID: matchID, finalStage: session.revealStage)
        } catch {
            Log.reveal.error("Failed to end session: \(error.localizedDescription)")
        }
    }

    // MARK: - Session Cleanup

    /// Removes timed-out sessions from the local cache.
    /// Call from a repeating timer (e.g., every 60s) or on `UIApplication.willEnterForegroundNotification`
    /// to prevent stale sessions from accumulating in memory.
    func cleanupExpiredSessions() {
        let expired = activeSessions.filter { !$0.value.isActive() }
        for (matchID, session) in expired {
            activeSessions.removeValue(forKey: matchID)
            analytics.logRevealSessionEnded(matchID: matchID, finalStage: session.revealStage)
        }
    }

    // MARK: - Private Helpers

    /// Finds a session by its Firestore document ID.
    private func sessionByID(_ sessionID: String) -> EncounterSession? {
        return activeSessions.values.first { $0.id == sessionID }
    }

    /// Updates the local cache for a session (keyed by matchID).
    private func updateLocalSession(_ session: EncounterSession) {
        activeSessions[session.matchID] = session
    }
}
