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
