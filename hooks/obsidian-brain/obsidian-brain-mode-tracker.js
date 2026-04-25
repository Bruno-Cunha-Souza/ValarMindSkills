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

const claudeDir = process.env.CLAUDE_CONFIG_DIR || path.join(os.homedir(), '.claude');
const flagPath = path.join(claudeDir, '.obsidian-brain-active');

let input = '';
process.stdin.on('data', chunk => { input += chunk; });
process.stdin.on('end', () => {
  try {
    const data = JSON.parse(input);
    const prompt = (data.prompt || '').trim().toLowerCase();

    // Natural language activation (PT + EN)
    if (/\b(activate|enable|turn on|start|ative|ativar|ligar)\b.*\b(obsidian[ -]?brain|cérebro do obsidian|cerebro do obsidian)\b/i.test(prompt) ||
        /\b(obsidian[ -]?brain|cérebro do obsidian|cerebro do obsidian)\b.*\b(mode|modo|activate|enable|turn on|start|on|ative|ativar|ligar)\b/i.test(prompt)) {
      if (!/\b(stop|disable|turn off|deactivate|parar|desativar|desligar|off)\b/i.test(prompt)) {
        safeWriteFlag(flagPath, 'on');
      }
    }

    // Match slash commands — both bare and plugin-namespaced
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

    // Natural language deactivation (PT + EN)
    if (/\b(stop|disable|deactivate|turn off|parar|desativar|desligar)\b.*\b(obsidian[ -]?brain|cérebro do obsidian|cerebro do obsidian)\b/i.test(prompt) ||
        /\b(obsidian[ -]?brain|cérebro do obsidian|cerebro do obsidian)\b.*\b(stop|disable|deactivate|turn off|off|parar|desativar|desligar)\b/i.test(prompt)) {
      try { fs.unlinkSync(flagPath); } catch (e) {}
    }

    // No per-turn reinforcement: the SessionStart digest is sufficient and
    // adding noise on every prompt would defeat the token-economy goal of
    // the obsidian-brain skill itself.
  } catch (e) {
    // Silent fail
  }
});
