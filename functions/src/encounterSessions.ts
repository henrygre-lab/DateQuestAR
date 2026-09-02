// MARK: - SECURITY CHECKLIST COMPLIANCE (see docs/SECURITY_CHECKLIST.md)
// [x] No hardcoded secrets — Admin SDK only
// [x] Encounter sessions are created ONLY here. firestore.rules denies client
//     creates on encounter_sessions, so the slot count cannot be bypassed by a
//     client that simply writes its own session document.
// [x] The count is a Firestore query inside a transaction, keyed by uid — never
//     a client-supplied number and never a local array
// [x] Both participants are counted. A session occupies a slot for each of them,
//     so a popular user cannot be pulled into more encounters than they have room
//     for by other people opening sessions against them.
// [x] Same-school gate re-checked here against the caller's custom claims, not
//     the match document alone: the match was validated when it was written, and
//     a school can be revoked after that.
// [x] participantUIDs, slotState, closedReason and closedAt are server-written
// [x] Sessions always open at revealStage 'blurred' — no earlier photo access
// [x] Generic errors to the caller; the distinction between "you are full" and
//     "they are full" is deliberate and is the only distinction exposed
// [x] Server timestamps throughout; the session window is computed server-side
// [x] No PII logged — uids, session ids and reasons only

import * as admin from "firebase-admin";
import { onCall, HttpsError, CallableRequest } from "firebase-functions/v2/https";

const db = admin.firestore();

/**
 * Encounters one person may hold at once.
 *
 * Two, not one: a single slot would mean the first person who walks past locks
 * you out of everyone else for fifteen minutes, which is a worse experience than
 * the swarm it prevents. Two leaves room to be mid-encounter and still notice
 * someone, without room to collect people.
 *
 * Mirrored by EncounterSession.maxActiveSessionsPerUser on the client, which is
 * a courtesy filter. This constant is the one that decides.
 */
const MAX_ACTIVE_SESSIONS = 2;

/** Session window, mirroring EncounterSession.defaultDurationSeconds. */
const SESSION_DURATION_SECONDS = 10 * 60;

const CLOSE_REASONS = new Set([
  "nameDrop",
  "pass",
  "unsafeProximity",
  "timeout",
  "questModeOff",
]);

function requireAuth(request: CallableRequest): string {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentication required.");
  }
  return request.auth.uid;
}

function claim(request: CallableRequest, key: string, fallback: string): string {
  const token = request.auth?.token as Record<string, unknown> | undefined;
  const value = token?.[key];
  return typeof value === "string" ? value : fallback;
}

/**
 * Counts the sessions currently holding a slot for `uid`.
 *
 * Three predicates, and the third is the one that makes this self-healing:
 * a session past its window stops counting without anyone writing to it. An
 * abandoned encounter — the other person walked off, the app was killed — cannot
 * strand someone at the cap.
 *
 * Runs inside the caller's transaction so two simultaneous opens cannot both see
 * a free slot.
 */
async function countActiveSlots(
  tx: admin.firestore.Transaction,
  uid: string,
  now: admin.firestore.Timestamp
): Promise<number> {
  const query = db
    .collection("encounter_sessions")
    .where("participantUIDs", "array-contains", uid)
    .where("slotState", "==", "active")
    .where("sessionTimeout", ">", now);

  const snapshot = await tx.get(query);
  return snapshot.size;
}

// MARK: - openEncounterSession

/**
 * Opens an encounter session for a match, if both participants have a free slot.
 *
 * This is the only path that creates one. The client used to write the document
 * directly, which meant the cap was whatever the client felt like enforcing.
 */
