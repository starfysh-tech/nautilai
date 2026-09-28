# TDD rules for autodev

The orchestrator reads this whole file. `init_task_lane.sh` cuts the marked
sections into each lane's `TDD-worker.md` and `TDD-review.md`. A section opens
with `<!-- tdd: roles=<role,...> [stack=<name>] -->` and closes with
`<!-- /tdd -->`. Roles are `worker` and `review`. A `stack=` section is kept only
when the TDD profile's `stack` key lists that name. Text outside a section is
for the orchestrator only.

Terms as SKILL.md uses them: lane, slice, red test, launch checkpoint, guard,
TDD profile.

## FIRST-U

<!-- tdd: roles=worker,review -->
- **Fast** — unit tests under 100ms, integration tests under 1s. Mock external
  dependencies; keep DB work and network calls out of unit tests.
- **Isolated** — each test builds its own data. No shared mutable state, no
  dependence on another test's data or on run order.
- **Repeatable** — seed random values; control time and date; no reliance on
  external services.
- **Self-validating** — assert specific expected values with binary pass/fail.
  Use realistic data, not placeholders such as `"abc"` or `"1234"`.
- **Thorough/Timely** — the test exists before the code. Cover the happy path,
  error cases, and boundaries: 0, 1, max, max+1; null, empty, invalid input.
- **Understandable** — name tests `[behavior] when [condition] should
  [outcome]` (Python: `test_[behavior]_when_[condition]`; TypeScript:
  `it('[behavior] when [condition]')`). Given/When/Then structure; one behavior
  per test.
<!-- /tdd -->

## Complexity quadrant

Place every behavior in the lane's plan into one quadrant before writing red
tests. The quadrant sets the red-test kind.

```
High complexity
    │  Q2: complex + many deps   │  Q1: complex + few deps
    │  extract, then test        │  TEST FIRST
────┼────────────────────────────┼─────────────────────────
    │  Q3: simple + many deps    │  Q4: simple + few deps
    │  integration test only     │  test early
Low complexity ──────────── few → many dependencies
```

- **Q1** (tax calculation, password validation, pricing, date arithmetic):
  unit red tests. These drive the design, so they come first.
- **Q4** (formatters, validators, transformations, utilities): unit red tests,
  early.
- **Q3** (CRUD with validation, API wrappers, thin service layers): one
  integration red test at the outer seam. Unit tests add little here.
- **Q2**: write the extraction into TASK.md `## Authorized extractions` — pull
  the complex logic into a pure unit (it becomes Q1) and leave a thin
  coordinator. Unit red tests go on the extracted unit; the coordinator gets an
  integration red test. Without the TASK.md entry the review gate blocks the
  extraction as out of scope.

Priority: Q1, then Q4, then Q3, then Q2.

### First-U choice

Among Q1 behaviors, the first slice is the one with the highest:

1. business impact — revenue, security, data integrity;
2. risk — probability times severity of a bug;
3. foundational weight — other behavior depends on it.

The First-U choice sets slice order inside a lane and lane order across the run.
Show it at the launch checkpoint.

## Given/When/Then

```gherkin
Scenario: [one-line description of one behavior]
  Given [system state before the action]
    And [more preconditions]
  When [the action that triggers the behavior]
  Then [expected outcome]
    And [more outcomes]
```

- One scenario per behavior; one scenario per slice.
- Business language, not implementation details.
- Specific outcomes, never "it works".
- Scenarios are independent of each other.

```gherkin
Scenario: Account locks after 5 failed login attempts
  Given a user account exists with email "alice@example.com"
    And the account has 4 previous failed login attempts
  When the user attempts to login with an incorrect password
  Then the account status changes to "locked"
    And the user receives an error "Account locked. Contact support."
    And no session is created
```

Include boundary scenarios (0, 1, max, max+1; null, empty, invalid) and error
scenarios, not only the happy path.

## Planning a run

For each lane:

