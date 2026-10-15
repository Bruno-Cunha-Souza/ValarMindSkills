> Reference companion for the [celebrimbor](../SKILL.md) skill.

# Checklist

Phase 5 walks every item from the target root. A failing item blocks the report until it is fixed or recorded as skipped with a reason; every output line of the bash block below is a failure, except `rm -rf` hits scoped to `"$OUT_DIR"`. Formats: [ARTIFACT_FORMATS](ARTIFACT_FORMATS.md).

## Profile

- [ ] Every non-null profile field carries `evidence: file:line`
- [ ] Gaps are recorded as `file (absent)`, not dropped

## Suggestions

- [ ] Every row has all schema fields: `id`, `type`, `name`, `family`, `priority`, `rationale`, `evidence`, `triggers`, `depends_on`, `uses_existing`, `portability`, `generates`, `status`
- [ ] `evidence` is non-empty on every row
- [ ] Dedupe applied: a name or `family`+`type` already in `existing_skills` / `existing_agents` is an `extend` row, `skipped` by default
- [ ] The approval list the user gave (IDs) is recorded; only `approved` rows were generated

## Generated skills

- [ ] Frontmatter parses with `yaml.safe_load` and holds only `name`, `description`, `source: celebrimbor`
- [ ] `name` equals the directory name (kebab, ≤64, no `claude` / `anthropic`)
- [ ] `description` is third person and ends with `Triggers: '...', '/<name>'.` (PT and EN)
- [ ] Every `references/*.md` opens with the companion banner

## Agent role files

- [ ] Frontmatter parses; `name` equals the file basename; `description` carries triggers
- [ ] No `tools:` key
- [ ] Every entry in `skills:` resolves to `.agents/skills/<name>/SKILL.md`; every `scripts:` path exists

## AGENTS.md block

- [ ] Exactly one `<!-- CELEBRIMBOR BEGIN` and one `<!-- CELEBRIMBOR END -->` marker
- [ ] Idempotent: content outside the markers is byte-identical before and after the run (re-running leaves it unchanged)

## Tool scripts

- [ ] `bash -n` passes on every `scripts/*.sh`
- [ ] Forbidden-token grep is clean; any `rm -rf` hit targets `"$OUT_DIR"` only
- [ ] Every active script (sends traffic / reads `TARGET`) has the `I_HAVE_AUTHORIZATION=1` check and the exact-host gate from ARTIFACT_FORMATS §6 (scheme, path/query/fragment, userinfo, port stripped before the `case`)
- [ ] No prefix glob in any gate (`localhost*`, `127.0.0.1*`, `*.test*`): a hit is a failure, since it accepts `localhost.evil.com`
- [ ] Matched secret values are redacted before reaching `findings.jsonl`; raw tool reports holding values are deleted
- [ ] `out/` is gitignored (script writes `$OUT_DIR/.gitignore`)

## Adapters

- [ ] Every symlink under `.claude/` and `.cursor/` resolves; fallback copies match `.agents/` (`diff -rq` clean)
- [ ] `.agent/skills/<name>/` (Antigravity) is a copy, never a symlink, and in sync

## Overwrite

- [ ] No existing file was overwritten without a shown diff and an explicit yes; declined files are listed as skipped; `CLAUDE.md` was touched only after its own yes, never created

## Prompt audit

- [ ] Each generated SKILL.md and agent file has an audit line, or `prompt audit: skipped — not available`

## Mechanical checks

Run with `bash`, never zsh (zsh aborts a line on an unmatched glob). Export `PRE_HASH` from the report file first (empty if AGENTS.md did not exist before Phase 3).

```bash
python3 - .agents/skills/*/SKILL.md .agents/agents/*.md <<'PY'   # frontmatter, name == dir, triggers, tools:, paths
import os, sys, yaml
for p in (a for a in sys.argv[1:] if os.path.isfile(a)):
    t, agent = open(p).read(), "/agents/" in p
    want = os.path.basename(p)[:-3] if agent else os.path.basename(os.path.dirname(p))
    try: fm = yaml.safe_load(t.split("\n---", 1)[0][4:]) if t.startswith("---\n") else None
    except yaml.YAMLError: fm = None
    if not isinstance(fm, dict): print("FRONTMATTER:", p); continue
    d = str(fm.get("description", ""))
    errs = [m for m, bad in [("name != " + want, fm.get("name") != want), ("tools: key", agent and "tools" in fm),
            ("no triggers", "Triggers:" not in d and not (agent and "Use when:" in d))] if bad]
    errs += [f"missing {k} {v}" for k, f in (("skills", ".agents/skills/{}/SKILL.md"), ("scripts", "{}")) for v in (fm.get(k) or []) if not os.path.isfile(f.format(v))]
    for e in errs: print(f"{p}: {e}")
PY
for r in .agents/skills/*/references/*.md; do [ -f "$r" ] && ! head -1 "$r" | grep -q '^> Reference companion for the \[' && echo "BANNER: $r"; done
for s in .agents/skills/*/scripts/*.sh; do [ -f "$s" ] && { bash -n "$s" || echo "SYNTAX: $s"; }; done
grep -nE 'rm -rf|git (push|reset --hard|clean)|sudo |chmod 777|(curl|wget)[^|]*\| *(ba)?sh|DROP |TRUNCATE ' .agents/skills/*/scripts/* 2>/dev/null
grep -nE '(localhost|127\.0\.0\.1|\.test)\*' .agents/skills/*/scripts/* 2>/dev/null && echo "PREFIX GLOB in gate"
active=$(grep -lE 'TARGET|curl |wget |zap-baseline' .agents/skills/*/scripts/*.sh 2>/dev/null)
[ -z "$active" ] || for pat in 'I_HAVE_AUTHORIZATION:-}" = "1"' 'host="${host%%[/?#]*}"' "localhost|127.0.0.1|'[::1]'|*.localhost|*.test)"; do
  for f in $(grep -LF "$pat" $active); do echo "NO GATE: $f lacks $pat"; done; done
grep -L '\.gitignore' .agents/skills/*/scripts/run.sh 2>/dev/null | sed 's/^/OUT NOT IGNORED: /'
find -L .claude .cursor .agent -type l 2>/dev/null | sed 's/^/BROKEN LINK: /'   # -L: only dangling links stay type l (GNU + BSD)
for d in .claude/skills/* .cursor/skills/* .agent/skills/*; do if [ -L "$d" ]; then case $d in .agent/*) echo "ANTIGRAVITY SYMLINK: $d" ;; esac; elif [ -d "$d" ]; then diff -rq ".agents/skills/${d##*/}" "$d"; fi; done
[ ! -f AGENTS.md ] || [ "$(grep -cE '^<!-- CELEBRIMBOR (BEGIN|END)' AGENTS.md)" = 2 ] || echo "MARKERS: expected exactly 2"
[ -z "${PRE_HASH:-}" ] || [ "$(sed '/^<!-- CELEBRIMBOR BEGIN/,/^<!-- CELEBRIMBOR END -->/d' AGENTS.md | awk 'NF{for(;n;n--)print "";print;next}{n++}' | shasum)" = "$PRE_HASH" ] || echo "OUTSIDE-MARKERS CHANGED"
```
