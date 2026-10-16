> Reference companion for the [celebrimbor](../SKILL.md) skill.

# Checklist

Phase 5 walks every item from the target root. A failing item blocks the report until it is fixed or recorded as skipped with a reason; every output line of the bash block below is a failure, except `rm -rf` hits scoped to `"$OUT_DIR"` and `skip:` lines (record those as skipped with their reason). Formats: [ARTIFACT_FORMATS](ARTIFACT_FORMATS.md).

## Profile

- [ ] Every non-null profile field carries `evidence: file:line`
- [ ] Gaps are recorded as `file (absent)`, not dropped

## Suggestions

- [ ] Every row has all schema fields: `id`, `type`, `name`, `family`, `priority`, `rationale`, `evidence`, `triggers`, `depends_on`, `uses_existing`, `portability`, `generates`, `status`
- [ ] `evidence` is non-empty on every row
- [ ] Both `review` baseline rows are present (`code-review`, `code-security-review`, or `<project>-` prefixed when an installed skill has the name), `proposed` or dedupe `skipped`
- [ ] Dedupe applied: a `name` already in `existing_skills` / `existing_agents` is an `extend` row, `skipped` by default; overlapping artifacts under other names appear in `uses_existing` with `path:line`, never as a silent drop
- [ ] The approval list the user gave (IDs) is recorded; only `approved` rows were generated

## Generated skills

- [ ] Frontmatter parses with `yaml.safe_load` (skipped when PyYAML is absent) and holds only `name`, `description`, `source: celebrimbor`
- [ ] `name` equals the directory name (kebab, ≤64, no `claude` / `anthropic`)
- [ ] `description` is third person and ends with `Triggers: '...', '/<name>'.` (PT and EN)
- [ ] Every `references/*.md` opens with the companion banner

## Agent role files

- [ ] Frontmatter parses; `name` equals the file basename; `description` carries triggers
- [ ] No `tools:` key
- [ ] Every entry in `skills:` resolves to `.agents/skills/<name>/SKILL.md`; every `scripts:` path exists

## AGENTS.md block

- [ ] Exactly one `<!-- CELEBRIMBOR BEGIN` line and one `<!-- CELEBRIMBOR END -->` line, BEGIN before END (mechanical check below)
- [ ] Idempotent: content outside the markers is byte-identical before and after the run (re-running leaves it unchanged)

## Tool scripts

- [ ] `bash -n` passes on every `scripts/*.sh`
- [ ] Forbidden-token grep is clean; any `rm -rf` hit targets `"$OUT_DIR"` only
- [ ] Every active script (sends traffic / reads `TARGET`) has the `I_HAVE_AUTHORIZATION=1` check and the exact-host gate from ARTIFACT_FORMATS §6 (scheme, path/query/fragment, userinfo, port stripped before the `case`)
- [ ] No prefix glob in any gate (`localhost*`, `127.0.0.1*`, `*.test*`): a hit is a failure, since it accepts `localhost.evil.com`
- [ ] Matched secret values are redacted inside the jq filter (slice `.[0:4]+"…"+.[-4:]`, emitted via `@tsv`), never interpolated raw (`"\(.Secret)"`) nor read line-by-line; raw tool reports holding values are deleted
- [ ] `out/` is gitignored (script writes `$OUT_DIR/.gitignore`)

## Adapters

- [ ] Every adapter of a generated artifact under `.claude/` and `.cursor/` resolves; fallback copies match `.agents/` (`diff -rq` clean)
- [ ] `.agent/skills/<name>/` (Antigravity) of a generated skill is a copy, never a symlink, and in sync

## Overwrite

- [ ] No existing file was overwritten without a shown diff and an explicit yes; declined files are listed as skipped; `CLAUDE.md` was touched only after its own yes, never created

## Prompt audit

- [ ] Each generated SKILL.md and agent file has an audit line, or `prompt audit: skipped — not available`

