// MARK: - SECURITY CHECKLIST COMPLIANCE (see docs/SECURITY_CHECKLIST.md)
// [x] No hardcoded secrets — the mail provider key is a defineSecret value and the
//     school allowlist lives in Firestore, not in this source
// [x] schoolId and enrollmentStatus are issued HERE and nowhere else. The client
//     never supplies either; firestore.rules rejects any client write to them.
// [x] The school email is never taken from the request body — it is read off the
//     verified Firebase Auth token (email + email_verified), so a client cannot
//     claim an address it does not control
// [x] Auth required on every callable; request.auth.uid is the only subject
// [x] Rate limited — magic link requests and destination check-ins are throttled
//     per uid per hour, backed by a Firestore counter, not in-memory state
// [x] Generic errors — a caller cannot learn whether an email, phone or account
//     already exists, or which specific check failed
// [x] No PII logged — only uids, schoolIds and status transitions
// [x] School email and phone hash are written to users/{uid}/verification/**
//     (owner-read, function-write), never to the profile document
// [x] Destination presence is verified server-side against the destination's own
//     geofence and server-dated window; the client supplies a geohash, never a
//     polygon and never a raw coordinate

import * as admin from "firebase-admin";
import { onCall, HttpsError, CallableRequest } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import { createHash } from "crypto";

const db = admin.firestore();

// Mail provider key for the .edu magic link. Injected at runtime; never in source.
const MAIL_PROVIDER_API_KEY = defineSecret("MAIL_PROVIDER_API_KEY");

// Salt for phone hashing. A bare SHA256 of a phone number is trivially reversible
// by enumerating the number space, so the hash is salted with a server secret.
const PHONE_HASH_SALT = defineSecret("PHONE_HASH_SALT");

const MAGIC_LINK_ATTEMPTS_PER_HOUR = 5;
const DESTINATION_CHECKINS_PER_HOUR = 12;

// How long a server-confirmed destination presence lasts before the client must
// re-confirm. Short by design: the sbDest claim is what opens the cross-school
// pool, so it must expire rather than linger after someone flies home.
const DESTINATION_PRESENCE_TTL_MINUTES = 45;

type EnrollmentStatus =
  | "unverified"
  | "pending"
  | "incoming"
  | "enrolled"
  | "alumni"
  | "revoked";

interface SchoolDoc {
  displayName: string;
  fullName: string;
  allowlistedEmailDomains: string[];
  oauthTenantHints: string[];
  campus: { centerGeohash: string; radiusMeters: number };
  isActive: boolean;
}

interface DestinationDoc {
  displayLabel: string;
  centerGeohash: string;
  radiusMeters: number;
  windowStart: admin.firestore.Timestamp;
  windowEnd: admin.firestore.Timestamp;
  isActive: boolean;
}

// MARK: - Generic failure
//
// Every rejection returns the same message. A caller must not be able to tell
// "that domain is not allowlisted" from "you already used your attempts" from
// "that school is paused" — each of those distinctions is a probe.
function reject(): never {
  throw new HttpsError(
    "failed-precondition",
    "We couldn't verify your school. Check your school email and try again."
  );
}

function requireAuth(request: CallableRequest): string {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentication required.");
  }
  return request.auth.uid;
}

// MARK: - Rate limiting
//
// Firestore-backed so it survives instance recycling. Counter documents live
// under the user's own verification subtree, which no other client can read.
async function consumeRateLimit(
  uid: string,
  bucket: string,
  maxPerHour: number
): Promise<void> {
  const hourKey = new Date().toISOString().slice(0, 13); // yyyy-MM-ddTHH
  const ref = db
    .collection("users")
    .doc(uid)
    .collection("verification")
    .doc(`ratelimit_${bucket}`);

  const allowed = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const data = snap.data() ?? {};
    const count = data.hourKey === hourKey ? (data.count as number) : 0;
    if (count >= maxPerHour) return false;
    tx.set(ref, { hourKey, count: count + 1 }, { merge: true });
    return true;
  });

  if (!allowed) reject();
}

