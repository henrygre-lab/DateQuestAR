# Vibe Coding Security Checklist

Security is the #1 priority — never compromise it for speed, simplicity, or "vibe". Before writing ANY code, during planning, and in every response that includes or modifies code, follow and enforce this checklist. All Serendipity source files begin with a `// MARK: - SECURITY CHECKLIST COMPLIANCE` block citing which items apply.

---

## 01 — Secrets & Config

- Never hardcode secrets, tokens, API keys, passwords, or credentials — use environment variables or Firebase Remote Config.
- Never log, print, or return secrets in errors, logs, or debug output.
- Never commit `GoogleService-Info.plist`, `.env`, or any file containing real values.
- Client-side code must not contain server-only secrets — proxy all sensitive API calls through backend (Cloud Functions).
- Scan dependencies for known vulnerabilities (`npm audit`, Swift Package audit) and prefer well-maintained libraries.
- Remove all debug modes, dev tools, and `console.log` / `print` statements that expose internals in production builds.

## 02 — Access & API

- Every Firestore read/write must require authentication — no anonymous writes to user-owned documents.
- Prevent IDOR: always verify the requesting user owns or is authorized for the resource. Never trust document IDs from the client.
- Apply Firestore Security Rules as the authoritative enforcement layer; client-side checks are advisory only.
- Never let login/reset flows leak whether an account exists — use generic "invalid credentials" messages.
- Apply strict rate limiting to all auth, OTP, and public Cloud Function endpoints.
- Never expose stack traces, internal paths, or database error details in responses.
- Return minimal data — never over-fetch or leak extra user records. Use `updateData` (not `setData`) to avoid overwriting server-authoritative fields.
- Require explicit confirmation for delete, account change, and report actions.
- Protect admin routes with proper role checks — never rely on URL obscurity.

## 03 — User Input

- Never trust user input. Sanitize, validate, and escape everywhere.
- Use Firestore's typed SDK methods — no string concatenation in queries.
- Validate all user-supplied data server-side via Cloud Functions before acting on it (XP grants, waitlist activations, referral rewards, trust score updates).
- Never allow client-side logic to control final alert cap enforcement, trust score, or account status — server is always authoritative.
- Clamp all numeric values to valid ranges before storing (e.g., `revealProgress` 0.0–1.0, `balanceBoostMultiplier`, alert caps).

## 04 — iOS-Specific Rules

- Never store tokens, session data, or sensitive values in `UserDefaults` — use Keychain (`SecItem`) for anything sensitive.
- `LocalAuthentication` (Face ID / Touch ID) is a UI gate only. Re-validate auth state via Firebase on the server side after biometric unlock.
- All background modes declared in `Info.plist` must be used by real, shipping code — no unused entitlements.
- `NearbyInteraction` discovery tokens must not be persisted — generate per-session and discard after the session closes.
- Raw `CLLocation` coordinates are never stored in Firestore — encode to geohash precision 7 (`Geohash.swift`) before any write.
- ARKit camera sessions must terminate when the app enters the background — no background camera access.
- All analytics events must pass through `AnalyticsService` — raw UIDs are SHA256-hashed before logging; no PII in event parameters.
- `GoogleService-Info.plist` is excluded from git via `.gitignore` — reviewers must supply their own Firebase project config.

## 05 — Additional Hard Rules

- Follow OWASP Top 10 / Cheat Sheet best practices by default.
- Use secure defaults: HTTPS-only, secure cookies, bcrypt/Argon2 for passwords, up-to-date crypto.
- Add security-relevant comments in code explaining non-obvious decisions (e.g., why `updateData` instead of `setData`).
- If a task conflicts with this checklist, stop and ask for clarification before proceeding.
- After generating code, review it against this checklist and list any violations and fixes.
- When planning features or architecture, propose designs that satisfy this checklist from the start.
