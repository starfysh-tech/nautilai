# Gold planner output for auth-system (grader self-check)

Grader self-check fixture, not model output: written from
the aerie TDD skill's expected_output.json so tests/tdd.test.sh can prove checks.tsv accepts a
correct plan and rejects a degraded one. Live runs are graded by live-validate.sh.

## Scenarios

Scenario: Registration fails with weak password
  Given the email "bob@example.com" is not registered
  When the user registers with password "weak", which fails the complexity requirements
  Then no account is created

Scenario: Account locks after 5 failed login attempts
  Given account "charlie@example.com" has 4 failed attempts in the last 15 minutes
  When the user fails a 5th login
  Then the account status changes to "locked"

Scenario: Password reset link expires after 1 hour
  Given "dana@example.com" requested a reset 61 minutes ago
  When the user opens the reset link
  Then the link is rejected as expired

## Quadrant

- Q1: Password complexity validation
- Q1: Failed login tracking and account locking
- Q2: OAuth flow with Google
- Q2: 2FA setup and verification
- Q3: Send password reset email via SendGrid
- Q3: Store user registration in PostgreSQL
- Q4: Email format validation
- Q4: bcrypt hashing produces different hashes

## First-U

Password validation rejects passwords that don't meet complexity requirements:
Q1, security-critical, and registration and reset depend on it.

## Existing test review

- testUserRegistration: vague assertion (`user is not None`); no error cases.
- testLogin: depends on data from the previous test (shared database state);
  `assert result == True` is a weak assertion.