1. Identify behaviors and place each in a quadrant.
2. Write one GWT scenario per behavior; order them by the First-U choice.
3. Name the seams — the public interfaces the tests observe. No test is written
   at a seam the launch checkpoint did not confirm.
4. List the guards the spec demands (permission checks, trigger bypasses,
   abort-on-truncation) in TASK.md `## Guards`.
5. Mark `red_tests: exempt — <reason>` only when the task has no testable
   behavior (docs, config). Exempt lanes verify through the lane `VERIFY.sh`.

## The loop

Each slice runs red, then green:

1. **Red** — the orchestrator writes one red test for the next scenario, runs
   `expect_run.sh red`, and commits it. It must fail, and the saved failure line
   must name the missing behavior. An import error for the not-yet-written unit
   is a valid red; a timeout, a missing command, or "no tests collected" is not.
2. **Green** — the worker writes the minimal code that passes it.
3. **Commit** — verify and the review gate pass, then the green commit.
4. **Repeat** for the next scenario.

After the last slice: the guard check, then one refactor attempt.

<!-- tdd: roles=worker -->
### Worker rules

- Work on the current slice's red test only. Do not implement ahead of it.
- Write only enough code to pass it. No speculative features.
- Never edit, move, skip, or delete a red test or the test config the TDD
  profile lists under `test_config`.
- Never edit a test file that existed before the lane started, unless TASK.md
  lists it under `## Test edits authorized`. A red test that contradicts an
  existing test is a spec gap.
- You may add tests for boundaries and error cases, only at the seams TASK.md
  lists, in new test files.
- A red test that exposes a spec gap is a finding. Pin the current rule with a
  test that documents it (skip the pin when your prompt says
  `unattended: true`), do not widen the implementation, and return
  `status: blocked` with `failure_signature: spec_gap: <what the spec does not
  say>`.
- Before you return, run the TDD profile's `format` command on the files you
  touched.
- Test through the seam. Mock external dependencies only (APIs, email,
  storage), never internal collaborators.
- Build test data with the repo's factories or fixtures, not raw model
  creation.
<!-- /tdd -->

<!-- tdd: roles=worker -->
### Refactor attempt

When the task says "refactor the changed code, behavior unchanged": improve
structure only. Change no test file. The red tests and the full suite must stay
green.
<!-- /tdd -->

## Verification gates

`verify.sh` runs these in order and stops at the first failure: the frozen-test
check, the current slice's red test, lint and format check on changed files,
the lane `VERIFY.sh`, the full suite. The full suite always runs.

Parallel lanes share one machine. When the TDD profile sets `db_isolation`,
every test command in a lane runs with it; without it, guard checks run
serially.

### Guard check

<!-- tdd: roles=review -->
For every guard in TASK.md, write one patch that removes only that guard. The
guard's named test must pass before the patch and fail after it. Some bypasses pass silently when misconfigured — for
example `pgtrigger.ignore()` with no arguments ignores every trigger — so a
guard's test must assert the guarded effect, not only that the call happened.
<!-- /tdd -->

## Coverage

<!-- tdd: roles=review -->
Coverage is evidence for review, never a gate.

- Critical paths (auth, payments, data validation): expect every branch
  covered. An uncovered branch there is an advisory finding.
- Business logic: expect 80% or more of lines and branches.
- Thin adapters and wrappers: integration tests only; ignore their unit
  metrics.
- Look for uncovered `except`/`catch` blocks, branches run 0 or 1 times,
  functions at 0%, and uncovered boundary conditions in `if` statements.
- A guard or a TASK.md scenario with no test at all is a blocking finding.
- Tests written for the number rather than a behavior are an advisory finding.
<!-- /tdd -->

## Test anti-patterns

<!-- tdd: roles=review -->
Blocking — the test lies or flakes, so a green result is false:

