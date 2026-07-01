#!/usr/bin/env node
// ponytail — Claude Code SubagentStart hook
//
// Ported from DietrichGebert/ponytail (MIT). See THIRD_PARTY_NOTICES.md.
//
// SessionStart context is parent-thread only and never reaches subagents, so
// without this every Task-spawned agent writes code ponytail-unaware
// (upstream issue #252). When ponytail is active, inject the same ruleset
// into each subagent — subagents are exactly where code gets written.

const path = require('path');
const os = require('os');
const { readFlag } = require('./ponytail-config');
const { buildInstructions } = require('./ponytail-instructions');

const claudeDir = process.env.CLAUDE_CONFIG_DIR || path.join(os.homedir(), '.claude');
const flagPath = path.join(claudeDir, '.ponytail-active');

const mode = readFlag(flagPath);

// Absent flag or off → ponytail isn't active; inject nothing.
if (!mode || mode === 'off') {
  process.exit(0);
}

try {
  process.stdout.write(JSON.stringify({
    hookSpecificOutput: {
      hookEventName: 'SubagentStart',
      additionalContext: buildInstructions(mode)
    }
  }));
} catch (e) {
  // Silent fail — a stdout error at hook exit must not surface as a hook failure.
}
