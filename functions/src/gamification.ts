// MARK: - SECURITY CHECKLIST COMPLIANCE (see docs/SECURITY_CHECKLIST.md)
// [x] No hardcoded secrets — Admin SDK only
// [x] XP and badge grants happen ONLY here. The client cannot name a recipient:
//     awardXP and awardBadge always write request.auth.uid, so there is no shape
//     of request that grants XP to someone else.
// [x] The client does not send an amount either — it sends a reason, and the
//     amount comes from a server-side table. A client-supplied amount is a
//     faucet even when it is clamped.
// [x] Amounts are still clamped to 1..10000 after the multiplier, so a bad
//     Remote Config value cannot mint XP
// [x] Reasons and badge ids are fixed allowlists; anything else is rejected
// [x] Level is derived from totalXP server-side, never accepted from a client
// [x] Cross-user rewards (referral, waitlist survivor) have NO callable entry
//     point. They are issued by activateWaitlistedUsers, which is a scheduled
//     server event — asking a client to request them would reintroduce exactly
//     the faucet this file exists to close.
// [x] Firestore transaction for atomicity — concurrent grants cannot interleave
// [x] Server timestamps throughout; never a client clock
// [x] No PII logged — uid, reason and amount only; no names, no gender

import * as admin from "firebase-admin";
import { onCall, HttpsError, CallableRequest } from "firebase-functions/v2/https";

const db = admin.firestore();

/**
 * XP per reason. Server-side on purpose.
 *
 * The client sends a reason, not a number. That removes the whole class of bug
 * where a caller passes the wrong amount, and the whole class of attack where a
 * caller passes a deliberately large one.
 */
const XP_BY_REASON: Record<string, number> = {
  verification: 200,
  first_connection: 150,
  waitlist_survived: 100,
  icebreaker_completed: 50,
  namedrop_completed: 100,
  referral_reward: 100,
};

/** Reasons a client may request for itself. */
const CLIENT_REQUESTABLE_REASONS = new Set([
  "verification",
  "first_connection",
  "icebreaker_completed",
  "namedrop_completed",
]);

/** Badge ids a client may request for itself, mirroring GamificationService.BadgeType. */
const CLIENT_REQUESTABLE_BADGES = new Set([
  "verified_pioneer",
  "first_connection",
  "vibe_matchmaker",
]);

/** Badges only the server issues, tied to server-observed events. */
const SERVER_ONLY_BADGES = new Set(["waitlist_survivor", "balance_guardian"]);

const BADGE_NAMES: Record<string, string> = {
  balance_guardian: "Balance Guardian",
  verified_pioneer: "Verified Pioneer",
  vibe_matchmaker: "Vibe Matchmaker",
  waitlist_survivor: "Waitlist Survivor",
  first_connection: "First Connection",
};

const MIN_XP = 1;
const MAX_XP = 10000;

// Bounds for the underrepresented-gender multiplier. Remote Config is a live
// dial; a fat-fingered value there must not become a mint.
const MIN_MULTIPLIER = 1.0;
const MAX_MULTIPLIER = 2.0;

function requireAuth(request: CallableRequest): string {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentication required.");
  }
  return request.auth.uid;
}

/** Level from total XP. Mirrors GamificationProfile.computedLevel. */
function levelForXP(totalXP: number): number {
  return 1 + Math.floor(Math.sqrt(totalXP / 80));
}

/**
 * The gender multiplier for an underrepresented user on their own campus.
 *
 * Read from the user's own document and their school's Dating ratio, never from
 * the request. Returns 1.0 whenever anything is missing — a multiplier is a
 * bonus, and an absent signal should not pay one.
 */
async function multiplierFor(uid: string): Promise<number> {
  const userSnap = await db.collection("users").doc(uid).get();
  const user = userSnap.data();
  if (!user) return 1.0;

  const gender = user.gender as string | undefined;
  if (gender !== "female" && gender !== "non_binary") return 1.0;

  const schoolId = user.schoolId as string | undefined;
  if (!schoolId) return 1.0;

  const statsSnap = await db.collection("global_gender_stats").doc(schoolId).get();
  const stats = statsSnap.data();
  if (!stats) return 1.0;

  const malePct = typeof stats.malePct === "number" ? stats.malePct : 0.5;
  if (malePct <= 0.55) return 1.0;

  const configured =
    typeof stats.underrepresentedGenderMultiplier === "number"
      ? stats.underrepresentedGenderMultiplier
      : 1.2;

  return Math.min(Math.max(configured, MIN_MULTIPLIER), MAX_MULTIPLIER);
}

