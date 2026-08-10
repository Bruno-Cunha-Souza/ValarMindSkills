#!/usr/bin/env node
// caveman — UserPromptSubmit hook to track which caveman mode is active
//
// Ported from JuliusBrussee/caveman (MIT). See THIRD_PARTY_NOTICES.md.
//
// Inspects user input for /caveman commands and writes mode to flag file.
// Matches bare `/caveman` and plugin-namespaced `/valarmindskills:caveman`
// (legacy `/valarmind:` accepted for backwards compatibility).
// Valid modes: lite | full | ultra (off clears the flag).

const fs = require('fs');
const path = require('path');
const os = require('os');
const { getDefaultMode, safeWriteFlag, readFlag } = require('./caveman-config');
const { matchIntent } = require('../_lib/posture-intent');

const claudeDir = process.env.CLAUDE_CONFIG_DIR || path.join(os.homedir(), '.claude');
const flagPath = path.join(claudeDir, '.caveman-active');

let input = '';
process.stdin.on('data', chunk => { input += chunk; });
process.stdin.on('end', () => {
  try {
    const data = JSON.parse(input);
    const prompt = (data.prompt || '').trim().toLowerCase();

    // Natural language toggle. The matcher is posture-aware: a prompt that
    // names another posture ("stop ponytail, keep caveman") no longer clears
    // this flag as collateral damage. Activation never clobbers an explicit
    // level — mentioning caveman must not reset `/caveman ultra` to the default.
    const intent = matchIntent(prompt, 'caveman');
    if (intent === 'on' && !readFlag(flagPath)) {
      const mode = getDefaultMode();
      if (mode !== 'off') {
        safeWriteFlag(flagPath, mode);
      }
    } else if (intent === 'off') {
      try { fs.unlinkSync(flagPath); } catch (e) {}
    }

    // Slash commands win over natural language — explicit beats inferred.
    // Both bare and plugin-namespaced.
    // (?=\s|$) prevents partial matches like /caveman-commit from being
    // treated as /caveman with arg "-commit".
    const slashMatch = prompt.match(/^\/(?:valarmind(?:skills)?:)?caveman(?=\s|$)\s*(\S*)/);
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

    // Per-turn reinforcement
    const VALID_MODES = new Set(['lite', 'full', 'ultra']);
    const activeMode = readFlag(flagPath);
    if (activeMode && VALID_MODES.has(activeMode)) {
      process.stdout.write(JSON.stringify({
        hookSpecificOutput: {
          hookEventName: "UserPromptSubmit",
          additionalContext: "CAVEMAN MODE ACTIVE (" + activeMode + "). " +
            "Prose posture: drop articles/filler/pleasantries/hedging. Fragments OK. " +
            "Never compress code, commit messages, or security warnings — reproduce verbatim. " +
            "Says nothing about how much code to write; that is ponytail's call."
        }
      }));
    }
  } catch (e) {
    // Silent fail
  }
});
