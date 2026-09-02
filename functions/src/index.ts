// MARK: - SECURITY CHECKLIST COMPLIANCE (see docs/SECURITY_CHECKLIST.md)
// [x] No hardcoded secrets in this file — all secrets managed via defineSecret()
// [x] Admin SDK initialized once at top level
// [x] All exports are typed Cloud Functions — no raw Express endpoints

import * as admin from "firebase-admin";

// Initialize Admin SDK — uses service account from environment, not hardcoded keys
admin.initializeApp();

// MARK: - Balance Monitoring (Scheduled)
export { balanceMonitor } from "./balanceMonitor";

// MARK: - User Signup & Gender Defaults
export {
  onUserSignup,
  applyGenderDefaults,
  activateWaitlistedUsers,
} from "./onUserSignup";

// MARK: - School Gate (Fizz-style: phone + .edu magic link / OAuth / enrollment proof)
// Issues schoolId and enrollmentStatus. The client never self-promotes.
export {
  requestSchoolMagicLink,
  completeSchoolGate,
  submitEnrollmentProof,
  reviewEnrollmentProof,
  confirmDestinationPresence,
  clearDestinationPresence,
} from "./schoolGate";

// MARK: - Student ID + Liveness (Quest Mode, Dating and NameDrop gates)
export {
  submitStudentIDVerification,
  revokeStudentIDVerification,
} from "./studentIdVerification";

// MARK: - Intents (server-owned; Dating-off starts the 24h cooldown)
export { setActiveIntents } from "./intents";

// MARK: - Identity Verification (Persona/Onfido Proxy)
export {
  createVerificationSession,
  onVerificationComplete,
} from "./identityVerification";

// MARK: - One-Time Migration (Admin Only)
export { migrateUserProfiles } from "./migrateUserProfiles";
