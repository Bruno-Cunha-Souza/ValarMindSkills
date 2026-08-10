# Third-Party Notices

## caveman (Julius Brussee)

The files in `hooks/caveman/` (`caveman-activate.js`, `caveman-mode-tracker.js`, `caveman-config.js`) and the caveman statusline segment at `hooks/statusline/segments/caveman.sh` are ported from [JuliusBrussee/caveman](https://github.com/JuliusBrussee/caveman) and retain the original MIT license. The three `skills/caveman*/` skills were also modeled on the upstream project.

```
MIT License

Copyright (c) 2024 Julius Brussee

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Modifications from upstream

- Dropped wenyan (Classical Chinese) modes.
- Dropped `compress` mode / `caveman-compress` skill.
- Adjusted slash-command regex to match plugin-namespaced `/valarmindskills:caveman*` (and legacy `/valarmind:caveman*`) in addition to bare `/caveman*`.
- Added Portuguese (pt-BR) activation/deactivation phrases to the natural-language matchers (`ative caveman`, `modo caveman`, `parar caveman`, `modo normal`).
- Filter logic in `hooks/caveman/caveman-activate.js` adapted to the `skills/caveman/SKILL.md` table format used in this repository.

## ponytail (Dietrich Gebert)

The files in `hooks/ponytail/` (`ponytail-activate.js`, `ponytail-mode-tracker.js`, `ponytail-subagent.js`, `ponytail-instructions.js`, `ponytail-config.js`) and the ponytail statusline segment at `hooks/statusline/segments/ponytail.sh` are ported from [DietrichGebert/ponytail](https://github.com/DietrichGebert/ponytail) and retain the original MIT license. The `skills/ponytail/` and `skills/ponytail-review/` skills were also modeled on the upstream project.

```
MIT License

Copyright (c) 2026 DietrichGebert

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

### Modifications from upstream

- Hooks rewritten in the local caveman idiom: shared `_lib/resolve-skill-path.js` resolver, symlink-safe flag write/read (`safeWriteFlag`/`readFlag`), `CLAUDE_CONFIG_DIR` flag placement — instead of upstream's `ponytail-runtime.js` Codex/Copilot runtime switches.
- Upstream's `ponytail-review`, `ponytail-audit`, and `ponytail-debt` skills consolidated into a single `skills/ponytail-review/` skill with a scope argument (diff / repo / debt). `ponytail-gain` (benchmark scoreboard) and `ponytail-help` (reference card) intentionally not ported.
- `review` dropped from the persistent-mode whitelist — `ponytail-review` is a one-shot skill here, not a mode.
- Adjusted slash-command regex to match plugin-namespaced `/valarmindskills:ponytail*` (and legacy `/valarmind:ponytail*`) in addition to bare `/ponytail*`.
- Added Portuguese (pt-BR) activation/deactivation phrases to the natural-language matchers (`ative ponytail`, `modo ponytail`, `parar ponytail`, `modo normal`).
- Statusline nudge centralized in `caveman-activate.js` (shared composer statusline); the ponytail activate hook does not emit its own nudge.
- Filter logic reads `skills/ponytail/SKILL.md` (backtick-labeled intensity table, one worked example per row) instead of upstream's bold-labeled table + example bullets.

## superpowers (Jesse Vincent)

The files in `hooks/superpowers/` (`superpowers-activate.js`, `superpowers-mode-tracker.js`, `superpowers-config.js`), the superpowers statusline segment at `hooks/statusline/segments/superpowers.sh`, and the `skills/superpowers/` skill are inspired by [obra/superpowers](https://github.com/obra/superpowers) and follow its MIT license. The implementation in this repository was rewritten from scratch for the ValarMindSkills idiom; the upstream project is credited for the conceptual posture (1% rule, instruction hierarchy, four pillars, twelve red flags, seven-stage workflow).

```
MIT License

Copyright (c) 2025 Jesse Vincent

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

### Modifications from upstream

- Replaced the install/uninstall binary toggle with a session flag-file model (`~/.claude/.superpowers-active`) plus `SessionStart` + `UserPromptSubmit` hooks, mirroring the local caveman pattern.
- Default mode is `off` (upstream is "active when installed"). Activation requires `SUPERPOWERS_DEFAULT_MODE=on`, `~/.config/superpowers/config.json`, or a per-session slash command.
- Slash command grammar is `on|off` (binary). No `lite/full/ultra` invented variants.
- Injected posture is a compressed digest, not the full upstream `using-superpowers` SKILL.md.
- Added Portuguese (pt-BR) activation/deactivation phrases to the natural-language matchers (`ative superpowers`, `modo superpowers`, `desativar superpowers`).
- Upstream's sixteen top-level skills are condensed into thirteen reference companions inside `skills/superpowers/references/` (one per upstream skill, except `using-superpowers` which is encoded directly in `SKILL.md`). The capabilities that already exist as ValarMind skills (`@code-review`, `@github-pr-review`, `@clean-code`, `@code-debugger`, `@skill-creator`) are referenced rather than duplicated.

### Reference companions ported from upstream skills

Each file under `skills/superpowers/references/` is a condensed port of one upstream skill, preserving the iron laws and killer quotes verbatim:

| Reference | Upstream skill |
| :--- | :--- |
| `TDD.md` | `test-driven-development` |
| `SYSTEMATIC_DEBUGGING.md` | `systematic-debugging` |
| `VERIFICATION.md` | `verification-before-completion` |
| `BRAINSTORMING.md` | `brainstorming` |
| `WRITING_PLANS.md` | `writing-plans` |
| `EXECUTING_PLANS.md` | `executing-plans` |
| `SUBAGENT_DRIVEN.md` | `subagent-driven-development` |
| `DISPATCHING_PARALLEL.md` | `dispatching-parallel-agents` |
| `REQUESTING_REVIEW.md` | `requesting-code-review` |
| `RECEIVING_REVIEW.md` | `receiving-code-review` |
| `GIT_WORKTREES.md` | `using-git-worktrees` |
| `FINISHING_BRANCH.md` | `finishing-a-development-branch` |
| `WRITING_SKILLS.md` | `writing-skills` |

## mcp-builder (Anthropic)

The `skills/mcp-builder/` skill is derived from [anthropics/skills/skills/mcp-builder](https://github.com/anthropics/skills/tree/main/skills/mcp-builder), which is licensed under the Apache License, Version 2.0. This is the only Apache-licensed upstream in this repository; the full license text is not reproduced here, but the notice below is retained as required by §4 of that license.

```
Copyright 2026 Anthropic, PBC.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
```

Upstream license text: <https://github.com/anthropics/skills/blob/main/skills/mcp-builder/LICENSE.txt>

### Modifications from upstream

- Rewritten into the ValarMindSkills Lifecycle archetype: three-field frontmatter (upstream's `license:` field stripped per repository convention), `SKILL.md` reduced to a phase router with the deep content pushed into `references/`.
- **Rust added and made the default language.** Upstream covers only Python and TypeScript and recommends TypeScript; `references/RUST.md` (`rmcp`, tool router macros, `ToolAnnotations`, `StreamableHttpServerConfig`) has no upstream equivalent and was written for this port.
- **Transport guidance rewritten for protocol revision `2026-07-28`**, which removed protocol-level sessions and resumable SSE streams. Upstream's guides still describe stateful sessions and the deprecated HTTP+SSE transport.
- **The Python evaluation harness was not ported.** Upstream's `scripts/` (`evaluation.py`, `connections.py`, `example_evaluation.xml`, `requirements.txt`) would require a Python dependency and an `ANTHROPIC_API_KEY` to run a loop the invoking agent already performs, and `scripts/` inside a skill is an anti-pattern in this repository. Phase 4 runs through the agent instead, keeping the question rules, the XML format, and the good/poor question catalog intact.
- Reference companions renamed to the repository's `UPPERCASE.md` convention and given the standard breadcrumb header.

| Reference | Upstream file |
| :--- | :--- |
| `BEST_PRACTICES.md` | `reference/mcp_best_practices.md` |
| `TYPESCRIPT.md` | `reference/node_mcp_server.md` |
| `PYTHON.md` | `reference/python_mcp_server.md` |
| `EVALUATION.md` | `reference/evaluation.md` (harness sections removed) |
| `RUST.md` | — (no upstream equivalent) |