export const openEncounterSession = onCall(async (request) => {
  const uid = requireAuth(request);
  const matchId = request.data?.matchId;

  if (typeof matchId !== "string" || matchId.length === 0 || matchId.length > 200) {
    throw new HttpsError("invalid-argument", "A match is required.");
  }

  const matchRef = db.collection("matches").doc(matchId);
  const matchSnap = await matchRef.get();
  if (!matchSnap.exists) {
    throw new HttpsError("not-found", "That encounter is no longer available.");
  }

  const match = matchSnap.data() ?? {};
  const userAUID = match.userAUID as string;
  const userBUID = match.userBUID as string;

  if (uid !== userAUID && uid !== userBUID) {
    // Not a participant. Says nothing about whether the match exists.
    throw new HttpsError("permission-denied", "That encounter is no longer available.");
  }

  const partnerUID = uid === userAUID ? userBUID : userAUID;
  if (!partnerUID || partnerUID === uid) {
    throw new HttpsError("failed-precondition", "That encounter is no longer available.");
  }

  // Community gate, re-checked against live claims rather than trusting the
  // match document. The match was validated when it was written; a school or a
  // student ID can be revoked after that, and this is the last point before two
  // people are put in a room together.
  const callerSchoolId = claim(request, "schoolId", "");
  const callerStudentID = claim(request, "studentIDStatus", "none");
  const callerEnrollment = claim(request, "enrollmentStatus", "unverified");

  const questEligible =
    callerSchoolId !== "" &&
    (callerEnrollment === "enrolled" || callerEnrollment === "incoming") &&
    (callerStudentID === "verified" || callerStudentID === "faceMatched");

  if (!questEligible || match.schoolId !== callerSchoolId) {
    throw new HttpsError("permission-denied", "That encounter is no longer available.");
  }

  if (match.partnerSchoolId !== callerSchoolId) {
    // Cross-school is legal only inside a live destination the caller is
    // confirmed at — the same condition firestore.rules applies.
    const destId = match.springBreakDestinationID;
    const callerDest = claim(request, "sbDest", "");
    if (
      match.scope !== "springBreak" ||
      typeof destId !== "string" ||
      destId !== callerDest ||
      !(await destinationIsLive(destId))
    ) {
      throw new HttpsError("permission-denied", "That encounter is no longer available.");
    }
  }

  const now = admin.firestore.Timestamp.now();
  const sessionRef = db.collection("encounter_sessions").doc();

  const outcome = await db.runTransaction(async (tx) => {
    // Reads first — Firestore transactions require it.
    const existing = await tx.get(
      db
        .collection("encounter_sessions")
        .where("matchID", "==", matchId)
        .where("slotState", "==", "active")
        .where("sessionTimeout", ">", now)
    );
    if (!existing.empty) {
      return { status: "existing" as const, sessionId: existing.docs[0].id };
    }

    const callerSlots = await countActiveSlots(tx, uid, now);
    if (callerSlots >= MAX_ACTIVE_SESSIONS) {
      return { status: "callerFull" as const, sessionId: null };
    }

    const partnerSlots = await countActiveSlots(tx, partnerUID, now);
    if (partnerSlots >= MAX_ACTIVE_SESSIONS) {
      return { status: "partnerFull" as const, sessionId: null };
    }

    tx.set(sessionRef, {
      matchID: matchId,
      userAUID,
      userBUID,
      participantUIDs: [userAUID, partnerUID === userBUID ? userBUID : partnerUID],
      startTimestamp: now,
      revealProgress: 0,
      icebreakerType: match.icebreakerType ?? "trivia",
      // Always opens blurred. A session cannot be created part-revealed.
      revealStage: "blurred",
      sessionTimeout: admin.firestore.Timestamp.fromMillis(
        now.toMillis() + SESSION_DURATION_SECONDS * 1000
      ),
      lastUpdated: now,
      schoolId: match.schoolId,
      partnerSchoolId: match.partnerSchoolId,
      scope: match.scope ?? "campus",
      springBreakDestinationID: match.springBreakDestinationID ?? null,
      lockedIntents: match.lockedIntents ?? [],
      isDatingGated: match.isDatingGated === true,
      slotState: "active",
      closedReason: null,
      closedAt: null,
    });

    tx.update(matchRef, {
      encounterSessionID: sessionRef.id,
      revealStage: "blurred",
    });

    return { status: "opened" as const, sessionId: sessionRef.id };
  });

  if (outcome.status === "callerFull") {
    // The one distinction worth exposing: the caller can act on this.
    throw new HttpsError(
      "resource-exhausted",
      "Finish or pass your current quests to meet someone new."
    );
  }

  if (outcome.status === "partnerFull") {
    // Deliberately indistinguishable from "unavailable". Telling A that B is
    // mid-encounter with someone else is a fact about B's evening that B did not
    // choose to share.
    throw new HttpsError("unavailable", "That encounter is no longer available.");
  }

  console.info(`[openEncounterSession] ${uid} <-> ${partnerUID} (${outcome.status})`);
  return { sessionId: outcome.sessionId, status: outcome.status };
});

