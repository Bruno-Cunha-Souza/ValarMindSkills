# HARNESS_NOTES — context-optimization

> Reference companion for the [context-optimization](../SKILL.md) skill.

Per-harness primitives for compaction, caching, session inspection, and limitations. Loaded when Phase 0.1 captures `harness ≠ agnostic`. The audit (Phases 1-5) is harness-agnostic; the **plan** in Block 3 names harness-specific commands so the user can act on it without a second lookup.

## Matrix overview

| Harness | Auto-compaction | Manual compaction | Cache primitive | Session inspection | Window default |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Claude Code** | Yes — since 2025-Q4 at ~95% | `/compact` slash command | `cache_control: ephemeral` (Anthropic API native) | `~/.claude/projects/<hash>/*.jsonl` | Per model (Sonnet 4.6: 1M; Opus 4.7: 1M) |
| **Codex CLI** | No (default) | `session.compaction` CLI | OpenAI prompt caching (automatic, no flag needed) | `~/.codex/sessions/` | Per model (GPT-5: 200k; o3: 200k) |
| **OpenCode** | Configurable per project | `session.compact` | Provider-dependent (mirror upstream) | Project session dir | Per model |
| **Antigravity (Gemini)** | None native | Manual UI re-prompt | Vertex AI context cache (server-managed) | (no direct CLI inspection) | Per model (Gemini 2.5 Pro: 2M) |

---

## Claude Code

**Auto-compaction.** Since 2025-Q4. Triggers automatically near 95% capacity. Implicit; user does not control timing. Plan output should NOT rely solely on auto-compaction for production sessions where determinism matters — the trigger threshold is implementation detail and may shift.

**Manual compaction.** `/compact` slash command. Recommended for deterministic timing at 70-80% utilization. After `/compact`, the session continues with a structured summary replacing earlier turns; `/clear` is the harder reset (full new session).

**Cache primitive.** Anthropic prompt caching native. Set `cache_control: { type: "ephemeral" }` on stable system prompt blocks via API. Inside Claude Code, the system manages this automatically for skill content and tool definitions; for user-built MCP servers, the MCP author sets cache_control on tool descriptions.

**Session inspection.** Each project has an entry in `~/.claude/projects/<hash>/`. Sessions are JSON-Lines (`.jsonl`); each line is a turn. Useful for `01-token-count.py` smoke tests and post-mortems. The hash is derived from the project path; find your project's hash via `ls ~/.claude/projects/`.

**Statusline indicator.** Bottom-right shows context usage live. When approaching 70%, manual `/compact` is the recommended trigger. The numeric percentage is your single best signal for Phase 0.1 utilization estimate.

**Limitations.**

