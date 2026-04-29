> Reference companion for the [obsidian-brain](../SKILL.md) skill.

# Session Lifecycle

The brain has three distinct lifecycle moments. Each has its own decision tree.

## 1. Detection (every session)

Run on every session start, regardless of state.

```
                     ┌─────────────────────────┐
                     │ cwd has CLAUDE.md ?     │
                     └────────────┬────────────┘
                            yes ──┤── no
                                  │     │
                                  ▼     ▼
                          read body   try AGENTS.md
                                  │     │
                                  │     └─── absent ──> walk up to 3 ancestors ──> still absent ──> SILENT SKIP
                                  ▼
                  regex /(\.\./)*[^"\s]*Obsidian[^"\s]*/ matches?
                                  │
                          yes ────┼──── no ──> SILENT SKIP
                                  ▼
                          realpath the match
                                  │
                          fails ──┴── succeeds
                                  │       │
                            SILENT │       ▼
                             SKIP  │   target is a directory and writable?
                                   │       │
                                   │  no ──┴── yes
                                   │       │
                                   │   ABORT  ▼
                                   │ + notify  derive <slug> from immediate child folder
                                   │           (lowercase, kebab-case)
                                   │           │
                                   │           ▼
                                   │   record signals: vaultRoot, brainRoot, indexPath, slug
                                   │           │
                                   │           ▼
                                   │   <indexPath> exists?
                                   │           │
                                   │     no ───┼─── yes
                                   │           │     │
                                   │   PHASE 1 │     PHASE 2
                                   │   bootstrap     load (read-only)
                                   │   (ask first)
```

### Edge cases

| Case | Behavior |
| :--- | :--- |
| `CLAUDE.md` and `AGENTS.md` both exist and disagree on vault path | Prefer `CLAUDE.md`. Surface one-line warning to user about the conflict. |
| Vault path is symlink | Resolve symlink. If target is outside writable area, treat as read-only and abort. |
| `CLAUDE.md` references multiple Obsidian paths | Use first match. Note the others as candidates in the bootstrap report. |
| Vault path falls under a `Notes/` directory or any read-only marker | Abort with notice: "Vault path `<path>` is under a read-only directory per `<CLAUDE.md>`. Skipping." |
| `realpath` returns a non-directory (e.g., a single `.md` file) | Treat the parent as `vaultRoot`. |
| User in nested git repo with parent CLAUDE.md | Walk up no more than 3 levels. First match wins. |
| Resolved path appears to be the vault root (contains `Projetos/` or similar) instead of a project doc folder | Surface ambiguity, ask user to confirm the project subfolder before bootstrapping. |
| `~/`-rooted path in CLAUDE.md (e.g., `~/Documents/MyVault`) | Expand tilde via `os.homedir()` before resolving. The hook does this in `expandTilde`. |

### CLI probe (run once per session)

On the first turn the skill activates, run `obsidian --version 2>/dev/null` exactly once. Cache the result mentally:

- exit 0 → `mode = cli`
- non-zero or not found → `mode = file`

Use the cached `mode` for the rest of the session. Re-probe only if a CLI command unexpectedly fails with "command not found" or similar — and only once even then.

## 2. First run (bootstrap)

Trigger: `<indexPath>` does **not** exist. **If it exists, skip this section entirely** and go to §3 (Subsequent runs). Re-bootstrap is reserved for explicit user request only.

Sequence (must be in this order):

