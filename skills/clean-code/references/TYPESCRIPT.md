# TypeScript — Clean Code Reference

> Language-specific companion for the [clean-code](../SKILL.md) skill. Covers TypeScript idioms, tooling, smells, and refactoring patterns.

## Tools

| Tool | Purpose | Install / Run |
|------|---------|---------------|
| `tsc` | Type checker (no emit mode) | `npx tsc --noEmit` |
| `eslint` | Linter + typescript-eslint rules | `npm install -D eslint @typescript-eslint/parser @typescript-eslint/eslint-plugin` |
| `biome` | Fast linter + formatter (eslint/prettier replacement) | `npm install -D @biomejs/biome` → `npx biome check .` |
| `knip` | Find unused exports, deps, and files | `npm install -D knip` → `npx knip` |
| `madge` | Detect circular dependencies | `npm install -D madge` → `npx madge --circular --extensions ts src/` |
| `ts-prune` | Find unused exports | `npm install -D ts-prune` → `npx ts-prune` |
| `depcheck` | Find unused npm dependencies | `npx depcheck` |

### Quick Audit

```bash
# Type check — catches refactoring regressions
npx tsc --noEmit

# Full lint sweep
npx eslint . --ext .ts,.tsx
# or with Biome
npx biome check .

# Find unused exports, dependencies, and files
npx knip

# Detect circular dependencies
npx madge --circular --extensions ts src/

# Find unused npm packages
npx depcheck

# Clone detection
npx jscpd --min-lines 5 --min-tokens 50 ./src
```

## TypeScript-Specific Smells

### 1. `any` Abuse

Using `any` defeats the purpose of TypeScript — turns off type checking.

```diff
# Bad — no type safety
- function processData(data: any): any {
-     return data.items.map((item: any) => item.value);
- }

# Good — typed
+ interface DataSet {
+     items: Array<{ value: number }>;
+ }
+ function processData(data: DataSet): number[] {
+     return data.items.map(item => item.value);
+ }

# Good — constrained generic when type varies
+ function processData<T extends { items: Array<{ value: number }> }>(data: T): number[] {
+     return data.items.map(item => item.value);
+ }
```

**Detect:** `rg '\bany\b' --type ts --count-matches | sort -t: -k2 -rn | head -20`

### 2. Excessive Type Assertions

Using `as` to force types instead of narrowing — hides bugs.

```diff
# Bad — lying to the compiler
- const user = getResponse() as User;
- const el = document.getElementById("root") as HTMLDivElement;

# Good — type guard with narrowing
+ const response = getResponse();
+ if (!isUser(response)) throw new Error("invalid response");
+ const user = response; // correctly narrowed to User

# Good — null check instead of assertion
+ const el = document.getElementById("root");
+ if (!el) throw new Error("root element not found");
```

**Detect:** `rg '\bas\b\s+\w' --type ts --count-matches | sort -t: -k2 -rn | head -20`

### 3. Enum vs Union Type

TypeScript enums add runtime code and have quirks. Union types are simpler and safer.

```diff
# Bad — enum generates runtime JS, allows numeric access
- enum Status {
-     Active = "active",
-     Inactive = "inactive",
-     Pending = "pending",
- }

# Good — union type, zero runtime cost
+ type Status = "active" | "inactive" | "pending";

# Good — when you need a namespace for related values
+ const Status = {
+     Active: "active",
+     Inactive: "inactive",
+     Pending: "pending",
+ } as const;
+ type Status = (typeof Status)[keyof typeof Status];
```

**Detect:** `rg '^export enum|^enum' --type ts`

### 4. Barrel File Bloat

`index.ts` that re-exports everything — slows bundling, creates circular deps, imports things you don't need.

```diff
# Bad — barrel re-exports the entire module
- // src/utils/index.ts
- export * from "./string";
- export * from "./date";
- export * from "./validation";
- export * from "./crypto";
- export * from "./http";

# Good — import directly from the module you need
+ import { formatDate } from "@/utils/date";
+ import { isEmail } from "@/utils/validation";
```

**Detect:** `rg 'export \* from' --type ts --count-matches | sort -t: -k2 -rn | head -10`

### 5. Callback Hell / Promise Chains

Nested `.then()` chains instead of async/await — hard to read and handle errors.

```diff
# Bad — nested promises
- function loadUserData(id: string) {
-     return fetchUser(id)
-         .then(user => fetchOrders(user.id)
-             .then(orders => fetchPayments(orders[0].id)
-                 .then(payments => ({ user, orders, payments }))));
- }

# Good — async/await
+ async function loadUserData(id: string) {
+     const user = await fetchUser(id);
+     const orders = await fetchOrders(user.id);
+     const payments = await fetchPayments(orders[0].id);
+     return { user, orders, payments };
+ }
```

**Detect:** `rg '\.then\(.*\.then\(' --type ts`

### 6. God Interface / Monster Type

A single type with 20+ fields used everywhere — different consumers need different shapes.

```diff
# Bad — one type for everything
- interface User {
-     id: string; name: string; email: string; password: string;
-     role: string; avatar: string; bio: string; createdAt: Date;
-     lastLogin: Date; preferences: Preferences; orders: Order[];
-     addresses: Address[]; paymentMethods: Payment[];
-     // ... 10 more fields
- }

# Good — purpose-specific types
+ interface UserProfile {
+     id: string; name: string; avatar: string; bio: string;
+ }
+ interface UserAuth {
+     id: string; email: string; password: string; role: string;
+ }
+ interface UserListItem {
+     id: string; name: string; email: string; lastLogin: Date;
+ }
```

