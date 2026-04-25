#!/usr/bin/env node
// obsidian-brain — Claude Code SessionStart activation hook
//
// Runs on every session start:
//   1. Resolve mode (env > config > 'on'). If 'off', clear flag, exit OK.
//   2. Locate CLAUDE.md (preferred) or AGENTS.md in cwd or up to 3 ancestors.
//   3. Scan the body for an Obsidian vault reference (path containing "Obsidian").
//   4. If the reference resolves to an existing directory, derive the brain
//      index path, write the flag file with 'on', and emit a system-reminder
//      pointing the agent to it.
//   5. On any failure or no match: clear flag, write "OK", exit 0.
//
// The hook never writes to the vault — only the local flag file at
// $CLAUDE_CONFIG_DIR/.obsidian-brain-active.

const fs = require('fs');
const path = require('path');
const os = require('os');
const { getDefaultMode, safeWriteFlag } = require('./obsidian-brain-config');

const MAX_ANCESTORS = 3;
// Match a relative, absolute, or home-relative path containing "Obsidian",
// terminated by whitespace, quote, backtick, or close-paren.
const VAULT_REGEX = /(?:~\/|\.{1,2}\/|\/)[^\s"'`)]*Obsidian[^\s"'`)]*/i;

const claudeDir = process.env.CLAUDE_CONFIG_DIR || path.join(os.homedir(), '.claude');
const flagPath = path.join(claudeDir, '.obsidian-brain-active');

function cleanFlag() {
  try { fs.unlinkSync(flagPath); } catch (e) { /* ignore ENOENT */ }
}

function expandTilde(p) {
  if (p.startsWith('~/') || p === '~') {
    return path.join(os.homedir(), p.slice(2));
  }
  return p;
}

function findFile(startDir, fileNames) {
  let dir = startDir;
  for (let i = 0; i <= MAX_ANCESTORS; i++) {
    for (const name of fileNames) {
      const p = path.join(dir, name);
      try {
        if (fs.statSync(p).isFile()) return p;
      } catch (e) { /* not present at this level */ }
    }
    const parent = path.dirname(dir);
    if (parent === dir) break;
    dir = parent;
  }
  return null;
}

function silentExit() {
  cleanFlag();
  process.stdout.write('OK');
  process.exit(0);
}

function deriveSlug(folderName) {
  return folderName
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
}

try {
  // Mode override — env > config > 'on'. 'off' clears the flag and exits.
  const mode = getDefaultMode();
  if (mode === 'off') {
    silentExit();
  }

  const cwd = process.cwd();
  const found = findFile(cwd, ['CLAUDE.md', 'AGENTS.md']);
  if (!found) silentExit();

  const body = fs.readFileSync(found, 'utf8');
  const match = body.match(VAULT_REGEX);
  if (!match) silentExit();

  const baseDir = path.dirname(found);
  const vaultPath = path.resolve(baseDir, expandTilde(match[0]));

  let stat;
  try {
    stat = fs.statSync(vaultPath);
  } catch (e) {
    silentExit();
  }
  if (!stat.isDirectory()) silentExit();

  const slug = deriveSlug(path.basename(vaultPath));
  if (!slug) silentExit();

  const brainRoot = path.join(vaultPath, 'brain');
  const indexPath = path.join(brainRoot, slug + '-brain.md');
  const indexExists = fs.existsSync(indexPath);
  const action = indexExists ? 'Read' : 'Bootstrap';

  const message =
    'OBSIDIAN-BRAIN ACTIVE\n\n' +
    'Vault detected at ' + vaultPath + '\n' +
    'Brain index: ' + indexPath + ' (' +
    (indexExists ? 'exists' : 'MISSING — bootstrap on first relevant turn') + ')\n\n' +
    'Action this session:\n' +
    '1. ' + action + ' the index (≤500 tokens) before any project-specific reasoning.\n' +
    '2. Lazy-load topics/sessions/decisions only when matched to the user prompt.\n' +
    '3. After relevant changes, suggest updating the main project docs.\n\n' +
    'See @obsidian-brain (skills/obsidian-brain/SKILL.md) for the full procedure.\n' +
    'Prefer @obsidian-cli for I/O. Fall back to file-IO only if `obsidian --version` fails.\n' +
    'Disable for this session with `/valarmindskills:obsidian-brain off`.';

  safeWriteFlag(flagPath, 'on');
  process.stdout.write(message);
} catch (e) {
  cleanFlag();
  process.stdout.write('OK');
  process.exit(0);
}
