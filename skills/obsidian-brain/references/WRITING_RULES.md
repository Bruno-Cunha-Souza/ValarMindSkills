> Reference companion for the [obsidian-brain](../SKILL.md) skill.

# Writing Rules

How to write to the brain without bloating it.

## Atomic notes

One idea per note. If a note covers two distinct topics, split it.

| Test | If the answer is yes, split |
| :--- | :--- |
| Could one half be useful in a session that does not need the other half? | Yes → split |
| Are the two halves linked by "and also"? | Yes → split |
| Would a single one-sentence summary cover both? | No → split |

Split by creating a new topic note and updating wikilinks in the index and any session that references the original.

## Decide what to write

Before writing anything, check the trigger matrix:

| Signal | Target |
| :--- | :--- |
| User asked something the brain did not previously cover and the answer survives the session | `sessions/YYYY-MM-DD-<slug>.md` (append) |
| Non-obvious project fact discovered (architecture, constraint, gotcha) | `topics/<topic>.md` (atomic, dedupe first) |
| Trade-off explicitly chosen ("we picked X because Y") | `decisions/NNNN-<slug>.md` (immutable ADR) |
| Pending task that survives the session | `> [!todo]` block in active session note |
| Open question to revisit | `> [!question]` block in active session note |

If no trigger fires, **do not write**. Bias toward fewer notes.

## Dedupe before creating

The brain's worst failure mode is duplicate topic notes (e.g., `auth-middleware.md` and `auth-mw.md` saying the same thing). Always dedupe first.

### Topic dedupe

```bash
# Search by candidate name
obsidian search query="<candidate topic name>" limit=10

# List all topics
obsidian search tag="brain-topic" total
```

If a near-duplicate exists:

- **Refine** — add the new finding as a bullet, update `updated:` property.
- **Merge** — if two existing topics overlap, propose a merge to the user before acting.

### Decision dedupe

```bash
# Search ADRs by keyword
obsidian search query="<key term>" tag="brain/adr"
```

If the decision was already made:

- **Reference** the existing ADR from the new session note. Do not re-decide.
- **Supersede** if the original decision changed — create a new ADR with `supersedes: "[[NNNN-<old>]]"` and patch the old ADR's `status: superseded` and `superseded_by: "[[<new>]]"`.

## ADR triggers

Create an ADR (`decisions/NNNN-<slug>.md`) when **all** of these hold:

1. A clear trade-off was named (Option A vs Option B).
2. A choice was made between them.
3. The choice is non-obvious enough that a future reader would ask "why?"

Examples that qualify:

- "We picked Bases over Dataview because Dataview is slow on large vaults."
- "We chose flat `topics/` over nested `topics/<area>/<topic>.md` because Obsidian Bases ignores folder hierarchy."
- "We dropped server-side rendering for this route because it broke streaming."

Examples that do **not** qualify (not ADRs):

- "We renamed `foo` to `bar`." → session note bullet only.
- "We installed package X." → topic note if non-obvious; otherwise nothing.
- "We tried Y and it didn't work." → session note `> [!warning]` callout, not an ADR.

ADRs are **immutable** once written. To change a decision, supersede with a new ADR, never edit the original.

## Append-only sessions

Session notes are append-only within a single day. The file is `brain/sessions/YYYY-MM-DD-<slug>.md`.

### First write of the day

