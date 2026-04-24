#!/usr/bin/env node
// superpowers — UserPromptSubmit hook to track which superpowers mode is active
//
// Inspired by obra/superpowers (MIT, Copyright 2025 Jesse Vincent).
// See THIRD_PARTY_NOTICES.md.
//
// Inspects user input for /superpowers commands and writes mode to flag file.
// Matches both bare `/superpowers` and plugin-namespaced `/valarmind:superpowers`
// forms. Default arg is `on` (binary toggle, no levels).

const fs = require('fs');
const path = require('path');
const os = require('os');
const { safeWriteFlag, readFlag } = require('./superpowers-config');

const claudeDir = process.env.CLAUDE_CONFIG_DIR || path.join(os.homedir(), '.claude');
const flagPath = path.join(claudeDir, '.superpowers-active');

let input = '';
process.stdin.on('data', chunk => { input += chunk; });
process.stdin.on('end', () => {
  try {
    const data = JSON.parse(input);
    const prompt = (data.prompt || '').trim().toLowerCase();

    // Natural language activation (PT + EN)
    if (/\b(activate|enable|turn on|start|ative|ativar|ligar)\b.*\bsuperpowers\b/i.test(prompt) ||
        /\bsuperpowers\b.*\b(mode|modo|activate|enable|turn on|start|on)\b/i.test(prompt)) {
      if (!/\b(stop|disable|turn off|deactivate|parar|desativar|desligar|off)\b/i.test(prompt)) {
        safeWriteFlag(flagPath, 'on');
      }
    }

    // Match slash commands — both bare and plugin-namespaced
    const slashMatch = prompt.match(/^\/(?:valarmind:)?superpowers\b\s*(\S*)/);
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
    if (/\b(stop|disable|deactivate|turn off|parar|desativar|desligar)\b.*\bsuperpowers\b/i.test(prompt) ||
        /\bsuperpowers\b.*\b(stop|disable|deactivate|turn off|off)\b/i.test(prompt)) {
      try { fs.unlinkSync(flagPath); } catch (e) {}
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
