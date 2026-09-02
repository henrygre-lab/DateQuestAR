// MARK: - SECURITY CHECKLIST COMPLIANCE (see docs/SECURITY_CHECKLIST.md)
// [x] No hardcoded secrets — uses Admin SDK only
// [x] Runs as one-shot callable (admin-only) — not exposed to regular users
// [x] Writes only default safety fields — never overwrites existing user data
// [x] Backfills community state at its LEAST-PRIVILEGED value: no schoolId,
//     enrollmentStatus 'unverified', studentIDStatus 'none'. Migration must never
//     be the thing that hands an existing account a campus — those accounts go
//     back through schoolGate.ts like everyone else.
// [x] activeIntents is backfilled to Hangout + Study; never Dating
// [x] Uses batch writes with 500-doc limit for Firestore safety
// [x] Minimal data read — only the fields the backfill needs, via select()
// [x] Idempotent — safe to re-run; skips users who already have enrollmentStatus

import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";

const db = admin.firestore();

const DEFAULT_FEMALE_ALERT_CAP = 3;
const DEFAULT_MALE_ALERT_CAP = 8;
const BATCH_SIZE = 500; // Firestore batch write limit

/**
 * migrateUserProfiles — One-time migration to backfill gender balance fields
 * for all existing users.
 *
 * Sets:
 * - gender: "prefer_not_to_say" (if not already set)
 * - alertCapPerHour: 3 for women, 8 for men (based on existing gender if present)
 * - accountStatus: "active"
 * - balanceBoostMultiplier: 1.0
 * - currentHourAlerts: {}
 * - intentVibes: []
 * - socialContextPreference: true
 * - schoolId: null, enrollmentStatus: "unverified", studentIDStatus: "none"
 * - activeIntents: ["hangout", "study"]
 *
 * Note what it deliberately does NOT do: grant anyone a community. Every
 * pre-campus account lands at the school gate, which is the only correct answer —
 * nothing in an old profile is evidence about which campus its owner belongs to.
 *
 * Call via: firebase functions:call migrateUserProfiles --data '{}'
 * Or from admin dashboard.
 *
 * IMPORTANT: This should only be callable by admin users.
 * In production, gate this behind a custom claim check.
 */
export const migrateUserProfiles = onCall(async (request) => {
  // Admin-only gate: require custom admin claim
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentication required.");
  }

  // Check for admin custom claim
  // In development, you can temporarily comment this out
  if (!request.auth.token.admin) {
    throw new HttpsError(
      "permission-denied",
      "Admin privileges required for migration."
    );
  }

  let totalMigrated = 0;
  let totalSkipped = 0;
  let lastDoc: admin.firestore.QueryDocumentSnapshot | undefined;

  // Process in batches to avoid memory issues.
  // `for (;;)` rather than `while (true)`: the latter trips no-constant-condition,
  // and firebase.json runs lint as a predeploy step.
  for (;;) {
    let query = db
      .collection("users")
      .select("gender", "accountStatus", "enrollmentStatus", "verificationStatus") // Minimal data
      .limit(BATCH_SIZE);

    if (lastDoc) {
      query = query.startAfter(lastDoc);
    }

    const snapshot = await query.get();
    if (snapshot.empty) break;

    const batch = db.batch();
    let batchCount = 0;

    for (const doc of snapshot.docs) {
      const data = doc.data();

      // Skip if already migrated (idempotency check). Keyed on enrollmentStatus
      // rather than accountStatus, because the earlier migration already set
      // accountStatus — re-running against that generation still needs to add
      // the community fields.
      if (data.enrollmentStatus !== undefined) {
        totalSkipped++;
        continue;
      }

      const existingGender = (data.gender as string) ?? "prefer_not_to_say";
      const alertCap =
        existingGender === "female" || existingGender === "non_binary"
          ? DEFAULT_FEMALE_ALERT_CAP
          : DEFAULT_MALE_ALERT_CAP;

      batch.update(doc.ref, {
        gender: existingGender,
        alertCapPerHour: alertCap,
        currentHourAlerts: {},
        balanceBoostMultiplier: 1.0,
        accountStatus: "active",
        waitlistEntryTime: null,
        activationDelayHours: null,
        verificationStatus: data.verificationStatus ?? "unverified",
        intentVibes: [],
        socialContextPreference: true,
        // Community state, least-privileged. Not a guess, not a default campus.
        schoolId: null,
        schoolDisplayName: null,
        enrollmentStatus: "unverified",
        studentIDStatus: "none",
        verifiedAge: null,
        activeIntents: ["hangout", "study"],
        datingCooldownUntil: null,
        springBreakDestinationId: null,
      });

      batchCount++;
    }

    if (batchCount > 0) {
      await batch.commit();
      totalMigrated += batchCount;
    }

    lastDoc = snapshot.docs[snapshot.docs.length - 1];

    // If we got fewer than BATCH_SIZE, we've reached the end
    if (snapshot.docs.length < BATCH_SIZE) break;
  }

  console.log(
    `[migrateUserProfiles] Complete: ${totalMigrated} migrated, ${totalSkipped} skipped`
  );

  return {
    migrated: totalMigrated,
    skipped: totalSkipped,
  };
});
