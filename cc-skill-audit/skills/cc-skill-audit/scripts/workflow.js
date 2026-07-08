export const meta = {
  name: 'cc-skill-audit-sweep',
  description: 'Score every SKILL.md (clarity, frontmatter, trigger quality), fact-check each score, rank worst-to-best',
  phases: [
    { title: 'Score', detail: 'one Haiku worker per SKILL.md', model: 'haiku' },
    { title: 'Verify', detail: 'fact-check each score against disk', model: 'sonnet' },
    { title: 'Rank', detail: 'rank worst-to-best + cross-set patterns' },
  ],
}

// args: { skills: [{scope: "global"|"project"|"plugin", path: "/abs/path/to/SKILL.md"}, ...], docs_rules: "<string>" }
// Guard: args sometimes arrives JSON-encoded as a string.
const ARGS = (typeof args === 'string') ? JSON.parse(args) : args
const SKILLS = ARGS.skills
const DOCS_RULES = ARGS.docs_rules || ''

const groundingClause = DOCS_RULES
  ? `\n\nGrade frontmatter/description rules against these current documented rules, not your memory: ${DOCS_RULES}`
  : ''

const SCORE_SCHEMA = {
  type: 'object',
  properties: {
    name: { type: 'string', description: 'skill name from frontmatter, or folder name if missing' },
    clarity: { type: 'integer', minimum: 1, maximum: 5 },
    clarity_note: { type: 'string' },
    frontmatter_pass: { type: 'boolean', description: 'valid YAML frontmatter with BOTH name and description fields' },
    frontmatter_note: { type: 'string' },
    trigger_quality: { type: 'integer', minimum: 1, maximum: 5 },
    trigger_note: { type: 'string' },
    top_fix: { type: 'string', description: 'the single highest-value fix, one sentence' },
    evidence: { type: 'string', description: 'disk evidence supporting every factual claim above: files checked with ls, line numbers quoted' },
  },
  required: ['name', 'clarity', 'frontmatter_pass', 'trigger_quality', 'top_fix', 'evidence'],
}

const VERIFY_SCHEMA = {
  type: 'object',
  properties: {
    factual_claims_ok: { type: 'boolean' },
    corrections: { type: 'string', description: 'what was wrong and what is actually true, with paths; empty if all claims verified' },
    corrected_top_fix: { type: 'string', description: 'replacement top fix if the original rested on a false premise; empty otherwise' },
  },
  required: ['factual_claims_ok', 'corrections'],
}

const scorePrompt = (s) => `Read the Claude Code skill file at ${s.path} and audit it. Score:
- clarity (1-5): are the instructions clear and unambiguous? 5 = a fresh agent could execute without guessing.
- frontmatter (pass/fail): does it start with valid YAML frontmatter containing BOTH a "name" and a "description" field?
- trigger_quality (1-5): does the description clearly say WHEN to use the skill, with concrete trigger phrases a user would actually type? 5 = explicit trigger phrases + clear scope boundaries; 1 = vague or missing.
Also give the single highest-value fix for this skill (one sentence, concrete).${groundingClause}

GROUNDING RULES (violations invalidate your audit):
- Before claiming ANY referenced file, script, or directory is missing/nonexistent/aspirational, run: ls -laR ${s.path.replace(/\/SKILL\.md$/, '')} and check the actual listing. Only claim "missing" for paths you verified are absent.
- Before claiming a section, boundary statement, or invocation command is absent from SKILL.md, quote the line range you checked.
- Every factual claim in your output must appear in your "evidence" field with the check that supports it.
Be a tough grader on quality, but make zero unverified factual claims. Return only structured output.`

const verifyPrompt = (s, score) => `You are an adversarial fact-checker. A scorer audited the Claude Code skill at ${s.path} and produced:
${JSON.stringify(score, null, 1)}

Verify every FACTUAL claim (not the subjective 1-5 scores):
1. ls -laR ${s.path.replace(/\/SKILL\.md$/, '')} — if the scorer claims files/scripts are missing or aspirational, check whether they exist (also check any absolute/repo-relative paths mentioned).
2. Read ${s.path} — if the scorer claims a section, trigger phrase, entry point, or boundary statement is absent, confirm by reading; quote line numbers.
3. Check any quoted lengths/counts (e.g. "1200-char description") against the real file.${groundingClause}
If the top_fix rests on a false premise, write a corrected top_fix grounded in what is actually on disk. Return only structured output.`

phase('Score')
const audited = await pipeline(
  SKILLS,
  (s) => agent(scorePrompt(s), {
    label: `score:${s.path.split('/').slice(-2)[0]}`,
    phase: 'Score', model: 'haiku', schema: SCORE_SCHEMA,
  }),
  (score, s) => score && agent(verifyPrompt(s, score), {
    label: `verify:${s.path.split('/').slice(-2)[0]}`,
    phase: 'Verify', model: 'sonnet', schema: VERIFY_SCHEMA,
  }).then(v => ({
    ...score,
    scope: s.scope,
    path: s.path,
    top_fix: (v && v.corrected_top_fix) ? v.corrected_top_fix : score.top_fix,
    verification: v ? { ok: v.factual_claims_ok, corrections: v.corrections } : { ok: false, corrections: 'verifier did not return' },
  }))
)

const results = audited.filter(Boolean)
const corrected = results.filter(r => !r.verification.ok).length
log(`${results.length}/${SKILLS.length} skills scored and fact-checked (${corrected} needed corrections)`)

phase('Rank')
const report = await agent(
  `You are producing the final content of a markdown skill-audit scorecard. Here are fact-checked audit results for ${results.length} Claude Code skills (scope "global" = ~/.claude/skills, "project" = repo .claude/skills, "plugin" = installed plugin skills). Each entry was adversarially verified against disk; the "verification" field notes corrections already applied — treat top_fix and corrections as ground truth, and do NOT resurrect claims the verifier overturned:

${JSON.stringify(results, null, 1)}

Produce a complete markdown document with:
1. Title "# Skill Audit Scorecard" + one-line date-free summary (counts, avg scores, frontmatter fail count) noting all factual claims are disk-verified.
2. A ranking table of ALL skills sorted WORST to BEST (weakest at top). Rank by total = clarity + trigger_quality, frontmatter fail breaks ties toward worse. Columns: Rank | Skill | Scope (global/project/plugin) | Clarity | Frontmatter | Trigger | Top Fix.
3. A "Patterns Across the Set" section: 3-6 concrete cross-cutting observations, each cited with example skill names — only patterns supported by the verified evidence.
4. A short "Fix First" list: the 5 weakest skills with their single highest-value fix.
Return ONLY the raw markdown document, no preamble.`,
  { label: 'rank+synthesize', phase: 'Rank' }
)

return { report, results }
