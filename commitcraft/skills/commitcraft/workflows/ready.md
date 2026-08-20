# Ready Workflow

Promote the current branch's draft PR to ready-for-review, then arm auto-merge.

**Never use `--admin`, `--no-verify`, or a force push.** If a gate blocks, STOP and
report.

## Phase 1: Gather

```bash
gh pr view --json number,url,state,isDraft,mergeable,mergeStateStatus,reviewDecision,autoMergeRequest,statusCheckRollup,baseRefName
```

If it fails: "No PR found for this branch. Run `/commitcraft pr` first."

`gh` exposes neither repo-level auto-merge nor review threads — get those and the
merge method from GraphQL (`<owner>`/`<repo>` from `gh repo view --json owner,name`):

```bash
gh api graphql -f query='
query($owner:String!,$name:String!,$number:Int!){
  repository(owner:$owner,name:$name){
    autoMergeAllowed
    viewerDefaultMergeMethod
    pullRequest(number:$number){
      reviewThreads(first:100){ nodes { isResolved } }
    }
  }
}' -F owner=<owner> -F name=<repo> -F number=<number>
```

## Phase 2: Preflight

Report **all** failures at once, not the first.

### Classify checks

`statusCheckRollup` mixes node shapes — CheckRun carries `conclusion`, legacy
StatusContext carries `state`. Classify on `(.conclusion // .state)`.

| Bucket | Values | Blocks? |
|---|---|---|
| FAILING | `FAILURE`, `CANCELLED`, `TIMED_OUT`, `ACTION_REQUIRED`, `ERROR` | yes |
| PENDING | `conclusion` null, `status` `QUEUED`/`IN_PROGRESS`/`WAITING`, `state` `PENDING` | **no** |
| PASSING | `SUCCESS`, `SKIPPED`, `NEUTRAL` | no |

### Gates

| Condition | Report |
|---|---|
| `state` != `OPEN` | PR is `<state>` |
| any FAILING check | name each one |
| any `reviewThreads` node `isResolved: false` | N unresolved review threads |
| `mergeable` is `CONFLICTING` | conflicts with `<baseRefName>` |
| `autoMergeAllowed` is `false` | auto-merge disabled — enable at **Settings → General → Pull Requests → Allow auto-merge** |

### If `mergeStateStatus` is `BEHIND`

Continue to Phase 3. Add to the Phase 5 report:

```
⚠ Branch is behind <base>. Only blocks merge if the repo requires branches
  up to date — squash merges are linear regardless. To update it yourself
  (commitcraft will not force-push):
    git pull --rebase origin <base> && git push --force-with-lease
```

## Phase 3: Promote

`isDraft` true → `gh pr ready`. Already false → say so, continue.

Must run before Phase 4: auto-merge cannot be armed on a draft
(`Pull Request is still a draft`).

## Phase 4: Arm auto-merge

`autoMergeRequest` non-null → already armed, skip to Phase 5.

**No PENDING checks and `reviewDecision` not blocking** → `--auto` merges
immediately via `mergePullRequest` instead of arming. Ask first with
`AskUserQuestion`:

- "Nothing left to wait for — `--auto` will merge this now, not arm it. Merge?" →
  **Merge now** / **Leave it ready** (skip to Phase 5)

Otherwise arm, method from `viewerDefaultMergeMethod`:

```bash
gh pr merge --auto --squash   # or --rebase / --merge
```

Any `gh` error: STOP, report verbatim.

## Phase 5: Report

```
✓ PR ready: <url>
✓ Auto-merge armed (<method>)

Waiting on:
  - N checks in flight: <names>
  - Approval (reviewDecision: REVIEW_REQUIRED)
```

Omit lines that don't apply.