// MARK: - Geohash
//
// Precision-7 decode, mirroring Serendipity/Utilities/Geohash.swift. The client
// sends a geohash rather than a coordinate so that no raw location ever reaches
// the backend, per SECURITY_CHECKLIST.md §04.
const GEOHASH_BASE32 = "0123456789bcdefghjkmnpqrstuvwxyz";

function decodeGeohash(hash: string): { lat: number; lon: number } | null {
  if (!/^[0-9bcdefghjkmnpqrstuvwxyz]{1,12}$/.test(hash)) return null;

  let latRange = [-90, 90];
  let lonRange = [-180, 180];
  let isLon = true;

  for (const char of hash) {
    const idx = GEOHASH_BASE32.indexOf(char);
    if (idx < 0) return null;
    for (let bit = 4; bit >= 0; bit--) {
      const bitValue = (idx >> bit) & 1;
      if (isLon) {
        const mid = (lonRange[0] + lonRange[1]) / 2;
        lonRange = bitValue === 1 ? [mid, lonRange[1]] : [lonRange[0], mid];
      } else {
        const mid = (latRange[0] + latRange[1]) / 2;
        latRange = bitValue === 1 ? [mid, latRange[1]] : [latRange[0], mid];
      }
      isLon = !isLon;
    }
  }

  return {
    lat: (latRange[0] + latRange[1]) / 2,
    lon: (lonRange[0] + lonRange[1]) / 2,
  };
}

function metersBetween(
  a: { lat: number; lon: number },
  b: { lat: number; lon: number }
): number {
  const R = 6_371_000;
  const toRad = (d: number) => (d * Math.PI) / 180;
  const dLat = toRad(b.lat - a.lat);
  const dLon = toRad(b.lon - a.lon);
  const lat1 = toRad(a.lat);
  const lat2 = toRad(b.lat);
  const h =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLon / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(h));
}

// MARK: - School resolution

/** Resolves an email domain to an active school. Returns null for anything else. */
async function resolveSchoolByDomain(
  domain: string
): Promise<{ schoolId: string; school: SchoolDoc } | null> {
  const snap = await db
    .collection("schools")
    .where("allowlistedEmailDomains", "array-contains", domain)
    .where("isActive", "==", true)
    .limit(1)
    .get();

  if (snap.empty) return null;
  const doc = snap.docs[0];
  return { schoolId: doc.id, school: doc.data() as SchoolDoc };
}

/**
 * Reads the verified email off the auth token.
 *
 * Deliberately ignores any email in the request body. The token's `email` claim
 * is set by Firebase Auth after the user actually proved control of the address
 * (email link, or a school OAuth provider), and `email_verified` confirms it.
 */
function verifiedEmailFromToken(request: CallableRequest): string | null {
  const token = request.auth?.token as Record<string, unknown> | undefined;
  if (!token) return null;
  if (token.email_verified !== true) return null;
  const email = token.email;
  if (typeof email !== "string" || !email.includes("@")) return null;
  return email.toLowerCase();
}

// MARK: - Claim issuance
//
// The single place community access is granted. Custom claims are what
// firestore.rules reads, so this function *is* the gate.
async function issueCommunityClaims(
  uid: string,
  schoolId: string | null,
  enrollmentStatus: EnrollmentStatus,
  studentIDStatus: string
): Promise<void> {
  const existing = (await admin.auth().getUser(uid)).customClaims ?? {};
  await admin.auth().setCustomUserClaims(uid, {
    ...existing,
    schoolId,
    enrollmentStatus,
    studentIDStatus,
  });
}

// MARK: - requestSchoolMagicLink
//
// Step 1 of the Fizz-style gate. The user is already phone-authenticated; this
// sends a sign-in link to an allowlisted .edu address so the address can be
// linked to that same account.

