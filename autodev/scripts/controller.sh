#!/usr/bin/env bash
# Single machine-readable controller state for all autodev lanes.
# State lives in the *user repo* at .autodev/state.json; this script lives in
# the plugin install dir and must be invoked via ${CLAUDE_PLUGIN_ROOT}.
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
STATE_DIR="$ROOT/.autodev"
STATE_FILE="$STATE_DIR/state.json"
mkdir -p "$STATE_DIR"
# Keep autodev bookkeeping out of the user's git status.
[[ -f "$STATE_DIR/.gitignore" ]] || printf '*\n' > "$STATE_DIR/.gitignore"
python3 - "$STATE_FILE" "$@" <<'PY'
import fcntl, json, os, sys, tempfile, time

MAX_COUNTED_FAILURES = 3
MAX_TRANSIENT_RETRIES = 2

state_file = sys.argv[1]
args = sys.argv[2:]
cmd = args[0] if args else 'help'
# Concurrent lanes mutate one shared file: serialize the whole
# read-modify-write under an exclusive lock (released on process exit).
lock_fd = open(state_file + '.lock', 'w')
fcntl.flock(lock_fd, fcntl.LOCK_EX)
try:
    with open(state_file) as f:
        state = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    state = {'version': 1, 'lanes': {}}
lanes = state.setdefault('lanes', {})
now = int(time.time())
if cmd == 'init-lane':
    lane = args[1]
    lanes.setdefault(lane, {
        'status': 'pending',
        'attempt_count': 0,
        'counted_failures': 0,
        'transient_retries': 0,
        'last_failure_class': None,
        'last_failure_fingerprint': None,
        'baseline_status': 'unknown',
        'parallel_safe': 'false',
        'worktree_path': None,
        'updated_at': now,
    })
elif cmd == 'set':
    lane, key, value = args[1], args[2], args[3]
    lanes.setdefault(lane, {})[key] = value
    lanes[lane]['updated_at'] = now
elif cmd == 'record-failure':
    lane, klass, fingerprint = args[1], args[2], args[3]
    lane_state = lanes.setdefault(lane, {})
    repeated = lane_state.get('last_failure_fingerprint') == fingerprint
    lane_state['last_failure_class'] = klass
    lane_state['last_failure_fingerprint'] = fingerprint
    lane_state['last_failure_repeated'] = repeated
    if klass == 'implementation':
        lane_state['counted_failures'] = int(lane_state.get('counted_failures', 0)) + 1
    # A non-transient failure ends the current transient-retry cycle, so the
    # cap only limits *consecutive* transient retries. A transient failure
    # must NOT reset it: the orchestrator records every verify fail here
    # before record-transient increments, so resetting on transient would
    # make the cap unreachable.
    if klass != 'transient':
        lane_state['transient_retries'] = 0
    lane_state['attempt_count'] = int(lane_state.get('attempt_count', 0)) + 1
    lane_state['updated_at'] = now
    if int(lane_state.get('counted_failures', 0)) >= MAX_COUNTED_FAILURES:
        lane_state['status'] = 'needs_guidance'
elif cmd == 'record-transient':
    # A `transient` classification (see classify_failure.sh) retries once
    # immediately without counting toward MAX_COUNTED_FAILURES — but nothing
    # short of this counter previously bounded how many times that could
    # happen in a row, so persistent rate-limiting could retry forever.
    lane = args[1]
    lane_state = lanes.setdefault(lane, {})
    lane_state['transient_retries'] = int(lane_state.get('transient_retries', 0)) + 1
    lane_state['updated_at'] = now
    if int(lane_state.get('transient_retries', 0)) >= MAX_TRANSIENT_RETRIES:
        lane_state['status'] = 'needs_guidance'
elif cmd == 'record-success':
    lane = args[1]
    lane_state = lanes.setdefault(lane, {})
    lane_state['status'] = 'done'
    lane_state['transient_retries'] = 0
    lane_state['attempt_count'] = int(lane_state.get('attempt_count', 0)) + 1
    lane_state['updated_at'] = now
elif cmd == 'check':
    # Gate for the orchestration loop: exit 0 = keep going, exit 1 = stop.
    lane = args[1]
    lane_state = lanes.get(lane, {})
    reasons = []
    if lane_state.get('status') in ('done', 'needs_guidance'):
        reasons.append(f"status={lane_state.get('status')}")
    if int(lane_state.get('counted_failures', 0)) >= MAX_COUNTED_FAILURES:
        reasons.append(f"counted_failures={lane_state.get('counted_failures')} (cap {MAX_COUNTED_FAILURES})")
    if int(lane_state.get('transient_retries', 0)) >= MAX_TRANSIENT_RETRIES:
        reasons.append(f"transient_retries={lane_state.get('transient_retries')} (cap {MAX_TRANSIENT_RETRIES})")
    if lane_state.get('last_failure_repeated'):
        reasons.append('repeated identical failure fingerprint')
    if reasons:
        print('stop: ' + '; '.join(reasons))
        sys.exit(1)
    print('continue')
    sys.exit(0)
elif cmd == 'show':
    print(json.dumps(state, indent=2))
    sys.exit(0)
else:
    print('usage: controller.sh init-lane <lane> | set <lane> <key> <value> | record-failure <lane> <class> <fingerprint> | record-transient <lane> | record-success <lane> | check <lane> | show', file=sys.stderr)
    sys.exit(1)
# Atomic replace so an unlocked reader can never observe a torn write.
tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(state_file), suffix='.tmp')
with os.fdopen(tmp_fd, 'w') as f:
    json.dump(state, f, indent=2)
os.replace(tmp_path, state_file)
PY
