// MARK: - SECURITY CHECKLIST COMPLIANCE (see docs/SECURITY_CHECKLIST.md)
// [x] No hardcoded secrets — Admin SDK only
// [x] activeIntents and datingCooldownUntil are written ONLY here; firestore.rules
//     lists both as server-owned and rejects every client write to them
// [x] Auth required; the subject is always request.auth.uid
// [x] Input validated against a closed set — an unknown intent string is rejected
//     rather than stored
// [x] Dating requires the ID <-> liveness face match AND a verified adult age,
//     both read from server-written fields, never from the request
// [x] Switching Dating off sets a 24h server cooldown, so caps cannot be shed by
//     toggling. The cooldown is a server timestamp, never a client clock.
// [x] Server timestamps throughout
// [x] No PII logged — uid and intent names only

import * as admin from "firebase-admin";
import { onCall, HttpsError, CallableRequest } from "firebase-functions/v2/https";

const db = admin.firestore();

const VALID_INTENTS = ["hangout", "study", "friendship", "event", "dating"] as const;
type Intent = (typeof VALID_INTENTS)[number];

/**
 * How long Dating's protections outlive switching Dating off.
 *
 * The whole point: a user cannot drop Dating to escape asymmetric caps,
 * women-first queuing or the male waitlist and keep receiving proximity alerts.
 * For 24h after switching off, they are still Dating-gated.
 */
const DATING_COOLDOWN_HOURS = 24;

const MIN_DATING_AGE = 18;

function requireAuth(request: CallableRequest): string {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentication required.");
  }
  return request.auth.uid;
}

function parseIntents(raw: unknown): Intent[] {
  if (!Array.isArray(raw) || raw.length === 0 || raw.length > VALID_INTENTS.length) {
    throw new HttpsError("invalid-argument", "Choose at least one intent.");
  }

  const parsed: Intent[] = [];
  for (const value of raw) {
    if (typeof value !== "string") {
      throw new HttpsError("invalid-argument", "Choose at least one intent.");
    }
    const intent = VALID_INTENTS.find((i) => i === value);
    // Unknown strings are rejected outright rather than silently dropped: a
    // caller sending garbage should learn its request did not take effect.
    if (!intent) {
      throw new HttpsError("invalid-argument", "Choose at least one intent.");
    }
    if (!parsed.includes(intent)) parsed.push(intent);
  }
  return parsed;
}

// MARK: - setActiveIntents
//
// The only way a user's intents change.

export const setActiveIntents = onCall(async (request) => {
  const uid = requireAuth(request);
  const requested = parseIntents(request.data?.intents);

  const userRef = db.collection("users").doc(uid);
  const snap = await userRef.get();
  if (!snap.exists) {
    throw new HttpsError("failed-precondition", "Finish setting up your profile first.");
  }

  const profile = snap.data() ?? {};
  const previous = (profile.activeIntents as string[] | undefined) ?? [];
  const wasDating = previous.includes("dating");
  const wantsDating = requested.includes("dating");

  // Dating gate, checked against server-written fields only.
  if (wantsDating) {
    const studentIDStatus = profile.studentIDStatus as string | undefined;
    const verifiedAge = profile.verifiedAge as number | undefined;

    if (studentIDStatus !== "faceMatched") {
      throw new HttpsError(
        "failed-precondition",
        "Dating needs your student ID and selfie to match. Finish verification first."
      );
    }
    if (typeof verifiedAge !== "number" || verifiedAge < MIN_DATING_AGE) {
      // Deliberately vague about age: an incoming 17-year-old should not be
      // told the exact number that would let them in.
      throw new HttpsError(
        "failed-precondition",
        "Dating isn't available on this account."
      );
    }
  }

  const update: Record<string, unknown> = { activeIntents: requested };

  if (wasDating && !wantsDating) {
    // Dating switched off: start the cooldown. Computed from the server clock.
    update.datingCooldownUntil = admin.firestore.Timestamp.fromMillis(
      Date.now() + DATING_COOLDOWN_HOURS * 60 * 60 * 1000
    );
  }
  // Switching Dating back on does not clear an existing cooldown — it does not
  // need to. isDatingGated is true either way, and leaving it alone means a
  // rapid on/off/on cycle cannot be used to shorten the window.

  await userRef.set(update, { merge: true });

  console.info(
    `[setActiveIntents] ${uid} -> [${requested.join(",")}]` +
      (wasDating && !wantsDating ? " (dating cooldown started)" : "")
  );

  return {
    activeIntents: requested,
    datingCooldownUntil:
      update.datingCooldownUntil instanceof admin.firestore.Timestamp
        ? update.datingCooldownUntil.toMillis()
        : (profile.datingCooldownUntil as admin.firestore.Timestamp | undefined)?.toMillis() ??
          null,
  };
});
