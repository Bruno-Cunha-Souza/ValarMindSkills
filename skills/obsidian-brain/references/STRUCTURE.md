> Reference companion for the [obsidian-brain](../SKILL.md) skill.

# Structure

The exact disk layout, frontmatter, naming, and templates for every note type the brain produces.

## Disk layout

```
<vault-doc-root>/
├── <existing project docs — untouched>
└── brain/                              ← created on first run
    ├── <slug>-brain.md                 ← INDEX (≤500 tokens; sole entrypoint)
    ├── sessions/
    │   ├── .gitkeep
    │   └── YYYY-MM-DD-<short-slug>.md  ← append-only daily log
    ├── topics/
    │   ├── .gitkeep
    │   └── <topic>.md                  ← atomic note, atomic-rewrite
    ├── decisions/
    │   ├── .gitkeep
    │   └── NNNN-<short-slug>.md        ← immutable ADR
    └── brain.base                      ← optional, on-demand only
```

Rules:

- `brain/` lives **inside** the project's existing vault folder, beside the existing MOC. Never at the vault root.
- Subdirs are flat — no nested `topics/<area>/<topic>.md`. Use tags for area separation.
- `.gitkeep` files preserve empty directories in version control.
- `brain.base` is optional and only created when the user explicitly asks for a dashboard.

## Frontmatter — every note type

The brain inherits the vault's frontmatter conventions documented in `<vault>/CLAUDE.md`. Below are the additional brain-specific fields.

### Index (`<slug>-brain.md`)

```yaml
---
aliases:
  - Brain
  - Memória do Projeto
tags:
  - brain-index
  - projeto/<slug>
type: brain-index
status: active
project: <slug>
created: YYYY-MM-DD
updated: YYYY-MM-DD
---
```

### Session (`sessions/YYYY-MM-DD-<short-slug>.md`)

```yaml
---
tags:
  - brain-session
  - brain/session
type: brain-session
date: YYYY-MM-DD
session_id: <YYYY-MM-DD>-<short-slug>
topics:
  - "[[topic-x]]"
  - "[[topic-y]]"
decisions:
  - "[[NNNN-z]]"
created: YYYY-MM-DD
updated: YYYY-MM-DD
---
```

### Topic (`topics/<topic>.md`)

```yaml
---
aliases:
  - <Optional human-readable alias>
tags:
  - brain-topic
  - brain/topic
  - topic/<area>
type: brain-topic
related:
  - "[[other-topic]]"
created: YYYY-MM-DD
updated: YYYY-MM-DD
---
```

### Decision (`decisions/NNNN-<short-slug>.md`)

```yaml
---
tags:
  - brain-decision
  - brain/adr
  - decision/<status>
type: brain-decision
decision_id: NNNN
status: accepted        # accepted | superseded | deprecated
date: YYYY-MM-DD
supersedes: ""          # wikilink to prior decision if applicable
superseded_by: ""       # wikilink to newer decision if applicable
---
```

## Naming conventions

| Note type | Pattern | Example |
| :--- | :--- | :--- |
| Index | `<slug>-brain.md` | `valarmindskills-brain.md` |
| Session | `YYYY-MM-DD-<short-slug>.md` | `2026-04-24-obsidian-brain.md` |
| Topic | `<topic>.md` (lowercase, kebab-case, ≤32 chars) | `rsc-rendering.md`, `auth-middleware.md` |
| Decision | `NNNN-<short-slug>.md` (4-digit zero-padded sequence) | `0001-pick-bases-over-dataview.md` |

Decision IDs are **monotonically assigned** per project. Get the next ID with:

```bash
obsidian search property="type=brain-decision" total
# fallback:
ls brain/decisions | grep -E '^\d{4}-' | tail -1
```

## Tags

Hierarchical, lowercase, hyphenated (no spaces, per vault convention).

| Tag | Applied to | Purpose |
| :--- | :--- | :--- |
| `brain-index` | Index | Identifies the index file uniquely. |
| `brain-session` | Sessions | Bulk filter for "all sessions". |
| `brain-topic` | Topics | Bulk filter for "all topics". |
| `brain-decision` | Decisions | Bulk filter for "all ADRs". |
| `brain/session` | Sessions | Hierarchical — Bases-friendly. |
| `brain/topic` | Topics | Hierarchical. |
| `brain/adr` | Decisions | Hierarchical. |
| `topic/<area>` | Topics | Sub-classify topics by area (e.g., `topic/security`, `topic/rendering`). |
| `decision/<status>` | Decisions | `decision/accepted`, `decision/superseded`, `decision/deprecated`. |
| `projeto/<slug>` | Index | Co-tag with the project tag the rest of the vault uses. |

