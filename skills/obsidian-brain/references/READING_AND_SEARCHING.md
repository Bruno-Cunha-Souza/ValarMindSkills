> Reference companion for the [obsidian-brain](../SKILL.md) skill.

# Reading and Searching

How to consume the brain without burning tokens.

## Core discipline: lazy-load

The brain is a **pointer-based** memory. The index lists wikilinks; you follow them only when relevant to the current prompt.

**Always:**

- Read the index first. Stop. Match against the current prompt.
- Load one note at a time. Stop the moment context is sufficient.
- Prefer search by tag/property over reading multiple files.
- Quote only the `> [!summary]` "Critical facts" callout from the index. Everything else is a hyperlink.

**Never:**

- "Just read the whole `brain/` directory to be safe." That destroys the entire token-economy benefit.
- Load all sessions to "find the relevant one." Use `obsidian search` instead.
- Re-read the same note twice in one session.

## CLI command catalog (primary path)

The `@obsidian-cli` is the **primary I/O mechanism** for every operation.

> [!warning] Ground truth is `obsidian help`
> The shapes below are the **preferred form** based on `skills/obsidian-cli/SKILL.md` and the public CLI docs at <https://help.obsidian.md/cli>. The CLI evolves — flags marked **(verify)** below were not exemplified in the local `obsidian-cli` skill. Always run `obsidian help <subcommand>` once per session to confirm the exact syntax for any command tagged **(verify)** before using it. If a command fails, use the file-IO fallback in [§ Fallback chain](#fallback-chain-cli-unavailable) — never invent flags.

| Operation | Command | Confidence |
| :--- | :--- | :--- |
| Read a note (by name) | `obsidian read file="<note-name>"` | exemplified |
| Read a note (by path) | `obsidian read path="brain/topics/<topic>.md"` | exemplified |
| Search full-text | `obsidian search query="<term>" limit=10` | exemplified |
| Search by tag | `obsidian search tag="brain/session"` | **verify** |
| Search by property | `obsidian search property="type=brain-decision"` | **verify** |
| Search by property value | `obsidian search property="status=accepted"` | **verify** |
| List all tags in vault | `obsidian tags sort=count counts` | exemplified |
| List notes with a tag (count) | `obsidian search tag="brain-topic" total` | **verify** (combines two verify-flags) |
| Backlinks of a note | `obsidian backlinks file="<topic>"` | exemplified |

Pair `--copy` with any read/search to copy output to clipboard. Add `silent` to suppress focus changes.

For any **verify** row that fails: drop directly to the file-IO fallback below — do not retry with a guessed flag.

### Resolving wikilinks

Use `file=` (no path, no extension) when the wikilink is unambiguous in the vault:

```bash
obsidian read file="rsc-rendering"
```

Use `path=` when there is ambiguity (e.g., `topic` and `decision` with same slug):

```bash
obsidian read path="brain/topics/auth.md"
```

### Targeting the right vault

If the user has multiple vaults open, lead with `vault=`:

```bash
obsidian vault="ValarMindObsidian" search tag="brain/session"
```

Otherwise the command targets the most recently focused vault, which is usually correct.

## Probing CLI availability

Run on session start, cache the result:

```bash
obsidian --version 2>/dev/null && echo "cli=on" || echo "cli=off"
```

If `cli=off`, switch to fallback. Notify the user once: `obsidian-brain: CLI indisponível, usando file IO direto.`

## Fallback chain (CLI unavailable)

When the CLI probe fails, every command above maps to a file-IO equivalent. Functionality is preserved; you lose wikilink resolution and surgical property updates.

| CLI command | File-IO fallback |
| :--- | :--- |
| `obsidian read file="X"` | `Read` tool on `<brainRoot>/topics/X.md` (or wherever X resolves; may need to grep) |
| `obsidian read path="P"` | `Read` tool on absolute path |
| `obsidian search query="T"` | `Bash`: `grep -rn 'T' <brainRoot>` (or `rg 'T' <brainRoot>` if ripgrep available) |
| `obsidian search tag="brain/session"` | `Bash`: `grep -lrn '^  - brain/session' <brainRoot>` |
| `obsidian search property="type=brain-decision"` | `Bash`: `grep -lrn '^type: brain-decision' <brainRoot>/decisions/` |
| `obsidian tags list` | `Bash`: `grep -hr '^  - ' <brainRoot> \| sort -u` |
| `obsidian backlinks file="X"` | `Bash`: `grep -lrn '\[\[X\]\]\|\[\[X|' <brainRoot>` |

Always wrap the absolute path in quotes — paths inside the vault may contain spaces (e.g., `Manual de Uso`).

## Token-economy rules

| Rule | Budget |
| :--- | :--- |
| Index file size | ≤500 tokens (≈350 words) |
| Critical-facts callout | ≤150 tokens (≈105 words) |
| Single session note size | ≤30 lines |
| Single topic note size | ≤80 lines |
| Single decision note size | ≤60 lines |
| Reads per session start | 1 (index only) |
| Lazy-load reads per turn | ≤3, only when relevant |

Validate with:

```bash
wc -w <brainRoot>/<slug>-brain.md           # ≤350
wc -l <brainRoot>/sessions/*.md             # each ≤30
```

If any file exceeds budget, propose a synthesis (see [SESSION_LIFECYCLE.md §5](SESSION_LIFECYCLE.md)).

## Query patterns

### "What was decided about X?"

```bash
# Find ADRs touching topic X
obsidian search query="X" tag="brain/adr" limit=5

# Or list all decisions and filter
obsidian search property="type=brain-decision" total
```

### "When did we discuss Y?"

```bash
# Sessions referencing topic Y
obsidian backlinks file="Y"
```

### "Recent activity in area Z"

```bash
# All notes tagged topic/Z, sorted by updated.
# search tag= is a verify-flag — confirm with `obsidian help search` first.
obsidian search tag="topic/Z"
# Fallback (no CLI):
grep -lrn '^  - topic/Z' "<brainRoot>"
```

### "Open todos across the brain"

```bash
# Pending tasks anywhere
obsidian search query="> [!todo]"
```

## brain.base (optional dashboard)

When the user wants a visual dashboard, hand off to `@obsidian-bases` to write `<brainRoot>/brain.base`. Suggested view set:

- **Recent sessions** — table sorted by `date DESC`, columns: date, topics, decisions.
- **Topics** — cards, grouped by `topic/<area>`.
- **Open decisions** — table filtered to `status=accepted`, sorted by `decision_id ASC`.
- **Superseded decisions** — table filtered to `status=superseded`, hidden by default.

Reload the vault with `obsidian plugin:reload id=bases` if the base does not appear after creation.

The base file is an optional ergonomic layer — the brain is fully usable without it.

## What NOT to put in the index

The index is a router, not a reservoir. Refuse to add:

- Long prose answers (link to a topic note instead).
- Ephemeral session details (those go in `sessions/`).
- Code blocks (link to source, do not copy).
- User preferences (those belong in the harness's auto-memory, not here).
- Anything already in the project's main docs (`<project-MOC>`, `Arquitetura.md`, etc.) — link instead.

The index lives or dies by being short. Anything beyond pointers, tags, and the critical-facts callout breaks the design.