- Slash commands are skill-managed; you cannot remap `/compact` to a different threshold.
- Auto-compaction summary is opaque (you don't see what was elided).
- Cross-session memory is NOT in scope of compaction — see `auto memory` system at `~/.claude/projects/<hash>/memory/` for that.

**Plan-output template (when `harness: claude-code`):**

```text
1. Run `/compact` at 75% utilization (currently 82% — overdue).
2. Add `cache_control: ephemeral` on system prompt blocks via your MCP server config.
3. Move tool definitions ahead of dynamic chunks (per §9).
4. Verify with: tail -f ~/.claude/projects/<hash>/<session>.jsonl
```

---

## Codex CLI

**Auto-compaction.** No automatic trigger by default. User opts-in per session.

**Manual compaction.** `session.compaction` CLI command (or equivalent — refer to current Codex docs). Codex sessions are explicit, terminal-driven, and compaction is a deliberate user action.

**Cache primitive.** OpenAI prompt caching is automatic for prompts ≥ 1024 tokens with stable prefixes — no `cache_control` flag required. The prefix-match rules apply (exact byte match before first dynamic byte). §9 cache-friendly ordering still mandatory; §1 caching is "on" but invisible to the user.

**Session inspection.** Sessions stored under `~/.codex/sessions/`. Format may differ from Claude Code; check `head -1 <session-file>` to confirm structure before parsing.

**Limitations.**

- No statusline context indicator analogous to Claude Code's. Manual estimation via session file size or token-count script (§3 candidate).
- Compaction strategy is less battle-tested than Claude Code's; verify summary fidelity on first run.
- Codex hooks (in `~/.codex/config.toml [[hooks]]`) are command-typed; **skill `scripts/` are not auto-invoked** — user runs them manually via terminal.

**Plan-output template (when `harness: codex`):**

```text
1. Run session.compaction at 75% utilization (Codex CLI command).
2. Trust automatic OpenAI prompt caching — verify §9 ordering manually.
3. For scripts/ analysis, run from terminal: bash scripts/run-all.sh <project>
4. No statusline indicator: track session file size as proxy:
   wc -c ~/.codex/sessions/<session-file>
```

---

## OpenCode

**Auto-compaction.** Configurable per project (set in OpenCode config). Default off in many distributions.

**Manual compaction.** `session.compact` (mirror Codex pattern; verify against current OpenCode docs).

**Cache primitive.** Mirrors upstream provider — if backed by Anthropic, use `cache_control`; if OpenAI, automatic prefix caching applies.

**Session inspection.** Per-project session dir under OpenCode workspace.

**Limitations.**

- Multi-provider abstraction means cache primitives shift by config — verify before relying on §1.
- Less broad adoption than Claude Code / Codex; community tooling sparser.

**Plan-output template (when `harness: opencode`):**

```text
1. Verify provider in OpenCode config; enable auto-compaction if not on.
2. Run session.compact at 75% utilization.
3. Cache_control depends on backing provider — see provider docs.
4. For scripts/, terminal invocation as Codex.
```

---

## Antigravity (Gemini-based)

**Auto-compaction.** None native. The IDE does not expose a compaction primitive analogous to `/compact`.

**Manual compaction.** Manual UI re-prompt — user closes thread and starts new, optionally pasting a hand-written summary as seed context.

**Cache primitive.** Vertex AI context cache — server-managed via API. Inside Antigravity (markdown-only skill loading), cache_control is **not under skill author's control**. Skill content benefits from cache only if the platform sets it up.

**Session inspection.** No direct CLI session inspection like `~/.claude/projects/`. State lives in IDE and Vertex AI backend.

**Limitations.**

- Skill `scripts/` are copied to `~/.gemini/antigravity/skills/<skill>/scripts/` but the Antigravity runtime is markdown-only — **scripts cannot be auto-invoked** by the skill. User must invoke from external terminal.
- Window is large (Gemini 2.5 Pro: 2M tokens) so compaction is rarely the bottleneck; cost / quality / cache become primary concerns.
- Audit mode of `context-optimization` skill works in **guide mode only** on Antigravity (no script execution to gather evidence).

**Plan-output template (when `harness: antigravity`):**

```text
1. No native compaction — close thread + re-prompt with summary at 75% utilization.
2. Vertex AI handles caching server-side; you cannot control cache_control directly.
3. Window is 2M tokens; compaction less urgent — focus on §3 masking, §10 dedup,
   §8 re-rank for retrieval workloads.
4. For scripts/ analysis, run from external terminal — Antigravity does not invoke
   skill scripts directly.
```

---

## Agnostic plans

When `harness: agnostic` (skill-prompt audit, design exercise, no production target named), Block 3 plan describes techniques in terms of the technique catalog (§1-§13) without naming a harness primitive. Add a one-line note: `Harness-specific commands not emitted: declare harness in Phase 0.1 to receive concrete commands.`

## Cross-link

- §13 of [TECHNIQUES.md](TECHNIQUES.md) cross-references this file as the source of harness-specific commands.
- Phase 0.1 of [SKILL.md](../SKILL.md) is where harness is captured.
- `scripts/README.md` repeats the portability matrix from this file in the script execution section.
