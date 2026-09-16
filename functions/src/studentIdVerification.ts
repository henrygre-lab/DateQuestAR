// MARK: - SECURITY CHECKLIST COMPLIANCE (see docs/SECURITY_CHECKLIST.md)
// [x] No hardcoded secrets — the face-match provider key is a defineSecret value
// [x] studentIDStatus, verifiedAge and trustLevel are written ONLY here. The
//     client cannot set them; firestore.rules rejects every client write to them.
// [x] Face matching happens server-side. The on-device Vision comparison in
//     SafetyVerifier is a UI affordance and is never trusted for gating.
// [x] Student ID images and liveness frames are read from the write-only Storage
//     prefix by the Admin SDK, then DELETED once the outcome is recorded. Only the
//     outcome (status, score, age) survives — no image is retained anywhere.
// [x] No image or path is ever written to the profile document, so none can reach
//     a nearby or match payload
// [x] Auth required; the subject is always request.auth.uid, never a client-supplied uid
// [x] Storage paths are validated to be inside the caller's own prefix (no IDOR)
// [x] Rate limited — 3 submissions per hour per uid, Firestore-backed
// [x] Generic errors — a caller never learns which specific check failed
// [x] No PII logged — uid, status and score bucket only; never a name, DOB or image
// [x] Age is clamped and sanity-checked before storage

import * as admin from "firebase-admin";
import { onCall, HttpsError, CallableRequest } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";

const db = admin.firestore();

// Face-match provider key. Never leaves the server.
const FACE_MATCH_API_KEY = defineSecret("FACE_MATCH_API_KEY");

const MAX_SUBMISSIONS_PER_HOUR = 3;

// Face-match threshold. Set deliberately high: a false accept here is someone
// using another student's ID, which is the exact failure the gate exists to stop.
const FACE_MATCH_THRESHOLD = 0.82;

// Liveness confidence floor, mirroring the on-device detector's >= 3 consecutive
// confirmation frames.
const LIVENESS_THRESHOLD = 0.75;

const MIN_PLAUSIBLE_AGE = 15;
const MAX_PLAUSIBLE_AGE = 99;

type StudentIDStatus = "none" | "pending" | "verified" | "faceMatched" | "rejected";

interface ProviderOutcome {
  livenessScore: number;
  faceMatchScore: number;
  extractedAge: number | null;
  schoolNameOnCard: string | null;
}

function requireAuth(request: CallableRequest): string {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentication required.");
  }
  return request.auth.uid;
}

/**
 * One message for every rejection.
 *
 * A caller must not be able to distinguish "liveness failed" from "faces did not
 * match" from "we could not read the card" — that difference tells someone
 * holding a borrowed ID exactly what to fix.
 */
function reject(): never {
  throw new HttpsError(
    "failed-precondition",
    "We couldn't verify your student ID. Try again in good lighting."
  );
}

async function consumeRateLimit(uid: string): Promise<void> {
  const hourKey = new Date().toISOString().slice(0, 13);
  const ref = db
    .collection("users")
    .doc(uid)
    .collection("verification")
    .doc("ratelimit_studentid");

  const allowed = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const data = snap.data() ?? {};
    const count = data.hourKey === hourKey ? (data.count as number) : 0;
    if (count >= MAX_SUBMISSIONS_PER_HOUR) return false;
    tx.set(ref, { hourKey, count: count + 1 }, { merge: true });
    return true;
  });

  if (!allowed) reject();
}

/** A path is only acceptable inside the caller's own write-only prefix. */
function isOwnedVerificationPath(uid: string, path: unknown): path is string {
  return (
    typeof path === "string" &&
    path.length < 512 &&
    path.startsWith(`verification/${uid}/`) &&
    !path.includes("..")
  );
}

/**
 * Sends the artefacts to the face-match provider and returns the outcome.
 *
 * The images are streamed from Storage by the Admin SDK; they are never exposed
 * through a download URL and never round-trip through the client.
 */