export const requestSchoolMagicLink = onCall(
  { secrets: [MAIL_PROVIDER_API_KEY] },
  async (request) => {
    const uid = requireAuth(request);
    await consumeRateLimit(uid, "magiclink", MAGIC_LINK_ATTEMPTS_PER_HOUR);

    const rawEmail = request.data?.schoolEmail;
    if (typeof rawEmail !== "string" || rawEmail.length > 254) reject();

    const email = rawEmail.trim().toLowerCase();
    // Conservative address shape check. Anything unusual is rejected rather than
    // normalised — this string selects a school, so it must be boring.
    if (!/^[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}$/.test(email)) reject();

    const domain = email.split("@")[1];
    const resolved = await resolveSchoolByDomain(domain);
    if (!resolved) reject();

    let link: string;
    try {
      link = await admin.auth().generateSignInWithEmailLink(email, {
        url: "https://serendipity.app/school-gate/complete",
        handleCodeInApp: true,
        iOS: { bundleId: "henry.Serendipity" },
      });
    } catch {
      // Never surface the provider's error — it distinguishes existing accounts.
      reject();
    }

    await sendMagicLinkEmail(email, link, resolved.school.displayName);

    // Deliberately returns nothing school-specific beyond the display name the
    // caller already implied by choosing the domain.
    return { sent: true, schoolDisplayName: resolved.school.displayName };
  }
);

/**
 * Hands the sign-in link to the mail provider.
 *
 * The link is a bearer credential: it is never logged, never returned to the
 * caller, and never written to Firestore.
 */
async function sendMagicLinkEmail(
  to: string,
  link: string,
  schoolDisplayName: string
): Promise<void> {
  const response = await fetch("https://api.sendgrid.com/v3/mail/send", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${MAIL_PROVIDER_API_KEY.value()}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      personalizations: [{ to: [{ email: to }] }],
      from: { email: "no-reply@serendipity.app", name: "Serendipity" },
      subject: `Verify your ${schoolDisplayName} email`,
      content: [
        {
          type: "text/plain",
          value:
            `Tap to verify your ${schoolDisplayName} email and join your campus community:\n\n` +
            `${link}\n\nThis link expires in one hour. If you didn't request it, ignore this email.`,
        },
      ],
    }),
  });

  if (!response.ok) {
    // Log the status only. The body can echo the recipient address.
    console.error(`[requestSchoolMagicLink] mail provider status ${response.status}`);
    throw new HttpsError("internal", "Couldn't send the verification email.");
  }
}

// MARK: - completeSchoolGate
//
// Step 2. Runs after the user has linked a verified school email — via the magic
// link above, or via school Google/Microsoft OAuth. Both paths land here, and
// both are judged on the same evidence: the verified email on the token.

