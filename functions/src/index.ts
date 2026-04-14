// MARK: - Vibe Coding Security Checklist Compliance
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

// MARK: - Identity Verification (Persona/Onfido Proxy)
export {
  createVerificationSession,
  onVerificationComplete,
} from "./identityVerification";

// MARK: - One-Time Migration (Admin Only)
export { migrateUserProfiles } from "./migrateUserProfiles";
