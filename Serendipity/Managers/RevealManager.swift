// MARK: - SECURITY CHECKLIST COMPLIANCE (see docs/SECURITY_CHECKLIST.md)
// [x] No hardcoded secrets, API keys, or tokens
// [x] Community context and the intent lock are copied from the match, never
//     re-derived from live user state — a mid-session intent change cannot move
//     a session's gender-balance posture
// [x] NameDrop requires the student ID <-> liveness face match (canNameDrop);
//     firestore.rules rejects a 'connected' write without the faceMatched claim
// [x] Sessions are opened and closed by Cloud Functions, never written here.
//     firestore.rules denies client creates on encounter_sessions, so the
//     two-encounter cap cannot be bypassed by writing a session document.
// [x] The slot count comes from a Firestore listener over the user's own
//     sessions, not from the local activeSessions dictionary. A local array is
//     exactly what a swarming client would edit; this one is a read of the same
//     documents the server counts.
// [x] The client count is a courtesy filter for UI. openEncounterSession runs the
//     same count inside a transaction with a fresh clock, and that decides.
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
import FirebaseFunctions
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

    /// How many encounter slots the signed-in user is currently holding.
    ///
    /// Read from Firestore rather than derived from `activeSessions`: the local
    /// dictionary only knows about sessions this device opened, and a slot can be
    /// taken by a session the *other* person opened.
    @Published private(set) var activeSlotCount: Int = 0

    /// True when there is no room for another encounter. Drives the one line on
    /// Home and Radar; the server enforces the same thing.
    @Published private(set) var isAtSessionCap: Bool = false

    #if DEBUG
    /// When true, the real stage-machine logic runs but all Firestore reads/writes
    /// and XP round-trips are skipped. Set by MatchManager during a demo encounter
    /// so the walkthrough works with no backend. Compiled out of release builds.
    var isDemoMode = false
    #endif

    // MARK: - Dependencies

    private let db = Firestore.firestore()
    private let functions = Functions.functions()
    private let analytics = AnalyticsService.shared
    private var slotListener: ListenerRegistration?

    private var sessionsCollection: CollectionReference {
        db.collection("encounter_sessions")
    }

    private init() {}

    deinit {
        slotListener?.remove()
    }

    // MARK: - Slot Accounting

    /// Starts watching the signed-in user's encounter slots.
    ///
    /// The query deliberately omits the timeout filter. A Firestore listener
    /// pins its bounds when the query is created, so `sessionTimeout > now` would
    /// freeze `now` at subscription time and keep counting sessions long after
    /// they expired. The window check happens per snapshot instead, against the
    /// current clock — and the backend re-checks it with its own.
    func startObservingSlots(uid: String) {
        slotListener?.remove()
        guard !uid.isEmpty else { return }

        slotListener = sessionsCollection
            .whereField("participantUIDs", arrayContains: uid)
            .whereField("slotState", isEqualTo: EncounterSession.SlotState.active.rawValue)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                if let error {
                    Log.reveal.error("Slot listener error: \(error.localizedDescription)")
                    return
                }
                let sessions = (snapshot?.documents ?? []).compactMap {
                    try? $0.data(as: EncounterSession.self)
                }
                Task { @MainActor in self.recomputeSlots(for: uid, from: sessions) }
            }
    }

    func stopObservingSlots() {
        slotListener?.remove()
        slotListener = nil
        activeSlotCount = 0
        isAtSessionCap = false
    }

    @MainActor
    private func recomputeSlots(for uid: String, from sessions: [EncounterSession]) {
        activeSlotCount = EncounterSession.activeSlotCount(for: uid, in: sessions)
        isAtSessionCap = activeSlotCount >= EncounterSession.maxActiveSessionsPerUser
    }

    // MARK: - Start Session

    /// Opens an EncounterSession for a match, if both people have a free slot.
    ///
    /// The session document is created by `openEncounterSession`, not here.
    /// `firestore.rules` denies client creates on `encounter_sessions`, because
    /// the two-encounter cap is a count across documents and rules cannot count —
    /// so the count and the write have to share a transaction, and that
    /// transaction lives on the server.
    ///
    /// Returns the outcome so the caller can tell "you are full" (worth saying)
    /// from "unavailable" (not worth saying, and not the user's business).
    @discardableResult
    func startRevealSession(for match: Match, currentUser: UserProfile) async -> SessionOpenResult {
        // Don't create duplicate sessions for the same match
        guard activeSessions[match.id] == nil else { return .alreadyOpen }

        #if DEBUG
        if isDemoMode {
            // No Firestore and no Cloud Function: build the session locally so
            // the walkthrough runs with no backend. The slot cap still applies —
            // the demo reads the same published count.
            let now = Timestamp(date: Date())
            var savedSession = EncounterSession(
                id: "demo_session_\(match.id)",
                matchID: match.id,
                userAUID: match.userAUID,
                userBUID: match.userBUID,
                startTimestamp: now,
                revealProgress: 0.0,
                icebreakerType: .trivia,
                revealStage: .blurred,
                sessionTimeout: Timestamp(date: Date().addingTimeInterval(EncounterSession.defaultDurationSeconds)),
                lastUpdated: now,
                schoolId: match.schoolId,
                partnerSchoolId: match.partnerSchoolId,
                scope: match.scope,
                springBreakDestinationID: match.springBreakDestinationID,
                lockedIntents: match.lockedIntents,
                isDatingGated: match.isDatingGated
            )
            savedSession.participantUIDs = [match.userAUID, match.userBUID]
            activeSessions[match.id] = savedSession
            recomputeSlots(for: currentUser.uid, from: Array(activeSessions.values))
            analytics.logRevealSessionStarted(matchID: match.id)
            return .opened
        }
        #endif

        do {
            let result = try await functions
                .httpsCallable("openEncounterSession")
                .call(["matchId": match.id])

            guard let payload = result.data as? [String: Any],
                  let sessionID = payload["sessionId"] as? String else {
                return .unavailable
            }

            // Read the session back rather than reconstructing it: the server
            // owns participantUIDs, the window and the slot state, and a locally
            // assembled copy would be a guess at all three.
            if let snapshot = try? await sessionsCollection.document(sessionID).getDocument(),
               let saved = try? snapshot.data(as: EncounterSession.self) {
                activeSessions[match.id] = saved
            }

            analytics.logRevealSessionStarted(matchID: match.id)
            return .opened
        } catch {
            // `resource-exhausted` is the caller's own cap, and it is the one
            // failure worth naming — they can act on it. Everything else,
            // including the partner being full, stays generic: telling A that B
            // is mid-encounter is a fact about B's evening that B did not choose
            // to share.
            if let nsError = error as NSError?,
               nsError.domain == FunctionsErrorDomain,
               FunctionsErrorCode(rawValue: nsError.code) == .resourceExhausted {
                Log.reveal.debug("Encounter blocked: caller is at the session cap")
                return .atCap
            }
            Log.reveal.error("Failed to open session: \(error.localizedDescription)")
            return .unavailable
        }
    }

    /// Why an encounter did or did not open.
    enum SessionOpenResult: Equatable {
        case opened
        case alreadyOpen
        /// The signed-in user is holding the maximum number of encounters.
        case atCap
        /// Anything else — including the partner being at their own cap.
        case unavailable
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
    /// NameDrop also requires the student ID <-> liveness face match, whatever the
    /// encounter's intent. Exchanging real identity is the moment the stakes rise,
    /// so it carries the Dating-tier proof even on a Study encounter.
    /// `firestore.rules` enforces the same thing: a write moving revealStage to
    /// 'connected' is rejected without the faceMatched claim.
    ///
    /// Firestore write is narrow: only revealStage, revealProgress, lastUpdated.
    func completeReveal(for sessionID: String, currentUser: UserProfile) async {
        guard var session = sessionByID(sessionID) else { return }

        guard currentUser.canNameDrop else {
            Log.reveal.error("NameDrop blocked: student ID face match required")
            return
        }

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
            // One server call: the stage advance and the slot release happen in
            // the same transaction, so they cannot disagree. A client that set
            // 'connected' and then failed to free the slot would hold a slot on a
            // finished encounter until the window elapsed.
            _ = try await functions
                .httpsCallable("closeEncounterSession")
                .call([
                    "sessionId": sessionID,
                    "reason": EncounterSession.CloseReason.nameDrop.rawValue
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

    /// Ends an encounter session and frees the slot.
    ///
    /// The reason is required rather than defaulted. Every case frees the slot,
    /// so the parameter changes nothing about the outcome — but "the user passed"
    /// and "the user reported them as unsafe" are very different facts to have in
    /// the audit trail, and a default would quietly record the wrong one.
    ///
    /// Does NOT delete the Firestore document — the trail is the point.
    func endSession(for matchID: String, reason: EncounterSession.CloseReason) async {
        guard let session = activeSessions[matchID], let sessionID = session.id else { return }

        activeSessions.removeValue(forKey: matchID)

        #if DEBUG
        if isDemoMode {
            analytics.logRevealSessionEnded(matchID: matchID, finalStage: session.revealStage)
            return
        }
        #endif

        do {
            _ = try await functions
                .httpsCallable("closeEncounterSession")
                .call(["sessionId": sessionID, "reason": reason.rawValue])

            analytics.logRevealSessionEnded(matchID: matchID, finalStage: session.revealStage)
        } catch {
            // The slot still frees on its own when the window elapses, so a
            // failure here costs the user time, not a permanently held slot.
            Log.reveal.error("Failed to end session: \(error.localizedDescription)")
        }
    }

    /// Frees every slot the signed-in user holds. Called when Quest Mode goes off.
    ///
    /// Someone who has stopped looking should not be occupying the other person's
    /// slot, and should not come back later to a full cap.
    func releaseAllSessions() async {
        activeSessions.removeAll()

        #if DEBUG
        if isDemoMode { return }
        #endif

        do {
            _ = try await functions.httpsCallable("releaseEncounterSessions").call()
        } catch {
            Log.reveal.error("Failed to release sessions: \(error.localizedDescription)")
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
