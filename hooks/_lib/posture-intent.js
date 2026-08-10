// Shared activate/deactivate intent matcher for the ValarMind posture trackers.
//
// Every tracker used to test /VERB\b.*\bNAME\b/ against the prompt. The
// unbounded `.*` made a prompt that names two postures match both patterns, so
// "stop ponytail, keep caveman" cleared the caveman flag too — the postures
// cancelled each other. All posture names are registered here, which lets the
// gap between the verb and the name be required to name no *other* posture.
// Reverse order ("caveman off") must be adjacent for the same reason.
//
// Ambiguous prompts return null and leave the flag untouched: changing posture
// state needs an unambiguous ask.
//
// Self-check: `node hooks/_lib/posture-intent.js`

const NAMES = {
  caveman: 'caveman',
  ponytail: 'ponytail',
  superpowers: 'superpowers',
  'obsidian-brain': 'obsidian[ -]?brain|c[eé]rebro do obsidian',
};

const ON_VERBS = 'activate|enable|turn on|start|talk like|fale como|ative|ativar|ligar';
const OFF_VERBS = 'stop|disable|deactivate|turn off|parar|desativar|desligar';
const ON_SUFFIX = 'mode|modo|on|activate|enable|turn on|start';
const OFF_SUFFIX = 'off|stop|disable|deactivate|turn off|parar|desativar|desligar';

// "normal mode" is a documented exit for caveman and ponytail only (their
// SKILL.md lists it). superpowers and obsidian-brain never honoured it and keep
// their own toggles — do not widen the blast radius here.
const RESET = /\b(normal mode|modo normal)\b/i;
const RESET_SLUGS = new Set(['caveman', 'ponytail']);

// Filler tolerated between verb and name ("stop the ", "desativar o ").
const MAX_GAP = 40;

const SEP = '[\\s,.:;\\u2013\\u2014-]*';

const cache = new Map();

function patternsFor(slug) {
  const cached = cache.get(slug);
  if (cached) return cached;

  const self = NAMES[slug];
  if (!self) throw new Error(`unknown posture slug: ${slug}`);

  const others = Object.keys(NAMES)
    .filter(k => k !== slug)
    .map(k => NAMES[k])
    .join('|');
  const gap = `(?:(?!${others})[\\s\\S]){0,${MAX_GAP}}`;
  const name = `(?:${self})`;

  const built = {
    onBefore: new RegExp(`\\b(?:${ON_VERBS})\\b${gap}\\b${name}\\b`, 'i'),
    offBefore: new RegExp(`\\b(?:${OFF_VERBS})\\b${gap}\\b${name}\\b`, 'i'),
    onAfter: new RegExp(`\\b${name}\\b${SEP}\\b(?:${ON_SUFFIX})\\b`, 'i'),
    offAfter: new RegExp(`\\b${name}\\b${SEP}\\b(?:${OFF_SUFFIX})\\b`, 'i'),
  };
  cache.set(slug, built);
  return built;
}

// Returns 'on', 'off', or null (no intent expressed about this posture).
// 'off' wins over 'on' when both match — the safe direction.
function matchIntent(prompt, slug) {
  const text = String(prompt || '');
  if (RESET_SLUGS.has(slug) && RESET.test(text)) return 'off';

  const re = patternsFor(slug);
  if (re.offBefore.test(text) || re.offAfter.test(text)) return 'off';
  if (re.onBefore.test(text) || re.onAfter.test(text)) return 'on';
  return null;
}

module.exports = { matchIntent, POSTURE_SLUGS: Object.keys(NAMES) };

if (require.main === module) {
  const assert = require('assert');
  const cases = [
    // The reported bug: naming both postures must not clear the untargeted one.
    ['stop ponytail, keep caveman', 'ponytail', 'off'],
    ['stop ponytail, keep caveman', 'caveman', null],
    ['stop caveman but keep ponytail', 'caveman', 'off'],
    ['stop caveman but keep ponytail', 'ponytail', null],
    ['turn off superpowers, keep caveman', 'caveman', null],
    ['turn off obsidian-brain, keep ponytail', 'ponytail', null],
    // Merely discussing the postures toggles nothing.
    ['o ponytail e o caveman estao em conflito', 'caveman', null],
    ['o ponytail e o caveman estao em conflito', 'ponytail', null],
    // Single-posture commands still work, both orders, both languages.
    ['stop caveman', 'caveman', 'off'],
    ['desativar o ponytail', 'ponytail', 'off'],
    ['caveman off', 'caveman', 'off'],
    ['ponytail off', 'ponytail', 'off'],
    ['caveman mode', 'caveman', 'on'],
    ['ativar caveman', 'caveman', 'on'],
    ['fale como caveman', 'caveman', 'on'],
    ['superpowers on', 'superpowers', 'on'],
    ['obsidian brain on', 'obsidian-brain', 'on'],
    // "normal mode" exits caveman and ponytail, and only those two.
    ['normal mode', 'caveman', 'off'],
    ['modo normal', 'ponytail', 'off'],
    ['normal mode', 'superpowers', null],
    ['normal mode', 'obsidian-brain', null],
  ];

  for (const [prompt, slug, expected] of cases) {
    assert.strictEqual(
      matchIntent(prompt, slug),
      expected,
      `${JSON.stringify(prompt)} / ${slug} → expected ${expected}`
    );
  }
  assert.throws(() => matchIntent('x', 'nope'), /unknown posture slug/);
  console.log(`posture-intent: ${cases.length} cases OK`);
}
