## Edge Cases

**Grouped PRs:**
- If any package in the group has breaking changes → INVESTIGATE
- If all are patches/minor dev deps and CI is passing → AUTO-MERGE
- Process as single unit (don't split)

**@types/* packages:**
- Check usage of corresponding runtime package
- Example: @types/react → look for react usage
- If runtime package unused → SKIP

**React + React-DOM:**
- Must update together (version parity required)
- If mismatch → INVESTIGATE (manual coordination needed)

**Pre-release versions:**
- alpha/beta/rc → INVESTIGATE (never auto-merge)
- Wait for stable release

**Transitive dependencies:**
- If PR updates transitive dep only → check parent package
- Example: `postcss` updated by `tailwindcss` → verify Tailwind still works
