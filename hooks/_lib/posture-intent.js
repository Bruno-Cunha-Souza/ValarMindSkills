// Activate/deactivate intent matcher for the ValarMind posture trackers.
//
// The gap between verb and name is capped at MAX_GAP, and reverse order
// ("obsidian-brain off") must be adjacent, so a passing mention followed by an
// unrelated "off" toggles nothing. Ambiguous prompts return null and leave the
// flag untouched: changing posture state needs an unambiguous ask.
//
// Self-check: `node hooks/_lib/posture-intent.js`

const NAMES = {
  'obsidian-brain': 'obsidian[ -]?brain|c[eé]rebro do obsidian',
};

const ON_VERBS = 'activate|enable|turn on|start|ative|ativar|ligar';
const OFF_VERBS = 'stop|disable|deactivate|turn off|parar|desativar|desligar';
const ON_SUFFIX = 'mode|modo|on|activate|enable|turn on|start';
const OFF_SUFFIX = 'off|stop|disable|deactivate|turn off|parar|desativar|desligar';

// Filler tolerated between verb and name ("stop the ", "desativar o ").
const MAX_GAP = 40;

const SEP = '[\\s,.:;\\u2013\\u2014-]*';

const cache = new Map();

function patternsFor(slug) {
  const cached = cache.get(slug);
  if (cached) return cached;

  const self = NAMES[slug];
  if (!self) throw new Error(`unknown posture slug: ${slug}`);

  const gap = `[\\s\\S]{0,${MAX_GAP}}`;
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
  const re = patternsFor(slug);
  if (re.offBefore.test(text) || re.offAfter.test(text)) return 'off';
  if (re.onBefore.test(text) || re.onAfter.test(text)) return 'on';
  return null;
}

module.exports = { matchIntent };

if (require.main === module) {
  const assert = require('assert');
  const cases = [
    // Both orders, both languages, filler between verb and name.
    ['stop obsidian-brain', 'obsidian-brain', 'off'],
    ['stop the obsidian brain', 'obsidian-brain', 'off'],
    ['desativar o obsidian-brain', 'obsidian-brain', 'off'],
    ['obsidian-brain off', 'obsidian-brain', 'off'],
    ['obsidian brain on', 'obsidian-brain', 'on'],
    ['ativar o cérebro do obsidian', 'obsidian-brain', 'on'],
    // Merely discussing the posture toggles nothing.
    ['o obsidian-brain anotou a sessão de ontem', 'obsidian-brain', null],
    ['o obsidian-brain anotou tudo, pode desligar o servidor', 'obsidian-brain', null],
    // "normal mode" is not an obsidian-brain exit.
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