Use the **dash form** (`brain-index`) for top-level filters and the **slash form** (`brain/session`) for hierarchical Bases queries. Both work — pick by Bases query needs.

## Callouts

| Callout | Where it appears | Purpose |
| :--- | :--- | :--- |
| `> [!summary]` | First block of every session note; "Critical facts" block of the index | Executive summary, ≤6 bullets. |
| `> [!decision]` | Body of every ADR; inline in session notes when a decision was made | Frame a chosen trade-off; references the formal ADR via wikilink. |
| `> [!todo]` | Session notes only | Pending task that survives the session. |
| `> [!question]` | Session notes; topic notes when a question is open | Open question to revisit. |
| `> [!warning]` | Topic notes; index | Gotcha, footgun, or constraint that matters across sessions. |
| `> [!tip]` | Topic notes | Non-obvious win, shortcut, or pattern. |

Stay within this set — do not invent custom callouts. Bases ignores callouts, so they are a human-readability aid only.

## Wikilink format rule

> [!important] Filename-only, never path-prefixed
> Obsidian resolves wikilinks **from the vault root**, not from the file's own directory. Use the filename only, never a path prefix:
>
> - ✅ `[[2026-04-25-ci-cd-generator|2026-04-25]]` — Obsidian resolves by filename across the entire vault
> - ❌ `[[sessions/2026-04-25-ci-cd-generator|2026-04-25]]` — would only resolve if `sessions/` lived at the vault root, which it doesn't (the brain lives nested under `Projetos/<slug>/brain/sessions/`)
> - ✅ `[[0001-pick-bases-over-dataview|0001]]` — for ADRs
> - ❌ `[[decisions/0001-pick-bases-over-dataview|0001]]` — same problem
>
> Filenames must be **unique across the vault** for this to work. The brain's naming conventions (`<slug>-brain.md`, `YYYY-MM-DD-<short-slug>.md`, `NNNN-<short-slug>.md`) are designed to be globally unique on purpose.
>
> This rule applies to every wikilink in every brain note — index, sessions, topics, decisions. It applies equally to the index template, the session-note template, and the topic/decision templates below.

## Index template

This is the seed used by Phase 1 bootstrap. Replace `<slug>` and `<Project name>` literally. Keep the total under 500 tokens.

````markdown
---
aliases:
  - Brain
  - Memória do Projeto
tags:
  - brain-index
  - projeto/<slug>
type: brain-index
status: active
project: <slug>
created: YYYY-MM-DD
updated: YYYY-MM-DD
---

# <Project name> — Brain

> [!summary] Critical facts (≤150 tokens)
> - Project: <one line — what this project is>
> - Source of truth: `[[<project-MOC>]]`
> - Read this index first; lazy-load the rest via wikilinks.
> - Brain is for **what happened**; main docs are for **how it works**.

## Topics (MOCs)

- `[[topics/<topic-1>|<Topic 1>]]` — <one-line summary>
- `[[topics/<topic-2>|<Topic 2>]]` — <one-line summary>

## Recent sessions (last 10)

- `[[YYYY-MM-DD-<slug>|YYYY-MM-DD]]` — <one-line summary>

## Decisions (ADRs)

- `[[0001-<slug>|0001]]` — <one-line summary>

## Keywords

- `<keyword>` → `[[<topic>]]`
- `<keyword>` → `[[<topic>]]`

## Pending

- `> [!todo]` items rolled up from active sessions (refreshed by Phase 4 sync).

## Related

- `[[<project-MOC>]]`
- `[[Arquitetura]]` (if applicable)
- `[[CLAUDE.md]]` (vault rules)
````

## Session note template

