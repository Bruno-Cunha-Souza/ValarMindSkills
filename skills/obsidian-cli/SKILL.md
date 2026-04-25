---
name: obsidian-cli
description: Interact with Obsidian vaults using the Obsidian CLI to read, create, search, and manage notes, tasks, properties, and more. Also supports plugin and theme development with commands to reload plugins, run JavaScript, capture errors, take screenshots, and inspect the DOM. Use when the user asks to interact with their Obsidian vault, manage notes, search vault content, perform vault operations from the command line, or develop and debug Obsidian plugins and themes.
source: https://github.com/kepano/obsidian-skills
---

# Obsidian CLI

Use the `obsidian` CLI to interact with a running Obsidian instance. Requires Obsidian to be open.

## Command reference

Run `obsidian help` to see all available commands. This is always up to date. Full docs: <https://help.obsidian.md/cli>

## Syntax

**Parameters** take a value with `=`. Quote values with spaces:

```bash
obsidian create name="My Note" content="Hello world"
```

**Flags** are boolean switches with no value:

```bash
obsidian create name="My Note" silent overwrite
```

For multiline content use `\n` for newline and `\t` for tab.

## File targeting

Many commands accept `file` or `path` to target a file. Without either, the active file is used.

- `file=<name>` — resolves like a wikilink (name only, no path or extension needed)
- `path=<path>` — exact path from vault root, e.g. `folder/note.md`

## Vault targeting

Commands target the most recently focused vault by default. Use `vault=<name>` as the first parameter to target a specific vault:

```bash
obsidian vault="My Vault" search query="test"
```

## Common patterns

```bash
obsidian read file="My Note"
obsidian create name="New Note" content="# Hello" template="Template" silent
obsidian append file="My Note" content="New line"
obsidian search query="search term" limit=10
obsidian daily:read
obsidian daily:append content="- [ ] New task"
obsidian property:set name="status" value="done" file="My Note"
obsidian tasks daily todo
obsidian tags sort=count counts
obsidian backlinks file="My Note"
```

Use `--copy` on any command to copy output to clipboard. Use `silent` to prevent files from opening. Use `total` on list commands to get a count.

## Documentation search patterns

The CLI is the **primary mechanism** for searching project documentation that lives in the vault — MOCs, skill notes, architecture docs, references, daily notes. Prefer it over `grep`/`find`/`Read` because it resolves wikilinks and aliases, respects the vault index (faster on large vaults), and emits paste-ready output via `--copy`.

> [!warning] Verify before first use
> Some flag combinations below are not exemplified upstream and the CLI evolves. Run `obsidian help search` (or `help backlinks`, `help tags`) **once** before first use of any row tagged **(verify)**. If the combo errors, drop to the file-IO fallback in the last row of each pattern — never guess flags.

### Probe once per session

```bash
obsidian --version 2>/dev/null && echo "cli=on" || echo "cli=off"
```

Cache the result. If `cli=off`, every recipe below has a `grep`/`find`/`Read` fallback.

### Recipes by intent

| Intent | CLI command | Confidence | Fallback |
| :--- | :--- | :--- | :--- |
| Read a note by name (alias-aware) | `obsidian read file="<note-name>" silent` | exemplified | `Read` tool on absolute path |
| Read a note by exact path | `obsidian read path="Folder/Note.md" silent` | exemplified | `Read` tool |
| Full-text search across the vault | `obsidian search query="<term>" limit=10` | exemplified | `grep -rn '<term>' <vaultRoot>` |
| Scope search to one folder | `obsidian search query="<term>" path="<folder>"` | **verify** | `grep -rn '<term>' <vaultRoot>/<folder>` |
| Filter by hierarchical tag (parent + children) | `obsidian search tag="skill"` or `tag="skill/segurança-api"` | **verify** | `grep -lrn '^  - skill' <vaultRoot>` |
| Filter by language tag | `obsidian search tag="lang/go"` | **verify** | `grep -lrn '^  - lang/go' <vaultRoot>` |
| Filter by frontmatter property (exact value) | `obsidian search property="type=skill"` | **verify** | `grep -lrn '^type: skill$' <vaultRoot>` |
| Combine tag + property | `obsidian search tag="skill" property="status=stable"` | **verify** | `grep` chain (`grep -l ... \| xargs grep -l ...`) |
| Count without listing content | append `total` — e.g., `obsidian search tag="skill" total` | exemplified for tags, **verify** for property | `grep -lrn ... \| wc -l` |
| List all tags in vault with counts | `obsidian tags sort=count counts` | exemplified | `grep -hr '^  - ' <vaultRoot> \| sort \| uniq -c \| sort -rn` |
| Find what links to a note (graph-aware) | `obsidian backlinks file="<note-name>"` | exemplified | `grep -lrn '\[\[<note-name>\]\]\|\[\[<note-name>|' <vaultRoot>` |
| Resolve aliases | `obsidian read file="<alias>" silent` (the CLI walks the alias index) | exemplified | (CLI required — aliases are not visible to plain `grep`) |
| Copy result to clipboard | append `--copy` to any read/search | exemplified | `... \| pbcopy` (macOS) / `... \| xclip` (Linux) |

### Targeting the right vault

If multiple vaults are open, lead the command with `vault="<name>"`:

```bash
obsidian vault="ValarMindObsidian" search query="auth middleware" path="Projetos/ValarMindSkills"
```

Otherwise the most recently focused vault is used.

### Token economy

| Flag | Why |
| :--- | :--- |
| `silent` | Prevents the vault from refocusing files in the UI — avoids losing the user's context. |
| `total` | Returns a count instead of full content. Use when the question is "how many?" not "which?". |
| `limit=N` | Caps `search` output at N hits. Default usually high enough to truncate large queries. |
| `--copy` | Sends output to clipboard instead of stdout. Use when the user asked for paste-ready text. |

Pair `total` with `tag` or `property` filters before `read` — confirm the cohort size first, then iterate only on the relevant subset.

### Read-only folder reminder

Some projects mark folders as **read-only** via `CLAUDE.md` (e.g., `Notes/`, `Inbox/`). Read-only ≠ search-only — searches MAY include them and `obsidian read`/`backlinks` work fine; **writes** (`create`, `append`, `property:set`) must refuse those paths and surface the conflict. Always re-check the project's `CLAUDE.md` before any write under such a folder.

### Project-memory use case

When the project keeps a knowledge graph at `<vault>/<project>/brain/` (sessions, topics, decisions), see `@obsidian-brain` for the routing strategy between brain queries and general-doc queries. The CLI commands above are the I/O mechanism; `@obsidian-brain` is the orchestration layer.

## Plugin development

### Develop/test cycle

After making code changes to a plugin or theme, follow this workflow:

1. **Reload** the plugin to pick up changes:

   ```bash
   obsidian plugin:reload id=my-plugin
   ```

2. **Check for errors** — if errors appear, fix and repeat from step 1:

   ```bash
   obsidian dev:errors
   ```

3. **Verify visually** with a screenshot or DOM inspection:

   ```bash
   obsidian dev:screenshot path=screenshot.png
   obsidian dev:dom selector=".workspace-leaf" text
   ```

4. **Check console output** for warnings or unexpected logs:

   ```bash
   obsidian dev:console level=error
   ```

### Additional developer commands

Run JavaScript in the app context:

```bash
obsidian eval code="app.vault.getFiles().length"
```

Inspect CSS values:

```bash
obsidian dev:css selector=".workspace-leaf" prop=background-color
```

Toggle mobile emulation:

```bash
obsidian dev:mobile on
```

Run `obsidian help` to see additional developer commands including CDP and debugger controls.
