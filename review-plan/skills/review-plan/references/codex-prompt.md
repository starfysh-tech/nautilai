# Codex Prompt Template

Fill in [bracketed] sections from Phase 1 plan extraction, then pass the filled
text as the `task` prompt argument to the Codex companion script (see SKILL.md
Phase 2 — the direct-Bash invocation, not the `codex:codex-rescue` subagent).

Do NOT pass `--write` — this is read-only review. Add `--effort high` only for
architecturally complex plans.

```
Review this implementation plan for risks and simplification opportunities.
Read the affected files yourself and be skeptical.

<task>
You are reviewing an implementation plan against an existing codebase.
Infer the project type and tech stack from the files you read.

Plan Summary:
[extracted plan summary from Phase 1]

Files Affected:
[file paths only — read them yourself]
</task>

<grounding_rules>
- Cite specific file paths and line numbers for every claim
- Distinguish observed facts from inferences
- If you cannot verify a claim from the code, say so
</grounding_rules>

<structured_output_contract>
Use these exact section headers, in this order (simplification first):
## Simplifications — the smallest correct version: what to reuse, delete, or not build (be concrete, cite file:line)
## Risks — what will NOT work or will BREAK
## Missed — reachable edge cases, error handling, rollback gaps (skip speculative ones)
## Dependencies — affected imports, services, external systems
## Assumptions — which assumptions are most likely WRONG and how to verify each before coding
</structured_output_contract>
```
