---
name: github-release-note
description: Use this skill when I ask to create release notes, generate a changelog, write version notes, or prepare text for a GitHub Release from a tag range.
source: ValarMind Skills
---

# GitHub Release Note

## Goal

Generate release notes following the project's standard, using only real project information. Compare the current version against the previous version.

## Inputs you must collect before starting

- Project (short name)
- New version (e.g.: v1.5.0)
- Comparison base (e.g.: v1.1.1)
- Repository URL (if you cannot infer it)

**If the user does not provide the comparison base, use the tag immediately before the new version. If there is no previous tag, use v0.0.0. If the user does not provide the new version, ask which version it is.**

## Procedure

1. Validate that the tags or commits exist in the repository.
2. Collect range metrics: commits, files changed, lines added and removed.
3. Read commits and relevant changes, grouping by topic.
4. Build the final text with an executive summary and sections: New Features, Performance, Refactors, Bug Fixes, Security, Tests, Infrastructure.
5. If there are relevant dependency changes, list them in a table with final versions.
6. List documentation changes (files in docs/ or equivalent).
7. Include contributors extracted from git log.
8. Generate a compare link in GitHub format: /compare/<BASE>...<NEW>.

## Constraints

- Do not invent features, metrics, or numbers.
- If there is no evidence in git, do not mention it.

## Output format

Follow exactly the template in `EXAMPLE.md` (same directory as this skill), adapting all content to the current project range.

Adaptation rules:
- If a section has no content in the range (e.g.: no Security changes), **omit it** entirely — do not include an empty section.
- Keep the section order as shown in the example.
- Replace the fictional project with the real project name.
- Replace fictional metrics with the real metrics collected in step 2 of the procedure.
- Use the same writing style: user-centered language, concise bullets, concrete numbers where available.

## Example request

"Create release notes for ibvi-odin v1.6.0 comparing with v1.5.0"
