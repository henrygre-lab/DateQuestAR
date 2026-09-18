// MARK: - SECURITY CHECKLIST COMPLIANCE (see docs/SECURITY_CHECKLIST.md)
// [x] No hardcoded secrets — Persona/Onfido API key stored in Firebase Secret Manager
// [x] API key accessed via defineSecret(), never exposed to client
// [x] Client sends only their UID + inquiry reference — no raw ID images transit through us
// [x] Proxy returns minimal data: {verificationStatus, trustScoreDelta, badge} only
// [x] Never writes trustLevel — the campus tier is promoted only by
//     studentIdVerification.ts. This function cannot mint gold.
// [x] Auth required — request.auth.uid must match the target UID
// [x] Rate limited — max 3 verification attempts per hour per user
// [x] No PII logged — only UID and status transitions

import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";

const db = admin.firestore();

// Secret references — values injected at runtime by Cloud Functions,
// never visible in source code or client bundles
const PERSONA_API_KEY = defineSecret("PERSONA_API_KEY");
const PERSONA_TEMPLATE_ID = defineSecret("PERSONA_TEMPLATE_ID");

// Rate limit: max verification attempts per hour
const MAX_ATTEMPTS_PER_HOUR = 3;

interface VerificationResult {
  verificationStatus: "verified" | "pending" | "flagged" | "unverified";
  trustScoreDelta: number;
  badge: string | null;
}

/**
 * createVerificationSession — Creates a Persona verification session.
 * Client calls this to get a session token, then opens the Persona SDK.
 * The API key NEVER leaves the server.
 */