| Anti-pattern | What to look for |
|---|---|
| Tautological assertion | The expected value is recomputed the way the code computes it (`assert add(a, b) == a + b`, a hand-derived snapshot). Expected values must come from an independent source: a known-good literal, a worked example, the spec. |
| Can never fail | The assertion holds whatever the code does (`toBeTruthy()` on an object, no assertion at all). |
| Implementation-coupled | Mocks internal collaborators, or asserts through a side channel such as querying the DB instead of the interface. It breaks on a refactor although behavior did not change. |
| Interdependent | Depends on another test's data, on run order, or on shared mutable state. |
| Non-repeatable | Unseeded random values or real wall-clock time. |
| Unconfirmed seam | A new test at a seam TASK.md does not list. |
| Missing test | A guard or a TASK.md scenario with no test. |

Advisory — the test still tells the truth, but is weaker or slower:

| Anti-pattern | Fix |
|---|---|
| Tests a private method (`_method`) | Test the public behavior that uses it. |
| Fragile assertion (exact message with a timestamp) | Assert on the meaningful part only. |
| `sleep` / slow test (over the FIRST-U F limits) | Mock the async dependency or use a deterministic wait. |
| Placeholder data (`"abc"`, `"1234"`) | Use realistic values. |
| Written for coverage numbers | Test a requirement or behavior instead. |
| Name breaks the naming format | `[behavior] when [condition] should [outcome]`. |
<!-- /tdd -->

<!-- tdd: roles=review stack=rtl -->
Advisory, React Testing Library: `getByTestId` where `getByRole` or
`getByLabelText` works. Accessible queries test behavior, not structure.
<!-- /tdd -->

## Stack patterns

<!-- tdd: roles=worker stack=pytest -->
### pytest

```python
@pytest.mark.django_db
def test_user_cannot_login_after_5_failed_attempts(client, user_factory):
    user = user_factory.create(failed_login_count=4)
    response = client.post('/api/auth/login/', {
        'email': user.email, 'password': 'wrong-password'
    })
    assert response.status_code == 403
    user.refresh_from_db()
    assert user.is_locked is True
```

- Mark tests that hit the database with `@pytest.mark.django_db` (Django).
<!-- /tdd -->

<!-- tdd: roles=worker stack=factory_boy -->
### Factory Boy

- `factory.build()` for unit tests — no DB hit.
- `factory.create()` for integration tests — persists to the DB.
<!-- /tdd -->

<!-- tdd: roles=worker stack=vitest -->
### Vitest

```typescript
import { vi } from 'vitest';
import { authApi } from 'src/services/auth';

vi.mock('src/services/auth', () => ({
  authApi: { logIn: vi.fn() },
}));
```

- Mock at the module boundary the TDD profile names. Use the repo's existing
  mocking convention, not a new one.
<!-- /tdd -->

<!-- tdd: roles=worker stack=rtl -->
### React Testing Library

```typescript
it('shows error when login fails', async () => {
  vi.mocked(authApi.logIn).mockRejectedValue({ detail: 'Invalid credentials' });
  render(<LoginForm />);

  await userEvent.type(screen.getByLabelText(/email/i), 'test@example.com');
  await userEvent.click(screen.getByRole('button', { name: /sign in/i }));

  expect(await screen.findByRole('alert')).toHaveTextContent(/invalid credentials/i);
});
```

- `screen.getByRole` / `getByLabelText` over `querySelector` or `getByTestId`.
- `userEvent`, not `fireEvent`, for every user interaction.
<!-- /tdd -->

## Test review (`--review-tests`)

For each existing test at a seam the run touches:

1. Score each FIRST-U letter 0–10 with the evidence (`file:line`) for the score,
   plus an overall score out of 100.
2. List anti-patterns from the tables above. Blocking-class findings become
   proposed test-fix lanes (disposition `ask-user`). Everything else is
   `report`.
3. List missing scenarios: error cases (400/404/500), authorization,
   validation failures, boundaries, concurrency the code can reach.
4. For each finding, give the refactored test as a proposal. Never apply it.
5. List coverage gaps from the Coverage checklist.
