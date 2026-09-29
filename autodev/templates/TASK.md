# Task

{{TASK}}

## Acceptance criteria
- Define objective completion checks here.

## Constraints
- Keep changes minimal.
- Respect existing architecture unless explicitly authorized.

## Seams
- Public interfaces the tests observe; confirmed at the launch checkpoint.

## Scenarios
- Given/When/Then, one per slice, in slice order.

## Quadrant
- Complexity and coupling per behavior; the First-U choice.

## Guards
- Checks the spec demands; one guard-removal patch each.

## Authorized extractions
- none

## Test edits authorized
- none

## Red tests
red_tests: pending
- slice 1: path/to/test — scenario name

## Verification
- bash VERIFY.sh
