#!/usr/bin/env node
// ponytail — Claude Code SessionStart activation hook
//
// Ported from DietrichGebert/ponytail (MIT). See THIRD_PARTY_NOTICES.md.
//
// Runs on every session start:
//   1. Writes flag file at $CLAUDE_CONFIG_DIR/.ponytail-active (statusline reads this)
//   2. Emits ponytail ruleset as hidden SessionStart context
//
// The statusline setup nudge lives in caveman-activate.js (the statusline is a
// shared composer; one nudge covers every segment, including this one).

const fs = require('fs');
const path = require('path');
const os = require('os');
const { getDefaultMode, safeWriteFlag } = require('./ponytail-config');
const { buildInstructions } = require('./ponytail-instructions');

const claudeDir = process.env.CLAUDE_CONFIG_DIR || path.join(os.homedir(), '.claude');
const flagPath = path.join(claudeDir, '.ponytail-active');

const mode = getDefaultMode();

// "off" mode — skip activation entirely
if (mode === 'off') {
  try { fs.unlinkSync(flagPath); } catch (e) {}
  process.stdout.write('OK');
  process.exit(0);
}

// 1. Write flag file (symlink-safe)
safeWriteFlag(flagPath, mode);

// 2. Emit the ponytail ruleset, filtered to the active intensity level.
process.stdout.write(buildInstructions(mode));
