---
name: obsidian-brain
description: "Use when starting a session in a project whose CLAUDE.md or AGENTS.md references an Obsidian vault. Maintains a token-efficient knowledge index at <vault>/brain/<slug>-brain.md plus atomic notes for sessions, topics, and decisions, complementing (not replacing) the built-in auto-memory. Trigger phrases: 'obsidian brain', 'memória do projeto', 'load project memory', 'project brain', 'ativar memória do projeto', 'carregar memória do projeto', '/obsidian-brain'."
source: ValarMindSkills
---

# Obsidian Brain

A token-efficient session-memory layer for any project whose `CLAUDE.md` (preferred) or `AGENTS.md` references an Obsidian vault. Maintains a small index file (`<slug>-brain.md`) plus atomic notes for sessions, topics, and decisions, all colocated with the project's existing documentation in the vault.

Operates as a knowledge graph **per project**, complementing — never duplicating — the harness's built-in auto-memory (which captures user/feedback/project/reference snippets globally).

## When to Use

- The current working directory has a `CLAUDE.md` or `AGENTS.md` that mentions an Obsidian vault, a `vault` path, or a folder named `*Obsidian*`.
- The user explicitly asks to load project memory, activate the brain, or runs `/valarmindskills:obsidian-brain`.
- The hook `hooks/obsidian-brain/obsidian-brain-activate.js` injected the activation system-reminder at session start.
- A relevant change was made (architecture, decision, refactor, gotcha) and you need to record it for the next session.

The statusline renders a roxo `[OBSIDIAN-BRAIN]` badge while the skill is active in this session, and a dim cinza `[OBSIDIAN-BRAIN]` badge when no vault is detected or when the user opted out via `/valarmindskills:obsidian-brain off` — paralelo ao `[SUPERPOWERS]`.

## Do not use when

- No `CLAUDE.md` or `AGENTS.md` exists in the cwd or any ancestor up to the repo root.
- Neither file references an Obsidian vault — the regex `obsidian|vault|Obsidian` returns no match.
- The detected vault path resolves under a directory marked read-only by the project's `CLAUDE.md` (e.g., `Notes/` in this repo). Refuse and report.
- The user asked for the **built-in auto-memory** types (user/feedback/project/reference) — that is a separate system handled by the harness.
- The task is a one-line edit, typo fix, or trivial dependency bump and the user has not asked for memory.

## Prerequisites

| Prerequisite | How to verify |
| :--- | :--- |
| `CLAUDE.md` or `AGENTS.md` in cwd or ancestor | `test -f CLAUDE.md` then `test -f AGENTS.md` |
| File references an Obsidian vault | `grep -i 'obsidian\|vault'` returns ≥1 line |
| Vault path resolves on disk | `realpath` succeeds and target is a directory |
| Write permission on `<vault>/<project>/brain/` | `test -w <path>` (refuse if path falls under a documented read-only directory) |
| `@obsidian-cli` available (preferred) | `obsidian --version` exits 0 |

If the CLI probe fails, the skill switches to **fallback file-IO** mode (`Read` / `Write` / `Edit` / `Bash grep`). All examples in this skill assume the CLI; substitutions are listed in [references/READING_AND_SEARCHING.md](references/READING_AND_SEARCHING.md) and [references/WRITING_RULES.md](references/WRITING_RULES.md).

**Probe once.** Run `obsidian --version 2>/dev/null` exactly once per session, on the first turn the skill activates. Cache the result mentally as `mode = cli | file` and use that mode for the rest of the session. Do not re-probe per turn.

## Phase 0 — Detection

Run, in order, until one resolves:

