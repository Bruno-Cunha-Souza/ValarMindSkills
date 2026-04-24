# Caveman Commit — Examples

## 1. Simple fix, no body

```bash
fix(auth): prevent session expiry on refresh
```

## 2. Feature, no body

```bash
feat(api): add batch invite endpoint
```

## 3. Refactor with non-obvious why (body earned)

```bash
refactor(db): extract query builders

- cuts duplication across 12 repos
- unblocks the v2 migration path
```

## 4. Breaking change with footer

```bash
feat(auth)!: replace sessions with JWT

BREAKING CHANGE: /auth/login now returns a bearer token instead of setting a cookie.
Refs: #245
```

## 5. Perf

```bash
perf(worker): cache product catalog
```

## 6. Docs

```bash
docs: add API auth guide to README
```

## 7. Chore

```bash
chore: upgrade eslint to v9
```

---

## Counter-example — body not earned

Diff adds a missing import. Do **not** write:

```bash
fix(ui): add missing import

The missing import was causing a runtime error, so I added it.
```

Write:

```bash
fix(ui): add missing Button import
```

The *why* is obvious from the subject; a body only adds noise.
