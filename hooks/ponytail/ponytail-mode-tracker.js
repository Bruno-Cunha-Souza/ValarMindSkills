#!/usr/bin/env node
// ponytail — UserPromptSubmit hook to track which ponytail mode is active
//
// Ported from DietrichGebert/ponytail (MIT). See THIRD_PARTY_NOTICES.md.
//
// Inspects user input for /ponytail commands and writes mode to flag file.
// Matches bare `/ponytail` and plugin-namespaced `/valarmindskills:ponytail`
// (legacy `/valarmind:` accepted for backwards compatibility).
// Valid modes: lite | full | ultra (off clears the flag).
// `/ponytail-review` is a one-shot skill, not a persistent mode — the
// (?=\s|$) lookahead keeps it from matching here.

const fs = require('fs');
const path = require('path');
const os = require('os');
const { getDefaultMode, safeWriteFlag, readFlag } = require('./ponytail-config');

const claudeDir = process.env.CLAUDE_CONFIG_DIR || path.join(os.homedir(), '.claude');
const flagPath = path.join(claudeDir, '.ponytail-active');

let input = '';
process.stdin.on('data', chunk => { input += chunk; });
process.stdin.on('end', () => {
  try {
    const data = JSON.parse(input);
    const prompt = (data.prompt || '').trim().toLowerCase();

    // Natural language activation
    if (/\b(activate|enable|turn on|start|ative|ativar)\b.*\bponytail\b/i.test(prompt) ||
        /\bponytail\b.*\b(mode|modo|activate|enable|turn on|start)\b/i.test(prompt) ||
        /^(lazy mode|modo lazy|be lazy)[.!?\s]*$/i.test(prompt)) {
      if (!/\b(stop|disable|turn off|deactivate|parar|desativar)\b/i.test(prompt)) {
        const mode = getDefaultMode();
        if (mode !== 'off') {
          safeWriteFlag(flagPath, mode);
        }
      }
    }

    // Match slash commands — both bare and plugin-namespaced.
    // (?=\s|$) prevents partial matches like /ponytail-review from being
    // treated as /ponytail with arg "-review".
    const slashMatch = prompt.match(/^\/(?:valarmind(?:skills)?:)?ponytail(?=\s|$)\s*(\S*)/);
    if (slashMatch) {
      const arg = slashMatch[1] || '';

      let mode;
      if (arg === 'lite') mode = 'lite';
      else if (arg === 'ultra') mode = 'ultra';
      else if (arg === 'full') mode = 'full';
      else if (arg === 'off') mode = 'off';
      else mode = getDefaultMode();

      if (mode && mode !== 'off') {
        safeWriteFlag(flagPath, mode);
      } else if (mode === 'off') {
        try { fs.unlinkSync(flagPath); } catch (e) {}
      }
    }

    // Natural language deactivation
    if (/\b(stop|disable|deactivate|turn off|parar|desativar)\b.*\bponytail\b/i.test(prompt) ||
        /\bponytail\b.*\b(stop|disable|deactivate|turn off)\b/i.test(prompt) ||
        /\b(normal mode|modo normal)\b/i.test(prompt)) {
      try { fs.unlinkSync(flagPath); } catch (e) {}
    }

    // Per-turn reinforcement
    const VALID_MODES = new Set(['lite', 'full', 'ultra']);
    const activeMode = readFlag(flagPath);
    if (activeMode && VALID_MODES.has(activeMode)) {
      process.stdout.write(JSON.stringify({
        hookSpecificOutput: {
          hookEventName: "UserPromptSubmit",
          additionalContext: "PONYTAIL MODE ACTIVE (" + activeMode + "). " +
            "Code output: climb the ladder first — needed at all? / already in codebase? / stdlib? / native platform? / installed dep? / one line? / minimum. " +
            "Never cut validation, error handling, security, accessibility. Prose style unchanged."
        }
      }));
    }
  } catch (e) {
    // Silent fail
  }
});