1. **Confirm with user.** Single yes/no, asked at most once per session. If no, exit silently for the rest of the session and remember the refusal — do not re-prompt on subsequent turns.

   **When to ask** (mirrors [SKILL.md Phase 1 timing rule](../SKILL.md#phase-1--bootstrap-first-run)):
   - **Default (every session, including auto mode)** — ask immediately after Phase 0 detection succeeds, as the **first user-facing sentence** of the next response. Auto mode does not suppress the question. Phase 1 is eager-ask, lazy-write: the actual `mkdir` + seed runs only after a yes.
   - **Mid-task exception (rare)** — defer only when another skill has an actual interactive prompt on screen waiting for input. Do not defer to vague "natural pauses" — that is the failure mode that left brains uncreated.
   - **Phase 3 race guard** — if a write trigger (session, topic, decision) fires before the question was answered, ask now and block the write until the user responds.
   - **Phase 4 entry guard** — Phase 4 is gated on Phase 1. If end-of-session fires before Phase 1 was answered AND the session had substantive work, ask now before any sync action.
   - **Re-injection** — if the SessionStart hook re-fires while the deferral is still pending, resume the same one-shot intent; do not ask twice and do not re-defer indefinitely.
   - **Refusal is sticky** — a "no" persists for the rest of the session even across hook re-injections.
2. **Probe `@obsidian-cli`.** Set `mode = cli` if `obsidian --version` exits 0; else `mode = file`. Cache for the session.
3. **Create directory tree.** See [SKILL.md Phase 1](../SKILL.md#phase-1--bootstrap-first-run) for exact commands per mode.
4. **Seed index from template.** Template lives in [STRUCTURE.md](STRUCTURE.md#index-template). Token budget: ≤500 total, ≤150 in critical-facts callout. Brain stays out of the project doc graph — **do not modify any file outside `brain/`** during bootstrap (no wikilink into the project MOC, no edit of `Arquitetura.md`, etc.).
5. **Report bootstrap.** Use the [Output format](../SKILL.md#output-format) from `SKILL.md`.

If any step fails, abort the rest. Do not leave a partial bootstrap on disk — clean up created directories.

## 3. Subsequent runs (load)

Trigger: `<indexPath>` exists.

Sequence:

1. **Read the index only.** No sessions, topics, or decisions are loaded preemptively.
2. **Match wikilinks against the user prompt.** Use simple substring + tag heuristics — do not invoke an LLM call for matching, just textual overlap.
3. **Lazy-load matched targets one at a time.** Stop the moment context is sufficient.
4. **Do not write anything yet.** Writes are reserved for [Phase 3](../SKILL.md#phase-3--operate-write-strategy).

## 4. End-of-session sync

Trigger signals (any one):

- User typed `/clear` or `/exit`.
- User typed natural-language goodbye: `obrigado`, `encerrar`, `tchau`, `done`, `that's it`.
- A substantial multi-turn task just finished and the user said `pronto`, `done`, `merged`, etc.
- The harness about to compress or close the session (rare).

Actions, in order:

1. Decide if the session **is worth a note**:
   - Worth a note: architectural insight discovered, decision made, refactor planned, gotcha encountered, multi-turn task completed.
   - Not worth: informational chat, single-line edit, "what does X do" with no follow-up.
2. If worth → append `> [!summary]` callout to today's session note (`brain/sessions/YYYY-MM-DD-<slug>.md`). Create the file if first write of the day. ≤30 lines, ≤6 bullets.
3. Surgical property updates on touched topics: `obsidian property:set name="updated" value="YYYY-MM-DD" file="<topic>"`.
4. Refresh "Recent sessions" wikilink list in the index. Drop entries older than 10.
5. Suggest synthesis if a topic appears in 3+ recent sessions without a corresponding topic note. One line, do not auto-execute.

## 5. Synthesize (on-demand only)

Trigger: user runs `/valarmindskills:obsidian-brain synthesize` or accepts a suggestion.

Sequence:

1. Identify candidates: topics referenced in 3+ session notes without an existing `topics/<topic>.md` note, or topic notes with `updated` older than 30 days that have new session evidence.
2. For each candidate, propose a draft topic note (atomic, ≤80 lines, bullets + wikilinks). Show the diff to the user.
3. On approval, write via `@obsidian-cli`. Update the session notes' frontmatter `topics:` array to include the new wikilink.
4. Report what was synthesized.

This phase is **never automatic**. The user must trigger it.

## 6. Termination

The brain has no termination hook of its own — it shares the harness's `SessionEnd`. The end-of-session sync (Phase 4 above) is the only durable artifact.