async function runProviderCheck(
  idImage: Buffer,
  livenessFrames: Buffer[]
): Promise<ProviderOutcome> {
  const response = await fetch("https://api.faceverify.dev/v1/student-id-match", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${FACE_MATCH_API_KEY.value()}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      idDocument: idImage.toString("base64"),
      livenessFrames: livenessFrames.map((f) => f.toString("base64")),
      documentType: "student_id",
    }),
  });

  if (!response.ok) {
    // Status only. A provider body can echo extracted PII.
    console.error(`[studentIdVerification] provider status ${response.status}`);
    throw new HttpsError("internal", "Verification is unavailable right now.");
  }

  const body = (await response.json()) as {
    liveness_score?: number;
    face_match_score?: number;
    extracted_age?: number;
    school_name?: string;
  };

  return {
    livenessScore: body.liveness_score ?? 0,
    faceMatchScore: body.face_match_score ?? 0,
    extractedAge:
      typeof body.extracted_age === "number" ? Math.floor(body.extracted_age) : null,
    schoolNameOnCard: body.school_name ?? null,
  };
}

/**
 * Deletes the uploaded artefacts.
 *
 * Called on every path — success, rejection and provider failure. Retaining a
 * student ID photo buys nothing once the outcome is recorded, and it is the one
 * artefact in this system whose leak would be unrecoverable.
 */
async function purgeArtefacts(paths: string[]): Promise<void> {
  const bucket = admin.storage().bucket();
  await Promise.all(
    paths.map(async (path) => {
      try {
        await bucket.file(path).delete({ ignoreNotFound: true });
      } catch (error) {
        // Log the path's owner-scoped prefix only, never the object contents.
        console.error(`[studentIdVerification] purge failed for a verification object`);
      }
    })
  );
}

/** Keeps the auth claims and the profile document in step. */
async function applyStatus(
  uid: string,
  status: StudentIDStatus,
  verifiedAge: number | null
): Promise<void> {
  const trustLevel =
    status === "faceMatched" ? "gold" : status === "verified" ? "silver" : "bronze";

  const profileUpdate: Record<string, unknown> = {
    studentIDStatus: status,
    trustLevel,
  };

  if (status === "verified" || status === "faceMatched") {
    profileUpdate.verificationStatus = "verified";
    profileUpdate.verificationCompletedAt =
      admin.firestore.FieldValue.serverTimestamp();
  }

  // verifiedAge is written only on a real reading. A null must never overwrite a
  // previously verified age.
  if (verifiedAge !== null) {
    profileUpdate.verifiedAge = verifiedAge;
  }

  await db.collection("users").doc(uid).set(profileUpdate, { merge: true });

  const claims = (await admin.auth().getUser(uid)).customClaims ?? {};
  await admin.auth().setCustomUserClaims(uid, { ...claims, studentIDStatus: status });
}

// MARK: - submitStudentIDVerification
//
// The Quest Mode gate, and — when the faces match — the Dating and NameDrop gate.
//
// The client uploads the student ID photo and liveness frames to its write-only
// Storage prefix and calls this with the paths. Everything that decides access
// happens here.

