# Plan only — run to the launch checkpoint and stop

Follow `${CLAUDE_PLUGIN_ROOT}/skills/autodev/workflows/run.md` steps 1 through 6 (profile, plan, test review,
worktree and baseline, first red test, launch checkpoint). Do not start step 7.

The output is the checkpoint package, per lane:

- seams;
- GWT scenarios in slice order;
- quadrant placement of every behavior, and the First-U choice with its
  business impact, risk, and foundational reasons;
- guards;
- exemption, if any;
- the first red test (path, commit) and its failure lines from `<lane>/red.log`;
- test review findings and proposed test-fix lanes.

When the user confirms, set `controller.sh set <slug> checkpoint confirmed` for
each lane. A later `/autodev` run on the same input finds the confirmed lanes
and starts at step 7 with no stops.
