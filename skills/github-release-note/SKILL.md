---
name: github-release-note
description: Use this skill when I ask to create release notes, generate a changelog, write version notes, or prepare text for a GitHub Release from a tag range.
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

## Procedure

0. **Discover real tags first** — before assuming any version, run:
   ```
   git tag --sort=-version:refname | head -10
   ```
   If GitHub CLI is available, also run `gh release list --limit 5`.
   Use this output to determine the actual latest tag. **Do NOT infer versions
   from examples in this skill — always read from the repository.**
   Also look for the most recent `release-v*.md` file in the current directory
   and detect the language it was written in. Use that language for all
   descriptive content in the new release note (see Language rule below).

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
