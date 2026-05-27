---
name: github-release-note
description: "Generate GitHub Release notes / changelog from tag range. Triggers: 'release notes', 'changelog', 'version notes'."
source: ValarMind Skills
---

# GitHub Release Note

## Goal

Generate release notes following the project's standard, using only real project
information. Compare the current version against the previous version.

## Inputs you must collect before starting

- Project (short name)
- New version (e.g.: v2.4.0)
- Comparison base (e.g.: v2.3.1)
- Repository URL (if you cannot infer it)

**If the user does not provide the comparison base, use the tag immediately before the
new version. If there is no previous tag, use v0.0.0. If the user does not provide the
new version, auto-detect it by running step 0 (git tag discovery), then show the
detected latest tag to the user and confirm before proceeding.**

> [!IMPORTANT]
> **Never trust tag values remembered from earlier in the session or from prior
> conversations.** Tags can be created, deleted, or pushed at any moment — including
> mid-session. Step 0 is mandatory on **every** invocation, even if you already saw
> the "latest tag" minutes ago. Treat any tag value not freshly read from `git` in
> this turn as unknown.

## Procedure

0. **Discover real tags first (mandatory, always re-run, hard gate)** — before
   assuming any version, run these commands **and show their full output to the
   user**:

   ```
   git remote -v
   git fetch --tags --force --prune origin 2>&1
   git tag --sort=-version:refname | head -10
   git describe --tags --abbrev=0 2>/dev/null || echo "(no local tags)"
   gh release view --json tagName,name,publishedAt 2>&1 || echo "(gh release view failed)"
   gh release list --limit 5 2>&1 || echo "(gh release list failed)"
   ```

   **Mandatory cross-checks:**

   a. **Fetch must succeed.** If `git fetch` prints any error (auth, network, no
      remote), STOP and report the exact error to the user. Do not continue with
      stale local tags unless the user explicitly says "use local only".

   b. **Compare local vs. remote.** If `gh release view` returns a tag that is
      newer than `git tag --sort=-version:refname | head -1`, the local clone is
      out of date even after fetch — STOP and tell the user the remote latest
      release tag verbatim. Ask whether they want to (i) pull the tag and retry,
      or (ii) generate notes for a different range.

   c. **Hard assertion on the chosen new version.** Whatever version you are
      about to use as `<NEW>` MUST appear in the output of
      `git tag --sort=-version:refname` from this turn. If it does not appear,
      STOP — do not run any `git rev-list`, `git log`, `git diff --stat`, or
      validation commands against that version. Tell the user the tag is missing
      locally and list the tags that DO exist.

   d. **Forbidden inference sources for `<NEW>`.** Do not pick the new version
      from any of these — they are not source of truth:
      - The `v2.4.0` / `v2.3.1` examples in this skill file (`SKILL.md`, `EXAMPLE.md`).
      - Filenames of existing `release-v*.md` files in the working directory.
      - Versions in `package.json`, `Cargo.toml`, `pyproject.toml`, `go.mod`.
      - Tag values remembered from earlier in the session or prior conversations.
      The only authoritative sources are: `git tag` output (post-fetch) and
      `gh release` output, both produced in the current turn.

   e. **Always print and confirm.** After running the commands, print this block
      verbatim and wait for explicit user confirmation before continuing:

      ```
      Detected:
        - Local latest tag:  <from git tag>
        - Remote latest tag: <from gh release view, or "unknown">
        - Proposed NEW:      <value>
        - Proposed BASE:     <value>
      Confirm to proceed (yes / change).
      ```

   Also look for the most recent `release-v*.md` file in the current directory
   and detect the language it was written in (for language detection only, per
   the Language rule below). The release-note filename is **not** a source of
   truth for the latest tag.

1. Validate that the tags or commits exist in the repository.
2. Collect range metrics: commits, files changed, lines added and removed.
3. Read commits and relevant changes, grouping by topic.
4. Build the final text with an executive summary and sections: New Features, Performance, Refactors, Bug Fixes, Security, Tests, Infrastructure.
5. If there are relevant dependency changes, list them in a table with final versions.
6. List documentation changes (files in docs/ or equivalent).
7. Include contributors extracted from git log.
8. Generate a compare link in GitHub format: `/compare/<BASE>...<NEW>`.
9. Write the final release note to a file named `release-<NEW>.md` in the current
   directory (e.g.: `release-v2.4.0.md`). Use the Write tool to create the file.

## Constraints

- Do not invent features, metrics, or numbers.
- If there is no evidence in git, do not mention it.

## Language rule

- Detect the language of the most recent `release-v*.md` file found in the
  current directory. Write all descriptive content (summaries, bullet text,
  table values, contributor lines) in that same language.
- If no previous release file exists, default to English.
- **Section titles and topic headings** (e.g. `Executive summary`, `New Features`,
  `Bug Fixes`, `Performance`, `Refactors`, `Security`, `Tests`, `Infrastructure`,
  `Dependencies`, `Documentation`, `Contributors`, `Breaking changes`) must always
  remain in English, regardless of the content language.

## Output format

Follow exactly the template in `EXAMPLE.md` (same directory as this skill), adapting
all content to the current project range.

Adaptation rules:

- If a section has no content in the range (e.g.: no Security changes), **omit it**
  entirely — do not include an empty section.
- Keep the section order as shown in the example.
- Replace the fictional project with the real project name.
- Replace fictional metrics with the real metrics collected in step 2 of the
  procedure.
- Use the same writing style: user-centered language, concise bullets, concrete
  numbers where available.

## Example request

"Create release notes for nexus-api v2.4.0 comparing with v2.3.1"