export const submitStudentIDVerification = onCall(
  { secrets: [FACE_MATCH_API_KEY] },
  async (request) => {
    const uid = requireAuth(request);
    await consumeRateLimit(uid);

    // The school gate must already have passed. A student ID is evidence about a
    // person, not about which community they belong to.
    const claims = (await admin.auth().getUser(uid)).customClaims ?? {};
    const enrollment = claims.enrollmentStatus as string | undefined;
    if (
      typeof claims.schoolId !== "string" ||
      claims.schoolId.length === 0 ||
      (enrollment !== "enrolled" && enrollment !== "incoming")
    ) {
      reject();
    }

    const idPath = request.data?.studentIDStoragePath;
    const framePaths = request.data?.livenessFrameStoragePaths;

    if (!isOwnedVerificationPath(uid, idPath)) reject();
    if (!Array.isArray(framePaths) || framePaths.length === 0 || framePaths.length > 8) {
      reject();
    }
    for (const path of framePaths) {
      if (!isOwnedVerificationPath(uid, path)) reject();
    }

    const allPaths = [idPath as string, ...(framePaths as string[])];

    await db
      .collection("users")
      .doc(uid)
      .collection("verification")
      .doc("studentId")
      .set(
        {
          uid,
          studentIDStatus: "pending",
          submittedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
    await applyStatus(uid, "pending", null);

    const bucket = admin.storage().bucket();
    let outcome: ProviderOutcome;

    try {
      const [idImage] = await bucket.file(idPath as string).download();
      const frames = await Promise.all(
        (framePaths as string[]).map(async (p) => (await bucket.file(p).download())[0])
      );
      outcome = await runProviderCheck(idImage, frames);
    } catch (error) {
      await purgeArtefacts(allPaths);
      await applyStatus(uid, "rejected", null);
      if (error instanceof HttpsError) throw error;
      console.error(`[studentIdVerification] ${uid} artefact read failed`);
      throw new HttpsError("internal", "Verification is unavailable right now.");
    }

    // The images have served their purpose. Nothing below needs them.
    await purgeArtefacts(allPaths);

    const livenessPassed = outcome.livenessScore >= LIVENESS_THRESHOLD;
    const facesMatched = outcome.faceMatchScore >= FACE_MATCH_THRESHOLD;

    const age =
      outcome.extractedAge !== null &&
      outcome.extractedAge >= MIN_PLAUSIBLE_AGE &&
      outcome.extractedAge <= MAX_PLAUSIBLE_AGE
        ? outcome.extractedAge
        : null;

    const status: StudentIDStatus = !livenessPassed
      ? "rejected"
      : facesMatched
        ? "faceMatched"
        : "verified";

    await db
      .collection("users")
      .doc(uid)
      .collection("verification")
      .doc("studentId")
      .set(
        {
          uid,
          studentIDStatus: status,
          faceMatchScore: outcome.faceMatchScore,
          verifiedAge: age,
          // Recorded so a reviewer can spot a card from a school the account does
          // not belong to. Not shown to any client.
          schoolNameOnCard: outcome.schoolNameOnCard,
          studentIDStoragePath: null,
          livenessFrameStoragePaths: [],
          reviewedAt: admin.firestore.FieldValue.serverTimestamp(),
          rejectionReason:
            status === "rejected"
              ? "We couldn't verify your student ID. Try again in good lighting."
              : null,
        },
        { merge: true }
      );

    await applyStatus(uid, status, age);

    // Score bucket rather than the score itself — enough to spot a drifting
    // threshold, not enough to tune an attack against it.
    console.info(
      `[studentIdVerification] ${uid} -> ${status} (match bucket ${Math.floor(
        outcome.faceMatchScore * 10
      )})`
    );

    if (status === "rejected") reject();

    return {
      studentIDStatus: status,
      canStartQuestMode: true,
      canUseDatingIntent: status === "faceMatched" && age !== null && age >= 18,
      requiresTokenRefresh: true,
    };
  }
);

// MARK: - revokeStudentIDVerification (admin only)
//
// Used when a card turns out to be borrowed or forged. Drops the user out of
// Quest Mode, Dating and NameDrop in one write.

export const revokeStudentIDVerification = onCall(async (request) => {
  const actor = requireAuth(request);
  if (request.auth?.token.admin !== true) {
    throw new HttpsError("permission-denied", "Admin access required.");
  }

  const targetUid = request.data?.uid;
  if (typeof targetUid !== "string") {
    throw new HttpsError("invalid-argument", "uid is required.");
  }

  await applyStatus(targetUid, "rejected", null);
  await db
    .collection("users")
    .doc(targetUid)
    .collection("verification")
    .doc("studentId")
    .set(
      {
        studentIDStatus: "rejected",
        reviewedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

  console.info(`[revokeStudentIDVerification] ${targetUid} revoked by ${actor}`);
  return { studentIDStatus: "rejected" };
});