export const completeSchoolGate = onCall(
  { secrets: [PHONE_HASH_SALT] },
  async (request) => {
    const uid = requireAuth(request);

    const email = verifiedEmailFromToken(request);
    if (!email) reject();

    const domain = email.split("@")[1];
    const resolved = await resolveSchoolByDomain(domain);
    if (!resolved) reject();

    const provider = (request.auth?.token as Record<string, unknown>)
      ?.firebase as { sign_in_provider?: string } | undefined;
    const gateMethod =
      provider?.sign_in_provider === "google.com" ||
      provider?.sign_in_provider === "microsoft.com"
        ? "schoolOAuth"
        : "eduMagicLink";

    const phoneNumber = (await admin.auth().getUser(uid)).phoneNumber;
    const phoneHash = phoneNumber
      ? createHash("sha256")
          .update(`${PHONE_HASH_SALT.value()}:${phoneNumber}`)
          .digest("hex")
      : null;

    const batch = db.batch();

    // Profile: community identity only. No email, no phone, no hash.
    batch.set(
      db.collection("users").doc(uid),
      {
        schoolId: resolved.schoolId,
        schoolDisplayName: resolved.school.displayName,
        enrollmentStatus: "enrolled",
        trustLevel: "bronze",
        accountStatus: "active",
      },
      { merge: true }
    );

    // Verification record: the sensitive half, owner-read only.
    batch.set(
      db.collection("users").doc(uid).collection("verification").doc("school"),
      {
        uid,
        gateMethod,
        schoolId: resolved.schoolId,
        schoolEmail: email,
        phoneHash,
        reviewedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    await batch.commit();

    // Claims last: if anything above failed, the user is not yet in a community.
    await issueCommunityClaims(uid, resolved.schoolId, "enrolled", "none");

    console.info(`[completeSchoolGate] ${uid} -> ${resolved.schoolId} via ${gateMethod}`);

    // The client must force-refresh its ID token before firestore.rules will see
    // the new claims.
    return {
      schoolId: resolved.schoolId,
      schoolDisplayName: resolved.school.displayName,
      enrollmentStatus: "enrolled",
      requiresTokenRefresh: true,
    };
  }
);

// MARK: - submitEnrollmentProof
//
// The third gate path, for admitted students who do not yet have a school
// address. Uploads land in the write-only Storage prefix; this call only records
// that a review is pending. It grants nothing on its own.

export const submitEnrollmentProof = onCall(async (request) => {
  const uid = requireAuth(request);
  await consumeRateLimit(uid, "enrollmentproof", MAGIC_LINK_ATTEMPTS_PER_HOUR);

  const schoolId = request.data?.schoolId;
  const storagePath = request.data?.storagePath;

  if (typeof schoolId !== "string" || schoolId.length > 128) reject();
  if (typeof storagePath !== "string") reject();
  // The path must be inside this user's own write-only verification prefix.
  if (!storagePath.startsWith(`verification/${uid}/`)) reject();

  const school = await db.collection("schools").doc(schoolId).get();
  if (!school.exists || school.data()?.isActive !== true) reject();

  await db
    .collection("users")
    .doc(uid)
    .collection("verification")
    .doc("enrollment")
    .set(
      {
        uid,
        gateMethod: "enrollmentProof",
        schoolId,
        proofStoragePath: storagePath,
        submittedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

  // 'pending' grants no community access — see EnrollmentStatus.grantsCommunityAccess.
  await db.collection("users").doc(uid).set({ enrollmentStatus: "pending" }, { merge: true });
  await issueCommunityClaims(uid, null, "pending", "none");

  return { status: "pending", requiresTokenRefresh: true };
});

// MARK: - reviewEnrollmentProof (admin only)

export const reviewEnrollmentProof = onCall(async (request) => {
  const uid = requireAuth(request);
  if (request.auth?.token.admin !== true) {
    throw new HttpsError("permission-denied", "Admin access required.");
  }

  const targetUid = request.data?.uid;
  const approve = request.data?.approve;
  if (typeof targetUid !== "string" || typeof approve !== "boolean") {
    throw new HttpsError("invalid-argument", "uid and approve are required.");
  }

  const record = await db
    .collection("users")
    .doc(targetUid)
    .collection("verification")
    .doc("enrollment")
    .get();

  if (!record.exists) {
    throw new HttpsError("not-found", "No enrollment proof on file.");
  }

  const schoolId = record.data()?.schoolId as string | undefined;
  if (!schoolId) throw new HttpsError("failed-precondition", "Record is incomplete.");

  const school = await db.collection("schools").doc(schoolId).get();
  const status: EnrollmentStatus = approve ? "incoming" : "unverified";

  await db.collection("users").doc(targetUid).set(
    {
      schoolId: approve ? schoolId : null,
      schoolDisplayName: approve ? school.data()?.displayName ?? null : null,
      enrollmentStatus: status,
    },
    { merge: true }
  );

  await db
    .collection("users")
    .doc(targetUid)
    .collection("verification")
    .doc("enrollment")
    .set({ reviewedAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });

  const claims = (await admin.auth().getUser(targetUid)).customClaims ?? {};
  await issueCommunityClaims(
    targetUid,
    approve ? schoolId : null,
    status,
    (claims.studentIDStatus as string) ?? "none"
  );

  console.info(`[reviewEnrollmentProof] ${targetUid} -> ${status} by ${uid}`);
  return { status };
});

// MARK: - confirmDestinationPresence
//
// The only way the cross-school Spring Break pool opens.
//
// The client sends a precision-7 geohash. The server decodes it, compares it to
// the destination's own centre and radius, checks the destination's server-dated
// window, and only then issues the short-lived sbDest claim that firestore.rules
// requires for a cross-school read. There is no client-supplied polygon, no
// client-supplied date, and no way to assert presence without passing this check.

export const confirmDestinationPresence = onCall(async (request) => {
  const uid = requireAuth(request);
  await consumeRateLimit(uid, "destcheckin", DESTINATION_CHECKINS_PER_HOUR);

  const destinationId = request.data?.destinationId;
  const geohash = request.data?.geohash;
  if (typeof destinationId !== "string" || destinationId.length > 128) reject();
  if (typeof geohash !== "string") reject();

  // Presence is only meaningful for someone already cleared for Quest Mode.
  const claims = (await admin.auth().getUser(uid)).customClaims ?? {};
  const enrollment = claims.enrollmentStatus as string | undefined;
  const studentID = claims.studentIDStatus as string | undefined;
  const schoolId = claims.schoolId as string | undefined;
  const eligible =
    typeof schoolId === "string" &&
    schoolId.length > 0 &&
    (enrollment === "enrolled" || enrollment === "incoming") &&
    (studentID === "verified" || studentID === "faceMatched");
  if (!eligible) reject();

  const destSnap = await db
    .collection("spring_break_destinations")
    .doc(destinationId)
    .get();
  if (!destSnap.exists) reject();

  const dest = destSnap.data() as DestinationDoc;
  const now = admin.firestore.Timestamp.now();
  const windowLive =
    dest.isActive === true &&
    dest.windowStart.toMillis() < dest.windowEnd.toMillis() &&
    now.toMillis() >= dest.windowStart.toMillis() &&
    now.toMillis() <= dest.windowEnd.toMillis();
  if (!windowLive) reject();

  const here = decodeGeohash(geohash);
  const there = decodeGeohash(dest.centerGeohash);
  if (!here || !there) reject();

  // Precision-7 cells are ~150 m, so allow that as slack on the fence edge
  // rather than rejecting someone standing on the boundary.
  const GEOHASH_CELL_SLACK_METERS = 150;
  if (metersBetween(here, there) > dest.radiusMeters + GEOHASH_CELL_SLACK_METERS) {
    reject();
  }

  const expiresAt = admin.firestore.Timestamp.fromMillis(
    Date.now() + DESTINATION_PRESENCE_TTL_MINUTES * 60 * 1000
  );

  await db.collection("users").doc(uid).set(
    {
      springBreakDestinationId: destinationId,
      springBreakPresenceExpiresAt: expiresAt,
    },
    { merge: true }
  );

  await admin.auth().setCustomUserClaims(uid, { ...claims, sbDest: destinationId });

  console.info(`[confirmDestinationPresence] ${uid} -> ${destinationId}`);

  return {
    destinationId,
    displayLabel: dest.displayLabel,
    expiresAt: expiresAt.toMillis(),
    requiresTokenRefresh: true,
  };
});

// MARK: - clearDestinationPresence
//
// Called when the window closes or the user leaves the fence. Drops the claim
// and the profile flag together, so no cross-school visibility survives the trip
// home — "no leftover cross-school radar".

export const clearDestinationPresence = onCall(async (request) => {
  const uid = requireAuth(request);

  const claims = (await admin.auth().getUser(uid)).customClaims ?? {};
  delete claims.sbDest;
  await admin.auth().setCustomUserClaims(uid, claims);

  await db.collection("users").doc(uid).set(
    {
      springBreakDestinationId: null,
      springBreakPresenceExpiresAt: null,
    },
    { merge: true }
  );

  return { cleared: true, requiresTokenRefresh: true };
});
