# Commit Message Examples

Default to subject-only. A body is the exception, not the rule. Keep bodies ≤ 4 lines / ≤ 350 chars, single paragraph, wrap at 72.

## 1. Simple fix (subject-only — preferred)

```bash
fix(auth): prevent session expiration on token refresh
```

## 2. Feature where the "why" is non-obvious

```bash
feat(api): add batch endpoint for user invitations

Single-call onboarding cuts client round-trips from N to 1; the
existing per-invite endpoint stays for backward compatibility.
```

## 3. Breaking change (subject + minimal body + footer)

```bash
feat(auth)!: replace session-based auth with JWT tokens

Removes the Redis session dependency and unblocks horizontal
scaling. Existing sessions are invalidated on deploy.

BREAKING CHANGE: /auth/login returns a JWT instead of setting a
session cookie. Clients must send Authorization: Bearer.

Refs: #245, #312
```

## 4. Refactor (subject-only — diff speaks for itself)

```bash
refactor(db): extract query builders into dedicated modules
```

## 5. Documentation

```bash
docs: add API authentication guide to README
```

## 6. Chore without scope

```bash
chore: upgrade eslint to v9 and update config format
```

## 7. Performance with measured impact

```bash
perf(worker): cache product catalog queries

Cuts catalog read latency from ~500ms to ~50ms (Redis-backed).
```

## Anti-patterns — do NOT write commits like this

The body below restates the diff, enumerates files, and ends with a question. Replace with subject-only or a short paragraph.

### Too long (avoid)

```bash
fix(obsidian-brain): force phase 1 bootstrap question on session start

Phase 1 was deferring indefinitely in auto mode and never firing. The
"first natural pause" fallback created a circular dependency: Phase 3
write triggers can only fire if the brain is already bootstrapped, and
Phase 4 end-of-session sync assumed an existing index, so neither
could wake the deferred bootstrap question.

Three coordinated changes:

- Hook digest now branches on index existence...
- SKILL.md Phase 1 timing rule rewritten...
- SKILL.md Phase 4 gains a step 0 entry guard...

references/SESSION_LIFECYCLE.md mirrored to stay in sync.

Confirma?
```

### Right size (prefer)

```bash
fix(obsidian-brain): force phase 1 bootstrap on session start

The "first natural pause" deferral never fired in auto mode, so
brains were never created for new projects. Hook now emits the
bootstrap question eagerly when the index is missing.
```