1. Read `CLAUDE.md` from the cwd. If absent, try `AGENTS.md`. If absent, walk up to a maximum of three ancestor directories.
2. Extract the first vault path from the file body. The path matches the regex below — relative (`./`, `../`), absolute (`/`), or home-relative (`~/`), and must contain the literal substring `Obsidian`:

   ```regex
   (?:~\/|\.{1,2}\/|\/)[^"\s'`)]*Obsidian[^"\s'`)]*
   ```

   The path terminates at whitespace, double-quote, single-quote, backtick, or close-paren. Expand `~` via the home directory if present. Resolve to an absolute path. If `realpath` fails or the path is read-only, abort with a one-line notice and exit.
3. From the resolved path, derive `<project-slug>` from the **immediate child folder name** (the leaf of the resolved path). Apply only `lowercase + replace [^a-z0-9] with '-'` then trim leading/trailing `-`. **Do not** apply camelCase splitting. Examples:
   - `Projetos/ValarMindSkills/` → slug `valarmindskills` → brain file `valarmindskills-brain.md`
   - `~/MyVault/MyProject/` → slug `myproject` → brain file `myproject-brain.md`

   This rule must match the hook's derivation in `hooks/obsidian-brain/obsidian-brain-activate.js`. If the hook output contradicts your computed path, trust the hook output.
4. Compute:
   - `vaultRoot = <resolved directory>` (the project doc folder, not necessarily the entire vault — the brain lives **next to the project's existing docs**, not at the vault root)
   - `brainRoot = <vaultRoot>/brain/`
   - `indexPath = <brainRoot>/<slug>-brain.md`

If the resolved path looks like a vault root rather than a project folder (i.e., it contains a `Projetos/` or similar subfolder), the user probably meant a child of it. Surface the ambiguity in one line and wait for confirmation before bootstrapping.

Record these signals in conversation context. Do not write to disk yet.

The full decision tree, including ambiguity resolution and conflicting CLAUDE.md/AGENTS.md, lives in [references/SESSION_LIFECYCLE.md](references/SESSION_LIFECYCLE.md).

## Phase 1 — Bootstrap (first run)

Trigger: `<indexPath>` does not exist.

**Idempotency rule.** If `<indexPath>` already exists on disk, **skip Phase 1 entirely** and go to Phase 2 — never re-bootstrap, never overwrite the index. Re-bootstrap is only allowed if the user explicitly says so (e.g., "wipe the brain and start over"), and even then only after a one-question confirmation.

> [!important] When to ask the bootstrap question
> Phase 1 is **eager-ask, lazy-write** — the question fires as the agent's first user-facing sentence; the actual `mkdir` + seed only happens after the user says yes. The timing rule:
>
> - **Default (every session, including auto mode)** — ask the question **immediately** after Phase 0 succeeds, as the first user-facing sentence of the next response. Auto mode does **not** suppress the question: a single y/n is one keystroke, not a real interruption, and Phase 1 has no other reliable trigger that does not depend on the brain already existing (Phase 3 needs the index to know what to write; Phase 4 needs the index to sync).
> - **Mid-task exception (rare)** — if another skill is already mid-question (an actual interactive prompt is on screen waiting for input), defer **only** until that prompt is answered, then ask. Do **not** defer to "first natural pause", "end-of-task report", or any other vague handoff — those are the failure modes that left brains uncreated. Record the deferral as a single one-shot intent so it survives `/compact`.
> - **Phase 3 race guard** — if any Phase 3 write trigger (new session note, topic, decision) fires before Phase 1 has been answered, **stop and ask now**. Never write to `brain/` without an existing index.
> - **Phase 4 entry guard** — if any end-of-session signal fires before Phase 1 was answered, ask now before running any Phase 4 action. Phase 4 is **gated** on Phase 1.
> - **Re-injection idempotency** — the SessionStart hook re-injects the activation digest after `/compact` and across new sessions. If the digest fires while Phase 1 is still pending, resume the same intent (do not re-defer indefinitely, do not ask twice). Treat the deferral state as a single one-shot until answered or the user explicitly refuses.
> - **Refusal is sticky for the session** — once the user says no, do not re-prompt; mark the brain as opted-out for the rest of the session and respect that across re-injections.

Steps:

1. Confirm with the user before any write: "Bootstrap obsidian-brain at `<indexPath>`? This creates `brain/`, three subdirectories, and seeds the index. Proceed?" Wait for explicit yes. Choose the moment per the timing rule above.
2. Create the directory tree. **Phase 1 prefers the shell-IO path** because directory creation and bulk file seeding are more reliably done with `mkdir`/`Write` than via the CLI's `create` subcommand (which the local `@obsidian-cli` skill exemplifies only with `name=`, not `path=`). Use:

   ```bash
   mkdir -p "<brainRoot>/sessions" "<brainRoot>/topics" "<brainRoot>/decisions"
   touch "<brainRoot>/sessions/.gitkeep" "<brainRoot>/topics/.gitkeep" "<brainRoot>/decisions/.gitkeep"
   # then use the Write tool to seed <indexPath> from the template in references/STRUCTURE.md.
   ```

   If you have a strong reason to use the CLI for the index seed instead (e.g., to integrate with vault watchers), confirm syntax first: `obsidian help create` then attempt `obsidian create path="brain/<slug>-brain.md" content="<seeded index>" silent`. If that fails, fall back to `Write` immediately — never guess flags.

3. Seed `<indexPath>` from the **index template** in [references/STRUCTURE.md](references/STRUCTURE.md). The seed must satisfy the token economy budget: ≤500 tokens total, ≤150 tokens in the `> [!summary]` "Critical facts" callout.

4. **Do not modify any file outside `brain/`.** Brain is an isolated graph — the project's main MOC must not be edited to point at the brain, and the brain must not link out to project docs. Phase 1 touches only the `brain/` subtree and its index.

5. Output the bootstrap report (see Output format).

If the user refuses bootstrap, exit silently — do not retry within the session.

## Phase 2 — Load (read strategy)

Trigger: `<indexPath>` exists.

> [!info] Route the prompt before reading
> Before loading anything, classify the user's question into one of three buckets — the answer determines which subtree of the vault to consult:
>
> | Bucket | Examples | Where the answer lives | Phase to follow |
> | :--- | :--- | :--- | :--- |
> | **Brain-history** | "what was decided about X", "when did we discuss Y", "open todos", "recent activity" | `brain/sessions`, `brain/topics`, `brain/decisions` | Phase 2 (this section) |
> | **General-doc** | "how does X work", "what does skill Y do", "where is the architecture for Z", "show me the MOC" | Project docs (`<vaultRoot>/<MOC>.md`, `Skills/`, `Arquitetura.md`, `Manual de Uso/`, `Technical Design/`) | [Phase 2.5](#phase-25--searching-general-project-docs) |
> | **Mixed** | "explain auth and what we decided about it" | Both — but lead with the general doc for substance, then surface brain context | Phase 2.5 then Phase 2 |
>
> Default to **Phase 2.5** if the question is about *how the system works*. Default to **Phase 2** only when the question is about *what happened in past sessions*. When unclear, run Phase 2.5 first; the brain is cheap to consult after.

1. **Read only the index** at session start (≤500 tokens). Do not preemptively load sessions, topics, or decisions.
2. From the index, identify the wikilinks relevant to the current user prompt — match by topic name, tag, or recent-session date.
3. Lazy-load only matched targets:
   - For a topic: `obsidian read file="<topic>"` (CLI, exemplified) or `Read` on the absolute path (fallback).
   - For a tag query: `obsidian search tag="<tag>"` (CLI, **verify with `obsidian help search` first**) or `grep -lrn 'tags:.*<tag>' <brainRoot>` (fallback).
   - For a property query: `obsidian search property="type=brain-decision"` (CLI, **verify**) or `grep -lrn '^type: brain-decision' <brainRoot>` (fallback).
4. Stop reading the moment the relevant context is in hand. Do not "read everything just in case."
5. Critical-facts callout in the index is the only block you may quote verbatim into your reasoning. Everything else is a wikilink to follow on demand.

Detailed strategy and the canonical CLI command catalog: [references/READING_AND_SEARCHING.md](references/READING_AND_SEARCHING.md).

## Phase 2.5 — Searching general project docs

Trigger: the user's question is about how the system works (general-doc bucket above) or the brain index has no matching wikilink.

The brain captures **what happened**; the project's main vault docs capture **how it works**. When the answer lives in the main docs, you must search them with the CLI **before** reaching for `Read`/`grep`.

1. **Use the cached `mode` from Phase 2.** If `mode = cli`, run the CLI recipes below. If `mode = file`, fall back to `grep`/`find`/`Read`.
2. **Scope the search to the project doc folder**, not the entire vault:

   ```bash
   obsidian search query="<term>" path="<vaultRoot>"     # verify with `obsidian help search` first
   ```

   `<vaultRoot>` here is the same path computed in Phase 0 (e.g., `Projetos/ValarMindSkills/`).
3. **Filter by tag or property** when the user named a category — `tag="skill"`, `tag="lang/go"`, `property="type=skill"`. Combine with `total` to count first:

   ```bash
   obsidian search tag="skill/segurança-api" total
   ```
4. **Read the top match** with `obsidian read file="<note-name>" silent`. Aliases resolve automatically — prefer `file=` over `path=` unless there is ambiguity.
5. **Optionally check backlinks** to surface related sessions in the brain:

   ```bash
   obsidian backlinks file="<note-name>"
   ```
6. **Quote sparingly.** Pull only the one or two passages that answer the question. Link to the doc with `[[<note>]]` when writing back to the brain — do not duplicate the doc into a topic note.

Full intent→command recipe table, fallback chain, and Notes/-read-only reminder live in [references/READING_AND_SEARCHING.md § Searching general project docs](references/READING_AND_SEARCHING.md#searching-general-project-docs-beyond-brain). Canonical CLI catalog (used by every other agent too) is in `@obsidian-cli`.

Always probe `@obsidian-cli` first; only fall back to `Read`/`grep` when the cached `mode = file`. Aliases, wikilinks, and the vault index are invisible to plain `grep`.

## Phase 3 — Operate (write strategy)

Write to the brain only when at least one of these triggers fires:

| Trigger | Target file |
| :--- | :--- |
| The user asked something the brain did not previously cover, and the answer survives the session | `brain/sessions/YYYY-MM-DD-<slug>.md` (append) |
| You discovered a non-obvious project fact (architecture, constraint, gotcha) | `brain/topics/<topic>.md` (atomic, dedupe first) |
| A trade-off was explicitly chosen ("we picked X because Y") | `brain/decisions/NNNN-<slug>.md` (immutable ADR) |
| A pending task was identified that survives the session | append `> [!todo]` block to active session note |

Always:

- **Dedupe first** — `obsidian search query="<key term>"` or `obsidian tags list` before creating a new topic/decision. If a near-duplicate exists, append/refine it instead of creating a new note.
- **Bullets > prose** — every entry begins with a one-sentence summary line, then bullets, then wikilinks. No paragraphs.
- **Wikilinks ≥ 2** per non-trivial entry — the entry must connect into the graph.
- **Update properties surgically** — `obsidian property:set name="updated" value="YYYY-MM-DD" file="<note>"` instead of rewriting the frontmatter.
- **Refuse `Notes/`** — if any target path falls under `Notes/` (or any directory the project `CLAUDE.md` marks read-only), abort the write and notify the user.

Templates per note type, dedupe heuristics, ADR triggers, and atomic-note rules: [references/WRITING_RULES.md](references/WRITING_RULES.md).

## Phase 4 — End-of-session sync

When the user signals end-of-session ("/clear", "obrigado", "encerrar", actual session close, or after a substantial finished task), perform this sequence at most once per session:

0. **Phase 1 entry guard.** If `<indexPath>` is missing AND the session had ≥1 substantive turn (anything beyond "hi"/typo fix), surface the Phase 1 bootstrap question **now**, before any other Phase 4 action. Block the rest of Phase 4 until the user answers. If the user refuses, exit Phase 4 silently — there is nothing to sync. This guard catches the case where the SessionStart digest was emitted but the agent failed to ask the question earlier in the session.
1. **Append session summary** as a `> [!summary]` callout to the active session note in `brain/sessions/`. ≤30 lines, ≤6 bullets.
2. **Update properties** of touched topics and the index (`updated: YYYY-MM-DD`) via surgical CLI calls.
3. **Refresh "Recent sessions"** in the index — wikilink to today's session note at the top, drop entries older than 10. If buildup exceeds 10, suggest the dedicated `synthesize` command.
4. **Suggest synthesis** when 3+ recent sessions touched the same topic without a corresponding `topics/<topic>.md` note. One line: "Topic `X` appeared in 3 recent sessions; want me to synthesize a topic note?"

Do not write a session note if the session produced nothing worth remembering (informational chat, trivial fix, no architectural insight). Bias toward fewer notes.

## Phase 5 — Suggest updating main docs

The brain captures **what happened**; the project's main vault docs (`Projetos/<project>/*.md` MOCs, Architecture notes, Skill notes) capture **how the system works**. The two are complementary, not redundant.

After any change that alters architecture, conventions, public interfaces, or skill behavior:

1. Identify the canonical doc affected (typically `Arquitetura.md`, `Manual de Uso.md`, `Skills/<slug>/<slug>.md`, or the project MOC).
2. Surface a one-line suggestion: "Consider updating `<doc>` to reflect <change>. Want me to draft the diff?"
3. If the user agrees, hand off to `@obsidian-markdown` for syntax and to `@obsidian-cli` for the actual write.

Do not update main docs unilaterally. The user reviews the diff first. The Phase 5 suggestion is **prose only** — never create a wikilink from a brain note to a project doc, and never edit the project MOC to wikilink to the brain. Brain stays out of the project documentation graph in both directions.

## Skills it delegates to

| Operation | Delegated skill | Priority |
| :--- | :--- | :--- |
| Read / grep / create / append / update properties on the vault | `@obsidian-cli` | Primary — try first |
| Syntax for callouts, wikilinks, embeds, frontmatter, tags | `@obsidian-markdown` | Always |
| Dashboard `brain.base` (filters, views, formulas) | `@obsidian-bases` | On-demand only |

This skill orchestrates the **strategy** (what to write where, when to read what); the delegated skills handle the **mechanism**.

## Persistence

Default mode: **on**. The `SessionStart` hook auto-activates per session whenever a vault is detected via `CLAUDE.md` or `AGENTS.md`. With no vault detected, the hook silently clears the active flag and the statusline badge dims to cinza — the skill produces no further effect that session.

| Action | Effect |
| :--- | :--- |
| `/valarmindskills:obsidian-brain off` | Disable for this session — flag cleared, badge dim cinza, no `additionalContext`. |
| `/valarmindskills:obsidian-brain on` | Re-enable for this session (only meaningful if the SessionStart hook had set the flag in the first place). |
| `stop obsidian-brain`, `desativar obsidian-brain` (PT/EN) | Same as `off`. |
| `OBSIDIAN_BRAIN_DEFAULT_MODE=off` (env) | Disable persistently across all new sessions. |
| `~/.config/obsidian-brain/config.json` with `{"defaultMode": "off"}` | Disable persistently (XDG fallback). |

The skill **does not** inject reinforcement into every `UserPromptSubmit` — the SessionStart digest is sufficient. Adding per-turn context would defeat the token-economy goal.

## Constraints

- **Never** write under any directory the project's `CLAUDE.md` marks read-only (`Notes/` in this repo).
- **Never** duplicate auto-memory built-in content (user preferences, global feedback, profile facts).
- **Never** load more than the index at session start. Lazy-load only.
- **Never** exceed 500 tokens in the index file. Critical-facts callout ≤150 tokens.
- **Never** write prose paragraphs in brain files — bullets, callouts, wikilinks only.
- **Never** rewrite a note when only a property changed — use surgical property update.
- **Never** edit an ADR after it has been written — supersede via a new file with `status: superseded`.
- **Never** wikilink from any brain note (sessions, topics, decisions, **or the index**) to project docs. Mention skills/docs in body prose with backticks (`` `prompt-engineering` ``) instead.
- **Never** modify the project MOC, `Arquitetura.md`, or any other project doc to add a wikilink to the brain. Brain is a closed graph; isolation is bidirectional.
- **Must** prefer `@obsidian-cli` for every I/O operation **for commands marked exemplified** in [references/READING_AND_SEARCHING.md](references/READING_AND_SEARCHING.md). For commands marked **verify**, run `obsidian help <subcommand>` once before first use; on failure, drop to file-IO without retrying with guessed flags.
- **Must** dedupe before creating any topic or decision note.
- **Must** include a `> [!summary]` callout as the first content block of every session note.
- **Must** ask the user before bootstrapping the brain (one explicit yes/no, once per session).
- **Must** suggest updating the main docs after relevant changes — never update them unilaterally.
- **Must** treat the slug derivation rule (`lowercase + [^a-z0-9]→'-'`, no camelCase) as authoritative; if it produces a name that conflicts with an existing file, surface the conflict instead of inventing an alternative.

## Output format

After any operation, report exactly:

```text
obsidian-brain: <action>
  index: <indexPath> (mode: cli|file)
  wrote: <files written, paths relative to brain/>
  read: <files loaded, count>

Suggested next: <one line — "synthesize topic X" / "update Arquitetura.md" / nothing>
```

Omit the report when the operation was a silent skip (no detection match, user refused bootstrap, nothing worth writing).

## Example invocations

- (automatic) Hook injects `OBSIDIAN-BRAIN ACTIVE` at session start when `CLAUDE.md` / `AGENTS.md` mentions a vault.
- "ative o brain do projeto"
- "carregue a memória do projeto antes de responder"
- "load project memory"
- "/valarmindskills:obsidian-brain"
- "/valarmindskills:obsidian-brain on" — re-enable after a previous off in the same session.
- "/valarmindskills:obsidian-brain off" — disable for this session.
- "stop obsidian-brain", "desativar obsidian-brain" — natural-language disable.
- "/valarmindskills:obsidian-brain synthesize" — consolidates recent sessions into topic notes.

## References

- [SESSION_LIFECYCLE](references/SESSION_LIFECYCLE.md) — detection decision tree, first-run vs subsequent runs, end-of-session triggers.
- [STRUCTURE](references/STRUCTURE.md) — exact `brain/` layout, frontmatter for every note type, naming conventions, callouts, templates.
- [READING_AND_SEARCHING](references/READING_AND_SEARCHING.md) — lazy-load discipline, canonical CLI commands, fallback chain, `brain.base` on-demand.
- [WRITING_RULES](references/WRITING_RULES.md) — atomic notes, dedupe via CLI, ADR triggers, append-only sessions, atomic-rewrite topics, fallback substitutions.
