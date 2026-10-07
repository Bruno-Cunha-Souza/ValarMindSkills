#!/usr/bin/env node
// statusline — Claude Code SessionStart hook
//
// When settings.json has no statusLine, emits a hidden hint telling the agent
// how to wire up statusline.sh. Silent otherwise. Registered only in
// plugin.json: Codex and Cursor have no Claude statusline, so their installers
// leave this hook out.

const fs = require('fs');
const path = require('path');
const os = require('os');

const claudeDir = process.env.CLAUDE_CONFIG_DIR || path.join(os.homedir(), '.claude');
const settingsPath = path.join(claudeDir, 'settings.json');

let settings = null;
try {
  settings = JSON.parse(fs.readFileSync(settingsPath, 'utf8'));
} catch (e) {
  // Unreadable or invalid settings.json — don't point the user at a broken file.
  if (e.code !== 'ENOENT') process.exit(0);
}
if (settings?.statusLine) process.exit(0);

const command = `bash "${path.join(__dirname, 'statusline.sh')}"`;
process.stdout.write(
  'STATUSLINE SETUP NEEDED: valarmindskills plugin includes a composable statusline ' +
  '(obsidian-brain badge + context window usage, e.g. [OBSIDIAN-BRAIN] 42% 420k/1M). Not configured yet. ' +
  'To enable, add to ' + settingsPath + ': ' +
  '"statusLine": { "type": "command", "command": ' + JSON.stringify(command) + ' }'
);
