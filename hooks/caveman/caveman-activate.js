#!/usr/bin/env node
// caveman — Claude Code SessionStart activation hook
//
// Ported from JuliusBrussee/caveman (MIT). See THIRD_PARTY_NOTICES.md.
//
// Runs on every session start:
//   1. Writes flag file at $CLAUDE_CONFIG_DIR/.caveman-active (statusline reads this)
//   2. Emits caveman ruleset as hidden SessionStart context
//   3. Detects missing statusline config and emits setup nudge

const fs = require('fs');
const path = require('path');
const os = require('os');
const { getDefaultMode, safeWriteFlag } = require('./caveman-config');
const { resolveSkillMd } = require('../_lib/resolve-skill-path');

const claudeDir = process.env.CLAUDE_CONFIG_DIR || path.join(os.homedir(), '.claude');
const flagPath = path.join(claudeDir, '.caveman-active');
const settingsPath = path.join(claudeDir, 'settings.json');

const mode = getDefaultMode();

// "off" mode — skip activation entirely
if (mode === 'off') {
  try { fs.unlinkSync(flagPath); } catch (e) {}
  process.stdout.write('OK');
  process.exit(0);
}

// 1. Write flag file (symlink-safe)
safeWriteFlag(flagPath, mode);

// 2. Emit full caveman ruleset, filtered to the active intensity level.
const INDEPENDENT_MODES = new Set(['commit', 'review']);

if (INDEPENDENT_MODES.has(mode)) {
  process.stdout.write('CAVEMAN MODE ACTIVE — level: ' + mode + '. Behavior defined by /valarmindskills:caveman-' + mode + ' skill.');
  process.exit(0);
}

const modeLabel = mode;

// Read SKILL.md — the single source of truth for caveman behavior.
const skillContent = resolveSkillMd('caveman', __dirname);

let output;

if (skillContent) {
  // Strip YAML frontmatter
  const body = skillContent.replace(/^---[\s\S]*?---\s*/, '');

  // Filter intensity table: keep header rows + only the active level's row
  const filtered = body.split('\n').reduce((acc, line) => {
    const tableRowMatch = line.match(/^\|\s*`?(\S+?)`?\s*\|/);
    if (tableRowMatch && ['lite', 'full', 'ultra'].includes(tableRowMatch[1])) {
      if (tableRowMatch[1] === modeLabel) {
        acc.push(line);
      }
      return acc;
    }
    acc.push(line);
    return acc;
  }, []);

  output = 'CAVEMAN MODE ACTIVE — level: ' + modeLabel + '\n\n' + filtered.join('\n');
} else {
  // Fallback
  output =
    'CAVEMAN MODE ACTIVE — level: ' + modeLabel + '\n\n' +
    'Respond terse like smart caveman. All technical substance stay. Only fluff die.\n\n' +
    '## Persistence\n\n' +
    'ACTIVE EVERY RESPONSE. No revert after many turns. No filler drift. Off only: "stop caveman" / "normal mode".\n\n' +
    'Current level: **' + modeLabel + '**. Switch: `/valarmindskills:caveman lite|full|ultra`.\n\n' +
    '## Rules\n\n' +
    'Drop: articles (a/an/the), filler (just/really/basically/actually/simply), pleasantries (sure/certainly/of course/happy to), hedging. ' +
    'Fragments OK. Short synonyms (big not extensive, fix not "implement a solution for"). ' +
    'No tool-call narration, no decorative tables/emoji, no raw error-log dumps — quote shortest decisive line. ' +
    'Standard acronyms OK (DB/API/HTTP); never invent abbreviations. Technical terms exact. Code blocks unchanged. Errors quoted exact.\n\n' +
    "Preserve user's dominant language — compress the style, not the language. Technical terms, code, CLI commands, commit-type keywords, error strings stay verbatim.\n\n" +
    'No self-reference. Never name or announce the mode. Output caveman-only — no "Caveman:" recap.\n\n' +
    'Pattern: `[thing] [action] [reason]. [next step].`\n\n' +
    '## Auto-Clarity\n\n' +
    'Drop caveman for: security warnings, irreversible action confirmations, multi-step sequences where fragment order risks misread. Resume caveman after clear part done.\n\n' +
    '## Boundaries\n\n' +
    'Caveman shapes prose only. Never compress code, commit messages, PRs, or errors — reproduce verbatim. ' +
    'How much code to write is ponytail territory, not caveman\'s; the two compose. ' +
    '"stop caveman" or "normal mode": revert. Level persist until changed or session end.';
}

// 3. Detect missing statusline config — nudge Claude to help set it up (Claude Code only)
if (process.env.VALARMIND_HOOK_RUNTIME === 'cursor') {
  process.stdout.write(output);
  process.exit(0);
}

try {
  let hasStatusline = false;
  if (fs.existsSync(settingsPath)) {
    const settings = JSON.parse(fs.readFileSync(settingsPath, 'utf8'));
    if (settings.statusLine) {
      hasStatusline = true;
    }
  }

  if (!hasStatusline) {
    const isWindows = process.platform === 'win32';
    const scriptPath = path.join(__dirname, '..', 'statusline', 'statusline.sh');
    const command = isWindows
      ? `powershell -ExecutionPolicy Bypass -File "${scriptPath}"`
      : `bash "${scriptPath}"`;
    const statusLineSnippet =
      '"statusLine": { "type": "command", "command": ' + JSON.stringify(command) + ' }';
    output += "\n\n" +
      "STATUSLINE SETUP NEEDED: valarmindskills plugin includes a composable statusline " +
      "(caveman badge + context window usage, e.g. [CAVEMAN] 42% 420k/1M). Not configured yet. " +
      "To enable, add to " + path.join(claudeDir, 'settings.json') + ": " +
      statusLineSnippet;
  }
} catch (e) {
  // Silent fail
}

process.stdout.write(output);