export const createVerificationSession = onCall(
  { secrets: [PERSONA_API_KEY, PERSONA_TEMPLATE_ID] },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }

    const uid = request.auth.uid;

    // Rate limiting check
    const isAllowed = await checkRateLimit(uid);
    if (!isAllowed) {
      throw new HttpsError(
        "resource-exhausted",
        "Too many verification attempts. Try again later."
      );
    }

    // Creates the inquiry server-side so the API key never reaches a client.
    // The iOS client is not wired to open the returned inquiry — see the TODO in
    // SafetyVerifier.verifyIdentity() — so this path is dormant in the shipping
    // app rather than unimplemented here.
    const apiKey = PERSONA_API_KEY.value();
    const templateId = PERSONA_TEMPLATE_ID.value();

    try {
      const response = await fetch("https://withpersona.com/api/v1/inquiries", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${apiKey}`,
          "Content-Type": "application/json",
          "Persona-Version": "2023-01-05",
        },
        body: JSON.stringify({
          data: {
            attributes: {
              "inquiry-template-id": templateId,
              "reference-id": uid, // Link inquiry to our user
            },
          },
        }),
      });

      if (!response.ok) {
        console.error(
          `[createVerificationSession] Persona API error: ${response.status}`
        );
        throw new HttpsError("internal", "Verification service unavailable.");
      }

      const inquiry = (await response.json()) as {
        data?: { id?: string; attributes?: { status?: string } };
      };

      // Record the attempt
      await recordVerificationAttempt(uid);

      // Update user status to pending
      await db.collection("users").doc(uid).update({
        verificationStatus: "pending",
      });

      // Return only the session ID — no API keys or PII
      return {
        inquiryId: inquiry.data?.id,
        status: "pending",
      };
    } catch (error) {
      if (error instanceof HttpsError) throw error;
      console.error(`[createVerificationSession] Error: ${error}`);
      throw new HttpsError("internal", "Verification service unavailable.");
    }
  }
);

/**
 * onVerificationComplete — Webhook handler for Persona/Onfido callbacks.
 * Called by the verification provider when an inquiry completes.
 * Returns minimal data to the client: status, trust delta, badge.
 */
export const onVerificationComplete = onCall(
  { secrets: [PERSONA_API_KEY] },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }

    const uid = request.auth.uid;
    const inquiryId = request.data?.inquiryId as string | undefined;

    if (!inquiryId) {
      throw new HttpsError("invalid-argument", "Missing inquiryId.");
    }

    // Verify the inquiry status with Persona API (server-to-server)
    const apiKey = PERSONA_API_KEY.value();

    try {
      const response = await fetch(
        `https://withpersona.com/api/v1/inquiries/${inquiryId}`,
        {
          headers: {
            Authorization: `Bearer ${apiKey}`,
            "Persona-Version": "2023-01-05",
          },
        }
      );

      if (!response.ok) {
        throw new HttpsError("internal", "Verification lookup failed.");
      }

      const inquiry = (await response.json()) as {
        data?: {
          attributes?: { status?: string; "reference-id"?: string };
        };
      };
      const inquiryStatus = inquiry.data?.attributes?.status;
      const referenceId = inquiry.data?.attributes?.["reference-id"];

      // Security: ensure the inquiry belongs to the requesting user
      if (referenceId !== uid) {
        throw new HttpsError(
          "permission-denied",
          "Inquiry does not belong to this user."
        );
      }

      // Map Persona status to our verification model
      const result = mapPersonaStatus(inquiryStatus ?? "unknown");

      // Update user profile with verification result
      const userRef = db.collection("users").doc(uid);
      const updateData: Record<string, unknown> = {
        verificationStatus: result.verificationStatus,
        trustScore: admin.firestore.FieldValue.increment(
          result.trustScoreDelta
        ),
      };

      // Deliberately no trustLevel write. The campus tier is promoted in exactly
      // one place — studentIdVerification.ts, on the student ID card photo
      // (silver) and the ID-to-liveness face match (gold). A third-party identity
      // check is a useful extra signal, not a campus enrolment proof, so it moves
      // verificationStatus and trustScore and stops there. Minting gold here
      // would hand out the Dating and NameDrop gates on evidence the campus
      // model never asked for.
      if (result.verificationStatus === "verified") {
        updateData.verificationCompletedAt =
          admin.firestore.FieldValue.serverTimestamp();
      }

      await userRef.update(updateData);

      // Return minimal result — no raw Persona data exposed
      return result;
    } catch (error) {
      if (error instanceof HttpsError) throw error;
      console.error(`[onVerificationComplete] Error: ${error}`);
      throw new HttpsError("internal", "Verification processing failed.");
    }
  }
);

/**
 * Maps Persona inquiry status to our internal verification result.
 */
function mapPersonaStatus(personaStatus: string): VerificationResult {
  switch (personaStatus) {
    case "completed":
    case "approved":
      return {
        verificationStatus: "verified",
        trustScoreDelta: 0.2,
        badge: "id_verified",
      };
    case "needs_review":
    case "pending":
      return {
        verificationStatus: "pending",
        trustScoreDelta: 0,
        badge: null,
      };
    case "failed":
    case "declined":
      return {
        verificationStatus: "flagged",
        trustScoreDelta: -0.1,
        badge: null,
      };
    default:
      return {
        verificationStatus: "unverified",
        trustScoreDelta: 0,
        badge: null,
      };
  }
}

/**
 * Rate limiting: tracks verification attempts per user per hour.
 * Stored in a subcollection to avoid polluting the user profile.
 */
async function checkRateLimit(uid: string): Promise<boolean> {
  const oneHourAgo = new Date(Date.now() - 60 * 60 * 1000);
  const attempts = await db
    .collection("users")
    .doc(uid)
    .collection("verification_attempts")
    .where("timestamp", ">", admin.firestore.Timestamp.fromDate(oneHourAgo))
    .count()
    .get();

  return (attempts.data().count ?? 0) < MAX_ATTEMPTS_PER_HOUR;
}

async function recordVerificationAttempt(uid: string): Promise<void> {
  await db
    .collection("users")
    .doc(uid)
    .collection("verification_attempts")
    .add({
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
    });
}
