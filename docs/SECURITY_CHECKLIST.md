# Vibe Coding Security Checklist

Security is the #1 priority — never compromise it for speed, simplicity, or "vibe". Before writing ANY code, during planning, and in every response that includes or modifies code, systematically follow and enforce this checklist.

## 01 — Secrets & Config

- Never hardcode secrets, tokens, API keys, passwords, or credentials in code — ever. Use environment variables ONLY.
- Never log, print, or return secrets in errors, logs, responses, or debugging output.
- Never commit .env, .env.local, .env.example (with real values), or any secret-containing files to git.
- Client-side code MUST NOT contain server-only secrets or API keys. Proxy ALL sensitive API calls through your backend.
- Never make CORS overly permissive (no "*"); use specific origins and credentials: 'include' only when necessary.
- Scan dependencies for known vulnerabilities (npm audit / pip check / etc.) and prefer well-maintained, secure libraries.
- Remove all default/example credentials, debug modes, dev tools, or console.log in production builds.

## 02 — Access & API

- EVERY route, page, endpoint, or data access MUST require proper authentication & authorization — no exceptions for "convenience".
- Prevent IDOR / insecure direct object references: always verify the requesting user owns or is authorized for the resource (NEVER trust ID from URL/params/client).
- Store tokens securely on client (HttpOnly, Secure, SameSite=Strict/Lax cookies preferred over localStorage).
- Never let login/reset flows leak whether an account exists (use generic "invalid credentials" messages).
- Apply strict rate limiting to ALL auth, password reset, OTP, and public endpoints.
- Never expose internal details, stack traces, paths, versions, or database errors in responses (use generic error messages).
- Return minimal data only — never over-fetch or leak extra user records.
- Require confirmation steps (are you sure? / re-enter password / email verification) for delete, email change, password change, payment actions, etc.
- Protect admin/superuser routes with proper role checks — never rely on URL obscurity.

## 03 — User Input

- NEVER trust user input. Sanitize, validate, and escape EVERYWHERE.
- Use parameterized queries / ORM safe methods — NO string concatenation in SQL/NoSQL queries (prevent injection).
- Prevent XSS: escape output, use CSP headers, never use dangerouslySetInnerHTML/raw HTML from user input without sanitization (DOMPurify etc.).
- Validate file uploads: strict MIME type checks, size limits, store outside web root, serve via signed URLs.
- Never allow client-side logic to control payments, billing, credits, or money-related actions — re-validate EVERYTHING server-side.

## Additional Hard Rules

- Follow OWASP Top 10 / Cheat Sheet best practices by default.
- Use secure defaults: HTTPS-only, secure cookies, bcrypt/Argon2 for passwords, up-to-date crypto.
- Add security-relevant comments in code explaining decisions (e.g. "// Parameterized to prevent SQL injection").
- If something in the task conflicts with this checklist, STOP and ask for clarification BEFORE proceeding.
- After generating code, explicitly review it against this checklist and list any violations + fixes.
- When planning features or architecture, propose designs that inherently satisfy this checklist.
