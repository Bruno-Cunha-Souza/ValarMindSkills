#!/usr/bin/env node
// obsidian-brain — UserPromptSubmit hook to track on/off toggle
//
// Inspects user input for /obsidian-brain commands and natural-language
// toggles, then writes/clears the flag file. Does NOT inject per-turn
// additionalContext — the SessionStart hook handles digest injection when
// a vault is detected. Tracker exists solely to honor user overrides
// during the session.
//
// Matches:
//   - bare `/obsidian-brain` and plugin-namespaced `/valarmindskills:obsidian-brain`
//     (legacy `/valarmind:` accepted for backwards compatibility)
//   - natural language activation/deactivation in PT and EN

const fs = require('fs');
const path = require('path');
const os = require('os');
const { safeWriteFlag } = require('./obsidian-brain-config');
const { matchIntent } = require('../_lib/posture-intent');

const claudeDir = process.env.CLAUDE_CONFIG_DIR || path.join(os.homedir(), '.claude');
const flagPath = path.join(claudeDir, '.obsidian-brain-active');

let input = '';
process.stdin.on('data', chunk => { input += chunk; });
process.stdin.on('end', () => {
  try {
    const data = JSON.parse(input);
    const prompt = (data.prompt || '').trim().toLowerCase();

    // Natural language toggle (PT + EN). The matcher is posture-aware: a prompt
    // that names another posture ("stop caveman, keep obsidian-brain") no longer
    // clears this flag as collateral damage.
    const intent = matchIntent(prompt, 'obsidian-brain');
    if (intent === 'on') {
      safeWriteFlag(flagPath, 'on');
    } else if (intent === 'off') {
      try { fs.unlinkSync(flagPath); } catch (e) {}
    }

    // Slash commands win over natural language — both bare and plugin-namespaced
    const slashMatch = prompt.match(/^\/(?:valarmind(?:skills)?:)?obsidian-brain\b\s*(\S*)/);
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

    // No per-turn reinforcement: the SessionStart digest is sufficient and
    // adding noise on every prompt would defeat the token-economy goal of
    // the obsidian-brain skill itself.
  } catch (e) {
    // Silent fail
  }
});
