# SKILL_MAP — Stage → Skills + Context Triggers

Companion to [SKILL.md](../SKILL.md). This is the **ground truth** the 1% rule scans against. When superpowers is active, walk this map before replying: pick candidates by stage, then narrow by context triggers.

The map is **not** a fence. If a skill applies and is missing here, invoke it anyway and update this file.

## 1. Stage → Skills

Each row: skills marked **default** apply to nearly every task in that stage; skills marked **conditional** activate only when the context triggers in §2 fire.

| Stage | Default | Conditional |
| :--- | :--- | :--- |
| 1. Brainstorm | — | `@skill-creator` (task is "create/edit a skill") |
| 2. Worktree | — | — (handled by harness `EnterWorktree`) |
| 3. Write plan | — | `@skill-creator` (skill authoring); `@context-optimization` (long plan, large surface) |
| 4. Execute / implement | `@clean-code` | `@nextjs-optimization-pro`, `@nextjs-security-pro`, `@golang-api-security`, `@api-security-best-practices`, `@obsidian-markdown`, `@obsidian-cli`, `@obsidian-bases` (per §2) |
| 5. TDD + debugging | `@code-debugger` (when red/error) | `@api-security-testing` (API under test) |
| 6. Request review | `@code-review` *or* `@github-pr-review` | `@caveman-review` (terse preference); `@nextjs-security-pro`, `@golang-api-security`, `@web-vulnerabilities` (security-sensitive diff) |
| 7. Finish branch | `@github-commit` *or* `@caveman-commit` | `@github-release-note` (tag/release in scope) |

Notes:

- `@code-review` = full-detail; `@github-pr-review` = PR-shaped; `@caveman-review` = terse one-line findings. Pick by user preference and artifact (local diff vs GitHub PR).
- `@github-commit` = full conventional commit; `@caveman-commit` = terse subject. Same preference rule.
- Stage 2 has no skill — the harness's `EnterWorktree` capability covers it.

## 2. Context Triggers

Rules of the form `IF <signal> → invoke <skill(s)>`. Signals are **detected from the repo / task / error stream**, not asked. When multiple triggers fire, all named skills enter the scan; §3 resolves priority.

### Frontend / Next.js

- `IF` `next.config.{js,ts,mjs}` exists, or task touches `app/`, `pages/`, RSC, Server Actions, route handlers
  → `@nextjs-optimization-pro` (perf, RSC, rendering strategy) + `@nextjs-security-pro` (audit Server Actions, route handlers, proxy.ts, image optimizer)

### Backend APIs

- `IF` Go module + Gin or Fiber detected (`go.mod` mentions `gin-gonic/gin` or `gofiber/fiber`)
  → `@golang-api-security` (full lifecycle audit)
- `IF` new or modified REST/GraphQL endpoint, regardless of language
  → `@api-security-best-practices` (design phase) + `@api-security-testing` (validation phase)
- `IF` API in FastAPI / Bun+Elysia / Gin / Fiber and security focus is "find issues now"
  → `@api-security-testing` (active OWASP API Top 10 2023 tests)

### Generic web vulnerabilities

- `IF` task is "review for vulnerabilities" without a specific framework, or the user asks about vulnerability categories
  → `@web-vulnerabilities` (catalog + assessment guide)

### Obsidian

- `IF` working file is `.md` inside a vault (path contains `ValarMindObsidian/` or sibling vault)
  → `@obsidian-markdown` (OFM syntax: wikilinks, callouts, properties, embeds)
- `IF` task is "operate on the vault" (read/create/search notes from CLI, plugin/theme dev)
  → `@obsidian-cli`
- `IF` working file is `.base` or task creates a database-like view
  → `@obsidian-bases`

### Debugging / errors

- `IF` test failure, exception in log, unexpected runtime behavior
  → `@code-debugger` (root cause first; iron law: no fixes without investigation)

### Context / cost

- `IF` context > ~60% of window, conversation has many large tool results, or task is long-running
  → `@context-optimization` (compaction, masking, KV-cache strategy)

### Skill authoring

- `IF` task is "create a new skill", "scaffold skill", or edit a skill's structure
  → `@skill-creator` (archetypes, frontmatter, references/ layout)

### Voice preference

- `IF` user activated caveman (`/valarmindskills:caveman *`) AND a review/commit step is reached
  → prefer `@caveman-review` / `@caveman-commit` over their full-detail siblings

## 3. Priority resolution

When multiple skills apply, resolve in this order:

1. **Safety / security never yields.** `@*-security-*`, `@web-vulnerabilities`, and destructive-action confirmations always run before anything else. Process-skills never override security-skills for "speed".
2. **Process > implementation.** `@code-debugger`, `@skill-creator`, and review skills come before commit skills. The wrong implementation done quickly is debt.
3. **Explicit user preference wins.** If the user said "be terse" or activated caveman, use `@caveman-*` variants. If the user said "no plan", honor it (user-instruction tier of the hierarchy).
4. **Domain skills coexist with process skills.** Stage 4 can run `@clean-code` + `@nextjs-optimization-pro` + `@nextjs-security-pro` together — they cover different concerns and do not compete.

## 4. Maintenance

This map is updated **by hand** when:

- A new skill is added under `skills/` (add a row to §1 or a trigger to §2).
- A skill is renamed (update all references — they are cheap to grep: `rg '@skill-name'`).
- A skill is removed (drop the row/trigger; check `EXAMPLE.md` and `SKILL.md` for stale mentions).

For the canonical authoring flow, see [`skills/skill-creator/SKILL.md`](../../skill-creator/SKILL.md).

When in doubt, prefer false positives (mention a skill that may not apply) over false negatives (skip a skill that does apply). The 1% rule errs on the side of invoking.
