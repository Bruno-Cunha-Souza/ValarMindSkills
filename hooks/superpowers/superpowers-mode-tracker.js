#!/usr/bin/env node
// superpowers — UserPromptSubmit hook to track which superpowers mode is active
//
// Inspired by obra/superpowers (MIT, Copyright 2025 Jesse Vincent).
// See THIRD_PARTY_NOTICES.md.
//
// Inspects user input for /superpowers commands and writes mode to flag file.
// Matches bare `/superpowers` and plugin-namespaced `/valarmindskills:superpowers`
// (legacy `/valarmind:` accepted for backwards compatibility).
// Default arg is `on` (binary toggle, no levels).

const fs = require('fs');
const path = require('path');
const os = require('os');
const { safeWriteFlag, readFlag } = require('./superpowers-config');
const { matchIntent } = require('../_lib/posture-intent');

const claudeDir = process.env.CLAUDE_CONFIG_DIR || path.join(os.homedir(), '.claude');
const flagPath = path.join(claudeDir, '.superpowers-active');

let input = '';
process.stdin.on('data', chunk => { input += chunk; });
process.stdin.on('end', () => {
  try {
    const data = JSON.parse(input);
    const prompt = (data.prompt || '').trim().toLowerCase();

    // Natural language toggle (PT + EN). The matcher is posture-aware: a prompt
    // that names another posture ("stop caveman, keep superpowers") no longer
    // clears this flag as collateral damage.
    const intent = matchIntent(prompt, 'superpowers');
    if (intent === 'on') {
      safeWriteFlag(flagPath, 'on');
    } else if (intent === 'off') {
      try { fs.unlinkSync(flagPath); } catch (e) {}
    }

    // Slash commands win over natural language — both bare and plugin-namespaced
    const slashMatch = prompt.match(/^\/(?:valarmind(?:skills)?:)?superpowers\b\s*(\S*)/);
    if (slashMatch) {
      const arg = slashMatch[1] || '';

      let mode = null;
      if (arg === 'off') mode = 'off';
      else if (arg === 'on' || arg === '') mode = 'on';

      if (mode === 'on') {
        safeWriteFlag(flagPath, 'on');
      } else if (mode === 'off') {
        try { fs.unlinkSync(flagPath); } catch (e) {}
      }
    }

    // Per-turn reinforcement when active
    const activeMode = readFlag(flagPath);
    if (activeMode === 'on') {
      process.stdout.write(JSON.stringify({
        hookSpecificOutput: {
          hookEventName: "UserPromptSubmit",
          additionalContext: "SUPERPOWERS ACTIVE. Scan skills before replying (1% rule). " +
            "Hierarchy: user > skills > defaults. Apply four pillars (TDD, systematic, " +
            "complexity reduction, evidence). Refuse the twelve rationalizations. " +
            "Use the seven-stage workflow when scope warrants it."
        }
      }));
    }
  } catch (e) {
    // Silent fail
  }
});