## Mechanical checks

Run with `bash`, never zsh (zsh aborts a line on an unmatched glob). Export two values from the report file first: `PRE_HASH` (empty if AGENTS.md did not exist before Phase 3) and `GENERATED` = the space-separated `generates` paths of every `approved` row (canonical `.agents/` paths). Every check below runs only on those paths — pre-existing user skills, agents and adapters are never inspected or edited.

```bash
: "${GENERATED:?export GENERATED from the report first}"
skills=$(printf '%s\n' $GENERATED | grep -o '^\.agents/skills/[^/]*' | sort -u)
agents=$(printf '%s\n' $GENERATED | grep '^\.agents/agents/[^/]*\.md$' | sort -u)
scripts=$(printf '%s\n' $GENERATED | grep '/scripts/[^/]*\.sh$')
if python3 -c 'import yaml' 2>/dev/null; then python3 - $(printf '%s/SKILL.md\n' $skills) $agents <<'PY'   # frontmatter, name == dir, triggers, tools:, paths
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
else echo "skip: PyYAML not installed — frontmatter check not run"; fi
for d in $skills; do for r in "$d"/references/*.md; do [ -f "$r" ] && ! head -1 "$r" | grep -q '^> Reference companion for the \[' && echo "BANNER: $r"; done; done
for s in $scripts; do [ -f "$s" ] && { bash -n "$s" || echo "SYNTAX: $s"; }; done
[ -z "$scripts" ] || grep -nE 'rm -rf|git (push|reset --hard|clean)|sudo |chmod 777|(curl|wget)[^|]*\| *(ba)?sh|DROP |TRUNCATE ' $scripts
[ -z "$scripts" ] || { grep -nE '(localhost|127\.0\.0\.1|\.test)\*' $scripts && echo "PREFIX GLOB in gate"; }
[ -z "$scripts" ] || grep -nE '\\\(\.(Secret|Match)\)' $scripts | sed 's/^/RAW SECRET INTERPOLATION: /'
active=$([ -z "$scripts" ] || grep -lE 'TARGET|curl |wget |zap-baseline' $scripts)
[ -z "$active" ] || for pat in 'I_HAVE_AUTHORIZATION:-}" = "1"' 'host="${host%%[/?#]*}"' "localhost|127.0.0.1|'[::1]'|*.localhost|*.test)"; do
  for f in $(grep -LF "$pat" $active); do echo "NO GATE: $f lacks $pat"; done; done
for s in $scripts; do case $s in */run.sh) grep -q '\.gitignore' "$s" || echo "OUT NOT IGNORED: $s" ;; esac; done
for p in $skills $agents; do for a in ".claude/${p#.agents/}" ".cursor/${p#.agents/}" ".agent/${p#.agents/}"; do   # adapters of generated artifacts only
  [ -e "$a" ] || [ -L "$a" ] || continue
  if [ -L "$a" ]; then [ -e "$a" ] || echo "BROKEN LINK: $a"; case $a in .agent/*) echo "ANTIGRAVITY SYMLINK: $a" ;; esac
  else diff -rq "$p" "$a"; fi; done; done
[ ! -f AGENTS.md ] || awk '/^<!-- CELEBRIMBOR BEGIN/{b++;bl=NR}/^<!-- CELEBRIMBOR END -->/{e++;el=NR}END{if(b!=1||e!=1||bl>el)print "MARKERS: need exactly one BEGIN then one END (begin="b+0" end="e+0")"}' AGENTS.md
[ -z "${PRE_HASH:-}" ] || [ "$(sed '/^<!-- CELEBRIMBOR BEGIN/,/^<!-- CELEBRIMBOR END -->/d' AGENTS.md | awk 'NF{for(;n;n--)print "";print;next}{n++}' | shasum)" = "$PRE_HASH" ] || echo "OUTSIDE-MARKERS CHANGED"
```
