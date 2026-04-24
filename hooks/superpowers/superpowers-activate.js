#!/usr/bin/env node
// superpowers — Claude Code SessionStart activation hook
//
// Inspired by obra/superpowers (MIT, Copyright 2025 Jesse Vincent).
// See THIRD_PARTY_NOTICES.md.
//
// Runs on every session start:
//   1. Reads default mode (env > config > 'off')
//   2. If 'off': cleans stale flag, exits silently — no posture injected.
//   3. If 'on': writes flag file at $CLAUDE_CONFIG_DIR/.superpowers-active
//      (statusline reads this) and emits a compressed posture digest.

const fs = require('fs');
const path = require('path');
const os = require('os');
const { getDefaultMode, safeWriteFlag } = require('./superpowers-config');

const claudeDir = process.env.CLAUDE_CONFIG_DIR || path.join(os.homedir(), '.claude');
const flagPath = path.join(claudeDir, '.superpowers-active');

const mode = getDefaultMode();

// "off" mode — skip activation entirely. Clean up any stale flag.
if (mode === 'off') {
  try { fs.unlinkSync(flagPath); } catch (e) {}
  process.stdout.write('OK');
  process.exit(0);
}

// "on" — write flag (symlink-safe) and emit posture digest.
safeWriteFlag(flagPath, 'on');

// Try to derive posture from SKILL.md so the message stays in sync with the
// canonical text. If absent, fall back to a short hardcoded summary.
let skillContent = '';
try {
  skillContent = fs.readFileSync(
    path.join(__dirname, '..', '..', 'skills', 'superpowers', 'SKILL.md'),
    'utf8'
  );
} catch (e) { /* fall back below */ }

let output;

if (skillContent) {
  const body = skillContent.replace(/^---[\s\S]*?---\s*/, '');
  output = 'SUPERPOWERS MODE ACTIVE\n\n' + body;
} else {
  output =
    'SUPERPOWERS MODE ACTIVE\n\n' +
    'Engineering-discipline posture. Persists for the session until `/valarmind:superpowers off` or "stop superpowers".\n\n' +
    '## The 1% Rule\n\n' +
    'Before any reply or action, scan available skills. Even a 1% chance a skill applies means invoke it to check. Skill check comes BEFORE clarifying questions.\n\n' +
    '## Instruction Hierarchy\n\n' +
    '1. User instructions (CLAUDE.md, AGENTS.md, direct request) — highest.\n' +
    '2. Superpowers skills — override defaults where they conflict.\n' +
    '3. Default system prompt — lowest.\n\n' +
    '## Four Pillars\n\n' +
    '1. **Test-Driven Development** — failing test before production code. RED → GREEN → REFACTOR.\n' +
    '2. **Systematic over ad-hoc** — process beats guessing.\n' +
    '3. **Complexity reduction** — simplicity is the primary goal.\n' +
    '4. **Evidence over claims** — verify before declaring success.\n\n' +
    '## Seven-Stage Workflow\n\n' +
    '1. Brainstorm — Socratic refinement until the spec is clear.\n' +
    '2. Worktree — isolate work in a clean branch.\n' +
    '3. Write plan — bite-size 2–5 minute tasks with exact paths.\n' +
    '4. Subagent-driven OR execute plan — fresh subagent per task with two-stage review.\n' +
    '5. TDD — failing test first, every time.\n' +
    '6. Request review — severity-ranked, critical issues block.\n' +
    '7. Finish branch — verify tests, present merge / PR / keep / discard.\n\n' +
    '## Twelve Red Flags (rationalizations to refuse)\n\n' +
    '- "Just a simple question" — questions are tasks; check for skills.\n' +
    '- "I need more context first" — skill check comes BEFORE clarifying questions.\n' +
    '- "This doesn\'t need a formal skill" — if a skill exists, use it.\n' +
    '- "The skill is overkill" — simple things become complex; use it.\n' +
    '- "I\'ll just do this one thing first" — check BEFORE doing anything.\n' +
    '- "I already know what to do" — verify against the skill anyway.\n' +
    '- "Tests will slow this down" — TDD is mandatory; the test IS the spec.\n' +
    '- "I can fix this after" — production code without a failing test is deleted.\n' +
    '- "It probably works" — evidence beats claims; verify.\n' +
    '- "Close enough" — refactor or ship; no half states.\n' +
    '- "The user didn\'t ask for tests" — the four pillars apply unless the user explicitly opts out.\n' +
    '- "I\'ll write a quick hack" — quick hacks become tech debt; reach for a skill.\n\n' +
    '## Boundaries\n\n' +
    'Does not override safety. Coexists with caveman (caveman shapes voice; superpowers shapes process). Stop with `/valarmind:superpowers off`, "stop superpowers", or "desativar superpowers".';
}

process.stdout.write(output);
