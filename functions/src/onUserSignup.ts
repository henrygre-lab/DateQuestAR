// MARK: - SECURITY CHECKLIST COMPLIANCE (see docs/SECURITY_CHECKLIST.md)
// [x] No hardcoded secrets — uses Admin SDK service account, not API keys
// [x] Triggered by Firebase Auth onCreate — cannot be called by arbitrary clients
// [x] Writes only to the newly created user's own document + waitlist entry
// [x] Waitlist decision based on server-side gender stats, not client input
// [x] The waitlist is DATING-ONLY and per-school: it is keyed on the user's own
//     campus ratio, and only applied when the user has actually selected Dating.
//     A man who signs up for Study is never queued.
// [x] New accounts start with no schoolId and enrollmentStatus 'unverified' —
//     signing up grants no community; only schoolGate.ts issues one
// [x] activeIntents defaults to Hangout + Study; Dating is never a default
// [x] Server timestamps used for all time fields — never trust client clock
// [x] Minimal data written — only balance/safety defaults, no echoed PII

import * as admin from "firebase-admin";
import { beforeUserCreated } from "firebase-functions/v2/identity";

const db = admin.firestore();

const MALE_CAP_THRESHOLD = 0.55;
const DEFAULT_FEMALE_ALERT_CAP = 3;
const DEFAULT_MALE_ALERT_CAP = 8;
const WAITLIST_ACTIVATION_DELAY_HOURS = 24;

/**
 * onUserSignup — Blocking Auth trigger that fires when a new user is created.
 *
 * Sets gender-neutral safety defaults only. No gender-based decisions here
 * because gender isn't known yet (set later during profile setup).
 *
 * Gender-specific logic (waitlist, alert caps, boost) lives in the
 * callable `applyGenderDefaults`, invoked after ProfileSetupView.
 */
export const onUserSignup = beforeUserCreated(async (event) => {
  const uid = event.data.uid;
  const userDoc = db.collection("users").doc(uid);

  // Gender-neutral safety defaults — gender set later during onboarding
  const safetyDefaults: Record<string, unknown> = {
    gender: "prefer_not_to_say",
    alertCapPerHour: DEFAULT_MALE_ALERT_CAP,
    currentHourAlerts: {},
    balanceBoostMultiplier: 1.0,
    accountStatus: "active",
    waitlistEntryTime: null,
    activationDelayHours: null,
    verificationStatus: "unverified",
    intentVibes: [],
    socialContextPreference: true,
    // Community state: none. Signing up gets you an account, not a campus.
    // Only schoolGate.ts issues schoolId and enrollmentStatus.
    schoolId: null,
    schoolDisplayName: null,
    enrollmentStatus: "unverified",
    studentIDStatus: "none",
    verifiedAge: null,
    // Hangout + Study. Dating is opt-in and needs the ID <-> liveness face match.
    activeIntents: ["hangout", "study"],
    datingCooldownUntil: null,
    springBreakDestinationId: null,
  };

  await userDoc.set(safetyDefaults, { merge: true });

  console.log(`[onUserSignup] Initialized safety fields for ${uid}`);
  return;
});

/**
 * applyGenderDefaults — Called from client after gender is set during profile setup.
 * This is a Callable function so the client can trigger it after ProfileSetupView.
 */
import { onCall, HttpsError } from "firebase-functions/v2/https";

export const applyGenderDefaults = onCall(async (request) => {
  // Auth required
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentication required.");
  }

  const uid = request.auth.uid;
  const gender = request.data?.gender as string | undefined;

  if (
    !gender ||
    !["male", "female", "non_binary", "prefer_not_to_say"].includes(gender)
  ) {
    throw new HttpsError("invalid-argument", "Invalid gender value.");
  }

  const userSnap = await db.collection("users").doc(uid).get();
  const profile = userSnap.data() ?? {};
  const schoolId = profile.schoolId as string | undefined;
  const intents = (profile.activeIntents as string[] | undefined) ?? [];
  const wantsDating = intents.includes("dating");

  // Read this campus's Dating ratio. A national number would be meaningless —
  // the person is going to meet people on their own campus.
  const statsDoc = schoolId
    ? await db.collection("global_gender_stats").doc(schoolId).get()
    : null;
  const stats = statsDoc?.data();
  const malePct = stats?.malePct ?? 0.5;
  const imbalanced = malePct > MALE_CAP_THRESHOLD;

  const updates: Record<string, unknown> = {
    gender: gender,
    alertCapPerHour:
      gender === "female" || gender === "non_binary"
        ? DEFAULT_FEMALE_ALERT_CAP
        : DEFAULT_MALE_ALERT_CAP,
    balanceBoostMultiplier:
      gender === "female" || gender === "non_binary" ? 1.3 : 1.0,
  };

  // Waitlist logic: a man is queued only if he has actually selected Dating and
  // his own campus's Dating ratio is skewed. Queuing someone who signed up to
  // find a study partner would be both useless and insulting.
  if (gender === "male" && wantsDating && imbalanced) {
    updates.accountStatus = "waitlisted";
    updates.waitlistEntryTime = admin.firestore.FieldValue.serverTimestamp();
    updates.activationDelayHours = WAITLIST_ACTIVATION_DELAY_HOURS;

    // Create waitlist entry (managed by Cloud Functions only)
    await db.collection("waitlist").doc(uid).set({
      uid: uid,
      gender: gender,
      schoolId: schoolId ?? null,
      // Recorded so the queue can never be mistaken for a whole-app hold: the
      // other four intents keep working while someone sits here.
      scopedToDating: true,
      status: "queued",
      entryTime: admin.firestore.FieldValue.serverTimestamp(),
      estimatedActivation: admin.firestore.Timestamp.fromDate(
        new Date(Date.now() + WAITLIST_ACTIVATION_DELAY_HOURS * 60 * 60 * 1000)
      ),
      activatedAt: null,
    });

    console.log(
      `[applyGenderDefaults] ${uid} waitlisted for Dating at ${schoolId} (malePct=${malePct})`
    );
  }

  await db.collection("users").doc(uid).update(updates);

  return {
    accountStatus: updates.accountStatus ?? "active",
    alertCapPerHour: updates.alertCapPerHour,
    waitlisted: updates.accountStatus === "waitlisted",
  };
});

/**
 * activateWaitlistedUsers — Scheduled function that activates users whose
 * waitlist delay has expired. Runs every 30 minutes.
 */
import { onSchedule } from "firebase-functions/v2/scheduler";

export const activateWaitlistedUsers = onSchedule(
  "every 30 minutes",
  async () => {
    const now = admin.firestore.Timestamp.now();

    const queued = await db
      .collection("waitlist")
      .where("status", "==", "queued")
      .where("estimatedActivation", "<=", now)
      .get();

    const batch = db.batch();
    let activated = 0;

    for (const doc of queued.docs) {
      const uid = doc.data().uid as string;

      // Activate in waitlist collection
      batch.update(doc.ref, {
        status: "activated",
        activatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      // Activate in user profile
      batch.update(db.collection("users").doc(uid), {
        accountStatus: "active",
        waitlistEntryTime: null,
        activationDelayHours: null,
      });

      activated++;
    }

    if (activated > 0) {
      await batch.commit();
      console.log(
        `[activateWaitlistedUsers] Activated ${activated} users from waitlist`
      );
    }
  }
);