**Detect:** Count fields per interface: `rg -U 'interface \w+ \{' --type ts --multiline -A 30 | awk '/interface/{name=$2; count=0} /\w+[\?]?:/{count++} /\}/{if(count>10) print name": "count" fields"}'`

### 7. Implicit `undefined` Returns

Functions that sometimes return a value and sometimes return nothing — caller can't trust the return type.

```diff
# Bad — implicitly returns undefined
- function findUser(id: string): User | undefined {
-     const user = users.get(id);
-     if (user) return user;
-     // implicit undefined return
- }

# Good — explicit and consistent
+ function findUser(id: string): User | undefined {
+     return users.get(id);
+ }

# Better — Result pattern for operations that can fail
+ type Result<T, E = Error> = { ok: true; value: T } | { ok: false; error: E };
+
+ function findUser(id: string): Result<User> {
+     const user = users.get(id);
+     if (!user) return { ok: false, error: new Error(`User ${id} not found`) };
+     return { ok: true, value: user };
+ }
```

**Detect:** `rg 'function \w+.*: \w+ \| undefined' --type ts`

### 8. Overuse of Classes

Using classes where plain functions and objects suffice — unnecessary complexity in TypeScript.

```diff
# Bad — class for stateless logic
- class UserValidator {
-     validate(user: UserInput): ValidationResult {
-         const errors: string[] = [];
-         if (!user.name) errors.push("name required");
-         if (!user.email?.includes("@")) errors.push("invalid email");
-         return { valid: errors.length === 0, errors };
-     }
- }
- const validator = new UserValidator();
- validator.validate(input);

# Good — plain function
+ function validateUser(user: UserInput): ValidationResult {
+     const errors: string[] = [];
+     if (!user.name) errors.push("name required");
+     if (!user.email?.includes("@")) errors.push("invalid email");
+     return { valid: errors.length === 0, errors };
+ }
+ validateUser(input);
```

**Detect:** `rg 'class \w+ \{' --type ts` — review if the class has no state and only one method.

## TypeScript Refactoring Patterns

### Discriminated Unions

Replaces class hierarchies and type switches on string fields.

```diff
# Before: string-based type checking
- interface Event {
-     type: string;
-     payload: any;
- }
- function handle(event: Event) {
-     if (event.type === "click") {
-         const { x, y } = event.payload as { x: number; y: number };
-     } else if (event.type === "keypress") {
-         const { key } = event.payload as { key: string };
-     }
- }

# After: discriminated union — exhaustive, type-safe
+ type Event =
+     | { type: "click"; x: number; y: number }
+     | { type: "keypress"; key: string }
+     | { type: "scroll"; offset: number };
+
+ function handle(event: Event) {
+     switch (event.type) {
+         case "click": console.log(event.x, event.y); break;
+         case "keypress": console.log(event.key); break;
+         case "scroll": console.log(event.offset); break;
+     }
+ }
```

### Branded Types (Nominal Typing)

Prevents mixing up primitives that represent different things.

```diff
# Before: easy to swap arguments
- function assignOrder(userId: string, orderId: string): void {
-     // oops: assignOrder(orderId, userId) compiles fine
- }

# After: branded types — compiler catches mistakes
+ type UserId = string & { readonly __brand: "UserId" };
+ type OrderId = string & { readonly __brand: "OrderId" };
+
+ function userId(id: string): UserId { return id as UserId; }
+ function orderId(id: string): OrderId { return id as OrderId; }
+
+ function assignOrder(userId: UserId, orderId: OrderId): void { /* ... */ }
+ // assignOrder(orderId("o1"), userId("u1")) → compile error
```

### Schema Validation with Zod

Replaces manual validation code scattered across endpoints.

```diff
# Before: manual validation duplicated in every handler
- function createUser(req: Request) {
-     const { name, email, age } = req.body;
-     if (!name || typeof name !== "string") throw new Error("invalid name");
-     if (!email || !email.includes("@")) throw new Error("invalid email");
-     if (age !== undefined && typeof age !== "number") throw new Error("invalid age");
-     // ...
- }

# After: single schema, reusable
+ import { z } from "zod";
+
+ const CreateUserSchema = z.object({
+     name: z.string().min(1),
+     email: z.string().email(),
+     age: z.number().int().positive().optional(),
+ });
+ type CreateUserInput = z.infer<typeof CreateUserSchema>;
+
+ function createUser(req: Request) {
+     const input = CreateUserSchema.parse(req.body); // throws ZodError
+     // input is fully typed as CreateUserInput
+ }
```

### Module Organization

Replaces barrel files with direct imports.

```diff
# Before: everything through index.ts
- // utils/index.ts
- export * from "./string";
- export * from "./date";
- export * from "./validation";
-
- // consumer.ts
- import { formatDate, isEmail, capitalize } from "@/utils";

# After: direct imports — better tree-shaking, no circulars
+ // consumer.ts
+ import { formatDate } from "@/utils/date";
+ import { isEmail } from "@/utils/validation";
+ import { capitalize } from "@/utils/string";
```

## TypeScript Verification Commands

```bash
# Type check
npx tsc --noEmit

# Lint
npx eslint . --ext .ts,.tsx
# or
npx biome check .

# Run tests
npx vitest run
# or
npx jest

# Find unused exports and dependencies
npx knip

# Check circular dependencies
npx madge --circular --extensions ts src/

# Check unused npm packages
npx depcheck
```
