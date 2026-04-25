#!/usr/bin/env node
// caveman — UserPromptSubmit hook to track which caveman mode is active
//
// Ported from JuliusBrussee/caveman (MIT). See THIRD_PARTY_NOTICES.md.
//
// Inspects user input for /caveman commands and writes mode to flag file.
// Matches bare `/caveman` and plugin-namespaced `/valarmindskills:caveman`
// (legacy `/valarmind:` accepted for backwards compatibility).

const fs = require('fs');
const path = require('path');
const os = require('os');
const { getDefaultMode, safeWriteFlag, readFlag } = require('./caveman-config');

const claudeDir = process.env.CLAUDE_CONFIG_DIR || path.join(os.homedir(), '.claude');
const flagPath = path.join(claudeDir, '.caveman-active');

let input = '';
process.stdin.on('data', chunk => { input += chunk; });
process.stdin.on('end', () => {
  try {
    const data = JSON.parse(input);
    const prompt = (data.prompt || '').trim().toLowerCase();

    // Natural language activation
    if (/\b(activate|enable|turn on|start|talk like|fale como|ative|ativar)\b.*\bcaveman\b/i.test(prompt) ||
        /\bcaveman\b.*\b(mode|modo|activate|enable|turn on|start)\b/i.test(prompt)) {
      if (!/\b(stop|disable|turn off|deactivate|parar|desativar|normal mode|modo normal)\b/i.test(prompt)) {
        const mode = getDefaultMode();
        if (mode !== 'off') {
          safeWriteFlag(flagPath, mode);
        }
      }
    }

    // Match slash commands — both bare and plugin-namespaced
    const slashMatch = prompt.match(/^\/(?:valarmind(?:skills)?:)?(caveman(?:-commit|-review)?)\b\s*(\S*)/);
    if (slashMatch) {
      const cmd = slashMatch[1];
      const arg = slashMatch[2] || '';

      let mode = null;

      if (cmd === 'caveman-commit') {
        mode = 'commit';
      } else if (cmd === 'caveman-review') {
        mode = 'review';
      } else if (cmd === 'caveman') {
        if (arg === 'lite') mode = 'lite';
        else if (arg === 'ultra') mode = 'ultra';
        else if (arg === 'full') mode = 'full';
        else if (arg === 'off') mode = 'off';
        else mode = getDefaultMode();
      }

      if (mode && mode !== 'off') {
        safeWriteFlag(flagPath, mode);
      } else if (mode === 'off') {
        try { fs.unlinkSync(flagPath); } catch (e) {}
      }
    }

    // Natural language deactivation
    if (/\b(stop|disable|deactivate|turn off|parar|desativar)\b.*\bcaveman\b/i.test(prompt) ||
        /\bcaveman\b.*\b(stop|disable|deactivate|turn off)\b/i.test(prompt) ||
        /\b(normal mode|modo normal)\b/i.test(prompt)) {
      try { fs.unlinkSync(flagPath); } catch (e) {}
    }

    // Per-turn reinforcement
    const INDEPENDENT_MODES = new Set(['commit', 'review']);
    const activeMode = readFlag(flagPath);
    if (activeMode && !INDEPENDENT_MODES.has(activeMode)) {
      process.stdout.write(JSON.stringify({
        hookSpecificOutput: {
          hookEventName: "UserPromptSubmit",
          additionalContext: "CAVEMAN MODE ACTIVE (" + activeMode + "). " +
            "Drop articles/filler/pleasantries/hedging. Fragments OK. " +
            "Code/commits/security: write normal."
        }
      }));
    }
  } catch (e) {
    // Silent fail
  }
});
