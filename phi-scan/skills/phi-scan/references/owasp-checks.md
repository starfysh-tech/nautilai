# OWASP grep checks (Django / React)

Read this only after confirming the stack in workflow step 3. These are **shallow
`grep` heuristics specific to Django and React**, not a real SAST. They overlap
with — and are no substitute for — dedicated tools (gitleaks, semgrep, bandit).
Run only the subsections whose stack is present, and treat every hit as a
candidate to verify by reading the file, not a confirmed vulnerability.

Set `TARGET_PATH` to the scanned path (default `.`).

## 1. Hardcoded secrets & API keys (any stack)

```bash
grep -rnE "api[_-]key|API[_-]KEY|secret[_-]key|SECRET[_-]KEY|password[[:space:]]*=|token[[:space:]]*=" "$TARGET_PATH" --include="*.py" --include="*.ts" --include="*.tsx"
```

Flag: secrets in code rather than env vars; API keys in committed config; passwords in fixtures that aren't obvious test data.

## 2. SQL injection (Django)

```bash
grep -rnE "\.raw\(|\.execute\(|executemany\(|cursor\.execute" "$TARGET_PATH" --include="*.py"
grep -rnE "SELECT.*%s|INSERT.*%s|UPDATE.*%s" "$TARGET_PATH" --include="*.py"
```

Flag: string interpolation (f-strings, `%`) or user input in raw SQL with no parameterization. The Django ORM's normal query methods are parameterized — only raw SQL is in scope here, so don't flag ordinary ORM calls.

## 3. XSS (Django templates + React)

```bash
# Django: |safe filter, mark_safe()
grep -rnE "\|[[:space:]]*safe|mark_safe\(" "$TARGET_PATH" --include="*.html" --include="*.py"

# React: dangerouslySetInnerHTML / innerHTML
grep -rnE "innerHTML|dangerouslySetInnerHTML" "$TARGET_PATH" --include="*.tsx" --include="*.ts" --include="*.jsx"
```

Flag: user-controlled input rendered through `|safe`, `mark_safe()`, `innerHTML`, or `dangerouslySetInnerHTML` without sanitization.

## 4. Authorization gaps (Django REST)

```bash
grep -rnE "class.*ViewSet|class.*APIView" "$TARGET_PATH" --include="*.py" -A 10
```

Read the matches above and check by eye for classes whose 10-line context has no `permission_classes`. (A piped `grep -v` here would need `Bash(grep:*)` to auto-approve a compound pipeline, which it may not — run this as a single invocation and filter manually.)

```bash
grep -rnE "#.*@login_required|#.*IsAuthenticated" "$TARGET_PATH" --include="*.py"
```

Flag: DRF `ViewSet`/`APIView` classes with no `permission_classes`, or commented-out auth decorators. Verify by reading — a global default permission class (set in `settings.py`) can make a missing per-view one a non-issue.

## 5. Sensitive data in logs (any stack)

```bash
grep -rnE "log.*password|log.*token|log.*secret|logger\..*patient" "$TARGET_PATH" --include="*.py" --include="*.ts" -i
```

Flag: passwords, tokens, or PHI in log statements; exception handlers logging full request bodies.