```markdown
---
tags: [brain-session, brain/session]
type: brain-session
date: YYYY-MM-DD
session_id: YYYY-MM-DD-<short-slug>
topics: ["[[<topic>]]"]
decisions: []
created: YYYY-MM-DD
updated: YYYY-MM-DD
---

# YYYY-MM-DD — <One-line title>

> [!summary]
> - <bullet 1>
> - <bullet 2>
> - <bullet 3>

## Asked

- <user request, paraphrased to one line>

## Found

- <non-obvious finding 1> → `[[<topic>]]`
- <non-obvious finding 2>

## Done

- <action 1>
- <action 2>

## Pending

> [!todo]
> - [ ] <task that survives the session>

## Decisions made

- `[[NNNN-<slug>|NNNN]]` — <one-line summary>

## Related

- `[[<slug>-brain|Brain]]` — link back to the project's brain index (mandatory for graph connectivity)
- `[[<topic>]]` — every topic referenced above, repeated here as an explicit body wikilink
- `[[<NNNN-...>]]` or `[[<YYYY-MM-DD-...>]]` — sibling brain notes (decisions, other sessions) referenced in the body
```

> [!warning] Related section is mandatory
> Obsidian's graph view does not by default follow wikilinks declared **only in frontmatter** (`topics:`, `decisions:`, `related:`). A session whose only links are in `topics:` will appear as an orphan in the graph. The `## Related` section guarantees the session is reachable both visually (graph) and structurally (backlinks pane).

> [!important] Brain isolation rule
> Brain notes (sessions, topics, decisions) **must not** wikilink to project docs (`Skills/<slug>`, `Arquitetura`, MOCs, `Manual de Uso`, etc.). The index (`<slug>-brain.md`) is the **only boundary node** allowed to wikilink across layers. Mention project skills/docs in body prose with backticks (`` `prompt-engineering` ``), never with wikilinks. The brain captures *what happened*; project docs capture *how things work* — keeping the graphs separate prevents the brain from polluting the documentation graph.

## Topic note template

```markdown
---
aliases: ["<alias>"]
tags: [brain-topic, brain/topic, topic/<area>]
type: brain-topic
related: ["[[<other-topic>]]"]
created: YYYY-MM-DD
updated: YYYY-MM-DD
---

# <Topic title>

> [!summary]
> <one-sentence definition>

## Key facts

- <fact 1>
- <fact 2>

## Constraints

> [!warning]
> <constraint or gotcha>

## Sessions where this came up

- `[[YYYY-MM-DD-<slug>]]`

## Related

- `[[<slug>-brain|Brain]]`
- `[[<other-topic>]]`
```

> [!important] Topic notes follow the same boundary rule as sessions
> Do **not** wikilink to project docs (`Skills/<slug>`, MOCs, etc.) from a topic note. Use backticks (`` `prompt-engineering` ``) for textual mention. The index is the only boundary.

## Decision note template (ADR)

```markdown
---
tags: [brain-decision, brain/adr, decision/accepted]
type: brain-decision
decision_id: NNNN
status: accepted
date: YYYY-MM-DD
supersedes: ""
superseded_by: ""
---

# NNNN — <One-line title>

> [!decision]
> <One-sentence statement of the decision.>

## Context

- <why we had to decide>

## Options considered

- **<Option A>** — <trade-off>
- **<Option B>** — <trade-off>

## Decision

- We chose **<X>** because <Y>.

## Consequences

- <consequence 1>
- <consequence 2>

## Sessions where this was decided

- `[[YYYY-MM-DD-<slug>]]`

## Related

- `[[<slug>-brain|Brain]]`
- `[[<topic>]]` — topic this decision crystallizes (if any)
```

> [!important] Decisions follow the same boundary rule
> Do **not** wikilink to project docs from an ADR. Use backticks for textual mention.

## brain.base (optional dashboard)

On-demand only. When the user wants a visual dashboard, hand off to `@obsidian-bases` to create:

```yaml
filters:
  and:
    - tag: brain-session
views:
  - name: Recent sessions
    type: table
    order:
      - date DESC
    properties:
      - file.name
      - date
      - topics
  - name: Topics
    type: cards
    filters:
      tag: brain-topic
  - name: Decisions
    type: table
    filters:
      tag: brain-decision
    order:
      - decision_id ASC
    properties:
      - decision_id
      - status
      - date
      - file.name
```

This is illustrative — the actual schema is owned by `@obsidian-bases`. Confirm syntax with that skill before writing.
