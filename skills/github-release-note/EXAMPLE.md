# Nexus API — Release Notes

## v2.4.0

[v2.3.1...v2.4.0](https://github.com/acme/nexus-api/compare/v2.3.1...v2.4.0) — 2026-02-28

**32 commits** · 47 files changed · +1,842 / −613 lines

## Executive summary

This release introduces **passkey authentication (WebAuthn)**, reduces search response time by **42%** with a new composite index, and fixes a critical security flaw in JWT token validation. The onboarding flow now supports **batch email invitations**, addressing the most voted request on the public roadmap.

## Breaking changes

> [!IMPORTANT]
> **`POST /auth/token` now returns `access_token` instead of `token`.**
> Clients reading the `token` field from the response must update to `access_token`. The old field will be removed in v3.0.
>
> **Removal of the `X-Legacy-Auth` header.**
> The legacy authentication header, deprecated since v2.0, is no longer accepted. Use the `Authorization: Bearer <token>` header instead.

## New Features

- **Passkey authentication (WebAuthn)** — users can register biometric keys and log in without a password. Compatible with Touch ID, Windows Hello, and YubiKey. ([#312](https://github.com/acme/nexus-api/issues/312))
- **Batch email invitations** — administrators can invite up to 200 users per request via `POST /invites/batch`, with a customizable email template. ([#287](https://github.com/acme/nexus-api/issues/287))
- **Billing event webhooks** — new events `invoice.paid`, `invoice.failed`, and `subscription.canceled` available in the webhooks API. ([#301](https://github.com/acme/nexus-api/issues/301))

## Performance

- **User search 42% faster** — new composite index on `(org_id, email)` reduced p95 from 320ms to 185ms.
- **Server startup 28% faster** — lazy-loading of report modules eliminated 1.2s from cold start.

## Refactors

- **Rate-limiting middleware extracted to internal package** (`@acme/rate-limiter`) — no change to the public API; enables reuse across other services.
- **Migrated callbacks to async/await** in webhook handlers — reduces stack trace depth by ~4 levels.

## Bug Fixes

- **Pagination returned duplicate records** when items were inserted between page requests. Now uses a stable cursor based on `created_at + id`. ([#298](https://github.com/acme/nexus-api/issues/298))
- **Avatar upload failed silently** for WebP images over 2 MB — the limit is now validated and returns `413 Payload Too Large` with an explanatory message. ([#305](https://github.com/acme/nexus-api/issues/305))
- **Password reset email sent in wrong language** when the browser locale differed from the account locale. Now respects the account locale. ([#310](https://github.com/acme/nexus-api/issues/310))

## Security

- **[CRITICAL] Insufficient JWT validation** — tokens with a missing `aud` claim were accepted, allowing cross-tenant usage. Fixed with strict `aud` and `iss` validation. (CVE-2026-10432, [#314](https://github.com/acme/nexus-api/issues/314))
- **[MEDIUM] Stack trace exposure in 500 responses** — in production mode, internal errors now return only `request_id` without implementation details. ([#309](https://github.com/acme/nexus-api/issues/309))

## Tests

- Overall coverage: 78% → **83%** (+5pp).
- 34 new integration tests for the passkey flow.
- Added load test with k6 simulating 500 req/s on the search endpoint.

## Infrastructure

- **Node.js** updated from 20.11 to 22.14 (LTS).
- **Dockerfile** migrated to multi-stage build — production image reduced from 1.1 GB to 340 MB.
- **CI** — pipeline now runs linting, tests, and build in parallel, reducing duration from 8min to 3min.

## Dependencies

| Package | Previous | Current | Type |
| :--- | :--- | :--- | :--- |
| `fastify` | 4.26.1 | 5.2.0 | production |
| `@simplewebauthn/server` | — | 11.0.0 | production |
| `zod` | 3.22.4 | 3.24.2 | production |
| `vitest` | 1.6.0 | 3.0.5 | dev |
| `@types/node` | 20.11.5 | 22.13.0 | dev |

## Documentation

- `docs/auth/passkeys.md` — passkey integration guide, including frontend examples.
- `docs/api/webhooks.md` — documentation for new billing events.
- `docs/migration/v2.3-to-v2.4.md` — migration guide for breaking changes.
- `README.md` — coverage badge updated.

## Contributors

- [@jsilva](https://github.com/jsilva) — passkey authentication
- [@mcosta](https://github.com/mcosta) — batch invitations and load tests
- [@lfernandes](https://github.com/lfernandes) — JWT security fix
- [@aduarte](https://github.com/aduarte) — Docker and CI migration

---

<https://github.com/acme/nexus-api/compare/v2.3.1...v2.4.0>