/** Whether a Spring Break destination is switched on and inside its window. */
async function destinationIsLive(destinationId: string): Promise<boolean> {
  const snap = await db.collection("spring_break_destinations").doc(destinationId).get();
  if (!snap.exists) return false;
  const dest = snap.data() ?? {};
  if (dest.isActive !== true) return false;

  const start = dest.windowStart as admin.firestore.Timestamp | undefined;
  const end = dest.windowEnd as admin.firestore.Timestamp | undefined;
  if (!start || !end || start.toMillis() >= end.toMillis()) return false;

  const nowMs = Date.now();
  return nowMs >= start.toMillis() && nowMs <= end.toMillis();
}

// MARK: - closeEncounterSession

/**
 * Frees a slot.
 *
 * On a NameDrop this also advances the reveal stage, in the same transaction, so
 * the stage and the slot can never disagree — a client that set 'connected' and
 * then failed to close would otherwise hold a slot on a finished encounter.
 */
export const closeEncounterSession = onCall(async (request) => {
  const uid = requireAuth(request);
  const sessionId = request.data?.sessionId;
  const reason = request.data?.reason;

  if (typeof sessionId !== "string" || sessionId.length === 0) {
    throw new HttpsError("invalid-argument", "A session is required.");
  }
  if (typeof reason !== "string" || !CLOSE_REASONS.has(reason)) {
    throw new HttpsError("invalid-argument", "Unknown reason.");
  }

  const sessionRef = db.collection("encounter_sessions").doc(sessionId);

  const matchID = await db.runTransaction(async (tx) => {
    const snap = await tx.get(sessionRef);
    if (!snap.exists) {
      throw new HttpsError("not-found", "That encounter is no longer available.");
    }

    const session = snap.data() ?? {};
    const participants = (session.participantUIDs as string[] | undefined) ?? [];
    if (!participants.includes(uid)) {
      throw new HttpsError("permission-denied", "That encounter is no longer available.");
    }

    // Already closed is a success, not an error — a retry, a second tap, or both
    // participants passing at once should all land in the same place.
    if (session.slotState !== "active") {
      return session.matchID as string | undefined;
    }

    const update: Record<string, unknown> = {
      slotState: "closed",
      closedReason: reason,
      closedAt: admin.firestore.FieldValue.serverTimestamp(),
      lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
    };

    if (reason === "nameDrop") {
      // NameDrop needs the ID <-> liveness face match, same as everywhere else.
      if (claim(request, "studentIDStatus", "none") !== "faceMatched") {
        throw new HttpsError("permission-denied", "Verification required.");
      }
      // And it is only reachable from .revealed.
      if (session.revealStage !== "revealed" && session.revealStage !== "connected") {
        throw new HttpsError("failed-precondition", "Finish the icebreaker first.");
      }
      update.revealStage = "connected";
      update.revealProgress = 1;
    }

    tx.update(sessionRef, update);
    return session.matchID as string | undefined;
  });

  if (reason === "nameDrop" && matchID) {
    await db.collection("matches").doc(matchID).update({
      revealStage: "connected",
      status: "connected",
    });
  }

  console.info(`[closeEncounterSession] ${sessionId} closed (${reason})`);
  return { closed: true, reason };
});

// MARK: - releaseEncounterSessions

/**
 * Closes every session the caller is holding.
 *
 * Called when Quest Mode goes off. Someone who has stopped looking should not be
 * occupying the other person's slot, and should not come back to a full cap.
 */
export const releaseEncounterSessions = onCall(async (request) => {
  const uid = requireAuth(request);
  const now = admin.firestore.Timestamp.now();

  const snapshot = await db
    .collection("encounter_sessions")
    .where("participantUIDs", "array-contains", uid)
    .where("slotState", "==", "active")
    .where("sessionTimeout", ">", now)
    .limit(MAX_ACTIVE_SESSIONS * 2)
    .get();

  if (snapshot.empty) return { released: 0 };

  const batch = db.batch();
  for (const doc of snapshot.docs) {
    batch.update(doc.ref, {
      slotState: "closed",
      closedReason: "questModeOff",
      closedAt: admin.firestore.FieldValue.serverTimestamp(),
      lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
    });
  }
  await batch.commit();

  console.info(`[releaseEncounterSessions] ${uid} released ${snapshot.size}`);
  return { released: snapshot.size };
});