Create the file from the [session template](STRUCTURE.md#session-note-template). Prefer the `Write` tool with the absolute path — `obsidian create` is exemplified with `name=` only in the local `obsidian-cli` skill, so `path=` for create is **verify** territory:

```bash
# Preferred — use the harness Write tool on:
# <brainRoot>/sessions/YYYY-MM-DD-<slug>.md

# CLI alternative (verify with `obsidian help create` first):
obsidian create path="brain/sessions/YYYY-MM-DD-<slug>.md" content="<seeded body>" silent
```

### Subsequent writes that day

If the session note `brain/sessions/YYYY-MM-DD-<slug>.md` already exists today, **append, never recreate**:

```bash
obsidian append file="YYYY-MM-DD-<slug>" content="\n\n## Found (continued)\n- <new bullet>"
```

`obsidian append` is exemplified in the local `obsidian-cli` skill — safe to use. The fallback is `Edit` on the file with `old_string` matching the last existing line and `new_string` being the same line plus the appended block.

If you discover prior bullets are wrong, **add a correction below**, do not edit prior content. The corrupted bullet is part of the session record — preserving it preserves the audit log.

### Multiple sessions per day

If a single day has two distinct sessions, append a `<short-slug-2>` to the second filename: `2026-04-24-superpowers.md` and `2026-04-24-bases-rewrite.md`.

## Atomic-rewrite topics

Topic notes are different — they evolve. When you refine a topic:

1. Read the existing note.
2. Replace it entirely with the refined version, preserving all old bullets that are still true.
3. Increment `updated: YYYY-MM-DD`.

Prefer the `Write` tool (overwrites by design):

```bash
# Use the Write tool on <brainRoot>/topics/<topic>.md with the refined body.
```

The CLI alternative `obsidian create path="..." content="..." overwrite silent` is **verify** — the `overwrite` flag is not exemplified in the local `obsidian-cli` skill. If you choose the CLI route, run `obsidian help create` first to confirm the flag exists; on failure, drop to `Write`.

Then update the timestamp surgically (this command is exemplified in the CLI skill — safe to use):

```bash
obsidian property:set name="updated" value="YYYY-MM-DD" file="<topic>"
```

## Surgical property updates

For any case where only a frontmatter field changes, use:

```bash
obsidian property:set name="<field>" value="<value>" file="<note-name>"
```

Common cases:

| Case | Command |
| :--- | :--- |
| Touch updated date | `obsidian property:set name="updated" value="YYYY-MM-DD" file="<note>"` |
| Add a topic to a session | `obsidian property:set name="topics" value='["[[topic-x]]","[[topic-y]]"]' file="<session>"` |
| Mark ADR superseded | `obsidian property:set name="status" value="superseded" file="<ADR>"` then set `superseded_by`. |

Surgical updates preserve the rest of the note (clean Git diff, no body churn).

## Fallback for property updates

When the CLI is unavailable, use `Edit` on the frontmatter:

```python
# Pseudocode — actual impl uses Edit tool with the YAML lines as old_string/new_string.
old = "updated: 2026-04-23"
new = "updated: 2026-04-24"
```

Match the exact line including indentation. Do not rewrite the entire frontmatter block.

## Wikilink hygiene

Two failure modes produce orphan notes in the graph view. Avoid both.

### Filename-only, never path-prefixed

Obsidian resolves wikilinks **from the vault root**, not from the file's directory. Use the filename only:

```markdown
✅ [[2026-04-25-ci-cd-generator|2026-04-25]]
✅ [[0001-pick-bases-over-dataview|0001]]
✅ [[ci-cd-generator]]
✅ [[valarmindskills-brain|Brain]]

❌ [[sessions/2026-04-25-ci-cd-generator|2026-04-25]]      ← path doesn't resolve
❌ [[brain/topics/auth.md|Auth]]                            ← path + extension both wrong
❌ [[../brain/<slug>-brain]]                                ← relative paths never resolve
```

Filenames must be globally unique within the vault. The brain's naming conventions are already designed for this (timestamped sessions, ID-prefixed ADRs, slug-prefixed index).

### Always link back to the index

Every session, topic, and decision note must have a `## Related` section in its body that includes:

- `[[<slug>-brain|Brain]]` — the project's brain index (mandatory).
- Every wikilink also declared in frontmatter (`topics:`, `decisions:`, `related:`) — repeated as a body wikilink.

**Why repeat frontmatter wikilinks in the body?** Obsidian's graph view does **not** by default follow wikilinks declared only in frontmatter properties. A session whose only `[[ci-cd-generator]]` reference is in `topics: ["[[ci-cd-generator]]"]` will appear as an orphan even though the link technically exists. The body wikilink fixes this — it is graph-visible and backlinks-visible everywhere.

The `## Related` section is the last block of every note. See [STRUCTURE.md § Session note template](STRUCTURE.md#session-note-template) for the canonical shape.

### Self-check before saving

Before writing any brain note, scan its wikilinks:

- All `[[...]]` resolve to a real `.md` file by filename only?
- The note has a `## Related` section linking back to `[[<slug>-brain|Brain]]`?
- Every frontmatter wikilink is also present as a body wikilink?

If any answer is no, fix before saving. Orphans accumulate silently — graph view is the only signal, and you may not notice until the graph is already a mess.

## Token economy in writing

| Rule | Why |
| :--- | :--- |
| Bullets > prose | Easier to skim, easier to extend, fewer tokens. |
| Wikilinks > full quotes | The graph does the work; quotes duplicate. |
| `> [!summary]` first | Readers (human or agent) decide in 1 second whether to read further. |
| ≤6 bullets per summary | More than 6 = the section is two topics; split. |
| One-sentence definitions | If the topic needs two sentences to define, the topic is too big. |
| Cite session by wikilink, not by paste | Sessions are the audit log; copying their content into topics duplicates. |

## Refuse `Notes/`

Before any write, check that the target path does not fall under any directory marked read-only by the project's `CLAUDE.md`. In this repo:

- `../ValarMindObsidian/Notes/` is read-only — refuse all writes.
- The harness has a hook (`block-notes-write.sh`) and `permissions.deny` as defense-in-depth.

Skill enforces the rule first; the harness backs it up. If you ever encounter a write failure with `Notes/` in the path, do not retry — surface the error to the user.

## Refuse main-doc writes

The brain does not write to the project's main docs (`<project-MOC>.md`, `Arquitetura.md`, `Skills/<slug>/<slug>.md`). Per [SKILL.md Phase 5](../SKILL.md#phase-5--suggest-updating-main-docs):

1. Suggest the update with one line.
2. Wait for user approval.
3. Hand off to `@obsidian-markdown` for syntax and `@obsidian-cli` for the write.

The brain is not a doc-update mechanism. It tracks history and proposes; the human approves.
