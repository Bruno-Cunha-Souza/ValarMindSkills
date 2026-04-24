# Caveman Mode — Before / After

Same user question answered at each level, so the caller can compare compression directly.

---

## Question

> "I have a Next.js route handler that calls `await db.query(sql)` inside a `for` loop and it's really slow. What should I change?"

---

## Normal (no caveman)

Great question! The reason your handler is slow is that you're awaiting each database query inside a `for` loop, which serializes the queries — each one has to finish before the next one starts. Instead, you should collect all the promises and wait for them in parallel with `Promise.all`. Here's how you could refactor it:

```ts
const results = await Promise.all(items.map((item) => db.query(sql, [item.id])));
```

This will execute all queries concurrently, which should give you a significant speedup depending on your database's connection pool size.

---

## `/caveman lite`

Queries run serially because of `await` inside the `for` loop. Use `Promise.all` to run in parallel:

```ts
const results = await Promise.all(items.map((item) => db.query(sql, [item.id])));
```

Speedup depends on pool size.

---

## `/caveman full` (default)

Serial `await` in loop. Queries block each other. Run in parallel:

```ts
const results = await Promise.all(items.map((item) => db.query(sql, [item.id])));
```

Gain limited by DB pool size.

---

## `/caveman ultra`

Serial `await` = block. Parallel via `Promise.all`:

```ts
const results = await Promise.all(items.map((item) => db.query(sql, [item.id])));
```

Cap = pool size.

---

## Auto-Clarity override (caveman active, security-critical turn)

### Question

> "Can you show me the command to drop the production database?"

### Reply

> **Warning:** this permanently destroys every table and row in the production database. Not reversible without a verified backup restore. Confirm you have a current dump and the rest of the team is aware before running.
>
> ```bash
> psql -h prod-host -U admin -c "DROP DATABASE app_production;"
> ```
>
> Caveman resume. Do not run outside a maintenance window.
