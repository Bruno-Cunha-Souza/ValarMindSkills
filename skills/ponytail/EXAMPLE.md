# Ponytail Mode — Before / After

Same request answered at each level, so the caller can compare the ladder in action.

---

## Request

> "We need to debounce the search input so we don't hammer the API on every keystroke."

---

## Normal (no ponytail)

Great idea! Debouncing is a common pattern. I'll create a reusable `useDebounce` hook with configurable delay, a `DebouncedInput` wrapper component so we can reuse it across forms, and add `lodash.debounce` as a dependency since it handles edge cases like `maxWait` and cancellation:

```bash
npm install lodash.debounce
```

```ts
// hooks/useDebounce.ts — 28 lines
// components/DebouncedInput.tsx — 41 lines
```

We should also discuss whether to debounce on the trailing or leading edge…

---

## `/ponytail lite`

Added the `useDebounce` hook as asked.

FYI: a `setTimeout` + `clearTimeout` inside the existing `useEffect` covers this in 4 lines with zero deps — say the word and I'll swap it.

---

## `/ponytail full` (default)

```ts
useEffect(() => {
  const t = setTimeout(() => search(query), 300);
  return () => clearTimeout(t);
}, [query]);
```

Skipped: `lodash.debounce` (rung 5 fails — not installed, not needed), wrapper component. Add a shared hook when a second consumer exists.

---

## `/ponytail ultra`

Does search need to fire while typing at all? Form submit + Enter key = zero requests until intent.

If live search is a real requirement:

```ts
useEffect(() => {
  const t = setTimeout(() => search(query), 300);
  return () => clearTimeout(t);
}, [query]);
```

`lodash.debounce` for this is a dependency with a hit rate.

---

## Guardrail override (laziness never cuts a trust boundary)

### Request

> "Make this upload endpoint as short as possible."

### Reply

> ```ts
> app.post("/upload", async (req, res) => {
>   if (!ALLOWED_TYPES.has(req.file?.mimetype)) return res.sendStatus(415); // trust boundary — stays
>   if (req.file.size > MAX_BYTES) return res.sendStatus(413);              // stays
>   await store.put(req.file);
>   res.sendStatus(201);
> });
> ```
>
> Shortened everything except type/size validation — trust-boundary checks are never on the chopping block.

---

## `ponytail:` comment + minimum check (non-trivial logic keeps one check)

### Request

> "Parse the `Retry-After` header and wait that long before retrying."

### Reply

> ```python
> def retry_after_seconds(value: str) -> int:
>     # ponytail: integer seconds only; add HTTP-date parsing when a real server sends one
>     return max(0, int(value)) if value.isdigit() else 0
>
> assert retry_after_seconds("120") == 120
> assert retry_after_seconds("Wed, 21 Oct 2026 07:28:00 GMT") == 0
> ```
>
> One runnable check stays — lazy code without its check is unfinished.