/**
 * The one XP write path.
 *
 * Exported for the server-triggered rewards below; it is not a callable, and it
 * takes an explicit uid precisely because the *server* is allowed to name a
 * recipient and a client is not.
 */
export async function grantXP(
  uid: string,
  reason: string,
  applyMultiplier: boolean
): Promise<{ awarded: number; totalXP: number; level: number }> {
  const base = XP_BY_REASON[reason];
  if (base === undefined) {
    throw new HttpsError("invalid-argument", "Unknown reward.");
  }

  const multiplier = applyMultiplier ? await multiplierFor(uid) : 1.0;
  const awarded = Math.min(Math.max(Math.round(base * multiplier), MIN_XP), MAX_XP);

  const docRef = db.collection("users").doc(uid);

  const result = await db.runTransaction(async (tx) => {
    const snap = await tx.get(docRef);
    if (!snap.exists) {
      throw new HttpsError("not-found", "Profile not found.");
    }

    const gam = (snap.data()?.gamification as Record<string, unknown>) ?? {};
    const currentXP = typeof gam.totalXP === "number" ? gam.totalXP : 0;
    const totalXP = currentXP + awarded;
    const level = levelForXP(totalXP);

    // Narrow write — only XP and level.
    tx.update(docRef, {
      "gamification.totalXP": totalXP,
      "gamification.level": level,
      lastActive: admin.firestore.FieldValue.serverTimestamp(),
    });

    return { totalXP, level };
  });

  console.info(`[grantXP] ${uid} +${awarded} (${reason}) -> ${result.totalXP}`);
  return { awarded, ...result };
}

/**
 * Awards a badge, deduplicated by id.
 *
 * Same shape as grantXP: server-callable with an explicit uid, client-callable
 * only for itself.
 */
export async function grantBadge(uid: string, badgeId: string): Promise<boolean> {
  const name = BADGE_NAMES[badgeId];
  if (!name) {
    throw new HttpsError("invalid-argument", "Unknown badge.");
  }

  const docRef = db.collection("users").doc(uid);

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(docRef);
    if (!snap.exists) return false;

    const badges = (snap.data()?.badges as Array<Record<string, unknown>>) ?? [];
    if (badges.some((b) => b.id === badgeId)) return false;

    tx.update(docRef, {
      badges: admin.firestore.FieldValue.arrayUnion({
        id: badgeId,
        name,
        awardedAt: admin.firestore.Timestamp.now(),
      }),
    });
    return true;
  });
}

// MARK: - awardXP (callable, self only)

export const awardXP = onCall(async (request) => {
  const uid = requireAuth(request);
  const reason = request.data?.reason;

  if (typeof reason !== "string" || !CLIENT_REQUESTABLE_REASONS.has(reason)) {
    // Deliberately does not say which reasons exist.
    throw new HttpsError("invalid-argument", "Unknown reward.");
  }

  // Note the uid: request.auth.uid, always. There is no recipient parameter.
  const result = await grantXP(uid, reason, true);
  return result;
});

// MARK: - awardBadge (callable, self only)

export const awardBadge = onCall(async (request) => {
  const uid = requireAuth(request);
  const badgeId = request.data?.badgeId;

  if (typeof badgeId !== "string" || SERVER_ONLY_BADGES.has(badgeId)) {
    throw new HttpsError("invalid-argument", "Unknown badge.");
  }
  if (!CLIENT_REQUESTABLE_BADGES.has(badgeId)) {
    throw new HttpsError("invalid-argument", "Unknown badge.");
  }

  const awarded = await grantBadge(uid, badgeId);
  return { awarded };
});

// MARK: - Server-triggered rewards
//
// No callable wrapper, by design. These fire on events the server observes, so
// exposing them to a client would let anyone claim a referral that never
// happened.

/**
 * Rewards a user activated off the waitlist, and their referrer if they had one.
 *
 * Called from activateWaitlistedUsers.
 */
export async function grantWaitlistActivationRewards(uid: string): Promise<void> {
  await grantXP(uid, "waitlist_survived", true);
  await grantBadge(uid, "waitlist_survivor");

  const referralSnap = await db.collection("referrals").doc(uid).get();
  const referrerUID = referralSnap.data()?.referredBy as string | undefined;
  if (!referrerUID || referrerUID === uid) return;

  const referrerSnap = await db.collection("users").doc(referrerUID).get();
  if (!referrerSnap.exists) return;

  await grantXP(referrerUID, "referral_reward", true);

  await db
    .collection("referrals")
    .doc(referrerUID)
    .set(
      {
        successfulReferrals: admin.firestore.FieldValue.increment(1),
        lastRewardedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

  console.info(`[grantWaitlistActivationRewards] ${uid} activated, referrer rewarded`);
}
