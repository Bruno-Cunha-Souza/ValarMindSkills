// Shared SKILL.md resolver for ValarMind hook scripts.
// Resolution order:
//   1. $VALARMIND_SKILLS_ROOT/<slug>/SKILL.md
//   2. <hooks>/<slug>/../../skills/<slug>/SKILL.md  (e.g. ~/.cursor/hooks/caveman → ~/.cursor/skills)
//   3. <hooks>/<slug>/../skills/<slug>/SKILL.md     (legacy / mistaken layout)

const fs = require('fs');
const path = require('path');

function resolveSkillMd(slug, hookDir) {
  const dir = hookDir || __dirname;
  const candidates = [];

  if (process.env.VALARMIND_SKILLS_ROOT) {
    candidates.push(path.join(process.env.VALARMIND_SKILLS_ROOT, slug, 'SKILL.md'));
  }

  candidates.push(path.join(dir, '..', '..', 'skills', slug, 'SKILL.md'));
  candidates.push(path.join(dir, '..', 'skills', slug, 'SKILL.md'));

  for (const p of candidates) {
    try {
      return fs.readFileSync(p, 'utf8');
    } catch (e) {
      /* try next */
    }
  }

  return '';
}

module.exports = { resolveSkillMd };
