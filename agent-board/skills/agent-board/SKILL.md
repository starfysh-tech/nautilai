---
name: agent-board
description: Work, file, and answer cards on an Agent Board, a shared work board reached through the agent-board MCP server. Use when the user says "work the board", "what's on the board", "file a card", "put this on the board", "what's waiting on me", "answer the blocked card", "make a board dashboard", or names a card by number, or when agent-board tools (next, progress, done, create, view) are available and the task is to pull or route work.
---

# Agent Board

A board holds cards (units of work). Workers pull cards and finish them; a coordinator or the
owner files and routes them. One bearer token fixes your role and, for a worker, your board. The
tools come from the `agent-board` MCP server (in Claude Code they show up as
`mcp__plugin_agent-board_agent-board__<tool>`). If they are not in your tool list, they may be
deferred: search for them by name (your tool search) before going to **Setup**.

## Roles

Look at your tool list: the tools you were given tell you your role.

| Role | Tools | Board |
|---|---|---|
| worker | `next`, `progress`, `block`, `done`, `release`, `view` | Bound to one board by the token. Never pass `board`; naming another board is refused |
| coordinator | `create`, `edit`, `cancel`, `view` | Pass `board` on every call (`view` may omit it, except for one card) |
| owner | coordinator's tools plus `answer` | Same as coordinator |
| read-only | `view` | Any board (a read-only worker token: its own board) |

Every reply has `ok`, `next` (the suggested next tool) and `retry` (whether the same call could
succeed later). A refusal adds `reason`, `field` and `state`.

## Worker loop

1. `next` leases one card (urgent first, then the card longest in ready). Keep `claim_token` and `card.id`.
   Read `card.text`, the `thread` (earlier progress and the owner's answers) and `dependencies`.
2. Do the work. Call `progress` with `card`, `claim_token`, `text` between steps, **at least every
   15 minutes** (`lease_ms`). It renews the lease. A lapsed lease ends your claim and counts an attempt.
3. End the claim with exactly one of:
   - `done` with the result: what changed and where (commits, PRs, files, links).
   - `block` with a question for the owner and the context needed to answer it. The answer lands
     in the thread and the card goes back to ready, for whoever calls `next`.
   - `release` with the reason you cannot do it. Counts an attempt; at three attempts the card
     waits for the owner.
4. Call `next` again.

**Never call `next` while you hold a card.** Every call leases another card; it is not a way to
peek or to grab extra work. Finish, block or release first.

**Claim token.** It comes only from the `next` reply that issued it. Pass it back unchanged with
the card id on `progress`, `block`, `done` and `release`. Never write it anywhere: not in card text,
progress text, commits, files, logs or chat. It stops working when the claim ends.

**Empty `next`.** `card` is null and `empty` says why. Do not call `next` again in a loop, even
though `retry` is true. Stop and report to the user:

| `empty` | Meaning | Report |
|---|---|---|
| `no ready cards` | Nothing to do on this board | The board is clear |
| `waiting on owner` | A card is blocked on a question | The owner needs to answer it |
| `waiting on dependency` | Every ready card waits on a card not yet done or cancelled | Work is queued behind other cards |

Workers cannot create cards. Put work you discover in your `progress` or `done` text ("found: …")
so a coordinator can file it.

## Coordinator and owner

- **`create`** with `board`, `text`, and optionally `priority`, `depends_on`, `source_ref`.
  - `text`: the first line is the title; the rest is everything a worker in a fresh session needs
    (repo, paths, acceptance criteria). The worker has none of your context.
  - `priority`: `urgent` or `normal` (default).
  - `depends_on`: ids of cards **on the same board** that must be done or cancelled first.
  - `source_ref`: where the work comes from (issue URL, ticket id). For work found during another
    card, use `discovered-from:card N`. It is the dedup key: if an open card has the same
    `source_ref` or identical text, that card comes back with `repeat: true` and nothing new is made.
    Filing two different cards from one card? Make the refs differ (`discovered-from:card N: <slug>`).
  - Retrying a `create` is safe for the same reason.
- **Blocked cards** ("what's waiting on me"): `view {blocked: true}` lists questions across all
  boards, urgent first. The owner replies with `answer` (`board`, `card`, `text`); the card becomes
  ready and its attempts reset. A coordinator cannot answer: report the questions to the owner.
- **`cancel`** with `board`, `card`, optional `text` (reason). For a duplicate pass
  `duplicate_of: <id>`. A worker holding the card gets `not holder` on its next call.
- **`edit`** changes `text` or `priority` of an open card, nothing else.

## View

| Call | Worker | Coordinator / owner |
|---|---|---|
| `view {}` | Its board's cards, paged | One line per board with counts by state |
| `view {blocked: true}` | Its board's blocked cards | Blocked cards on every board |
| `view {board}` | n/a | That board's cards, paged |
| `view {card}` | One card and its thread | n/a: name the board (`invalid`, `field: board`) |
| `view {board, card}` | n/a | One card and its thread |

Paged lists return `cursor`; pass it back for the next page. `cursor: null` is the last page.
`view` writes nothing.

## Dashboards

When someone asks for a dashboard or a page that shows the board, build it from live `view` calls
rather than a copy, and let them describe the layout they want: each person's dashboard can differ.
Use these facts so it works on the first pass:

- **Connector name.** Use the connector's name exactly as the person added it (the Claude app lists
  it, for example `agent-board`). A display name that differs makes every query fail as absent.
- **Read-only first.** A dashboard needs only `view`. Build it on a read-only or coordinator token.
  Leave answering, editing and cancelling to chat with an owner token, rather than adding buttons
  that change the board.
- **Reply shapes** (every reply has `ok`; throw on `ok: false` with its `reason`):

  | Call | Rows are in | Row fields |
  |---|---|---|
  | `view {}` | `boards` | `board`, `counts.{ready, claimed, blocked, done, cancelled}` |
  | `view {blocked: true}` | `cards` | `board`, `id`, `text` (first line), `priority`, `state`, `depends_on` |
  | `view {board}` | `cards`, paged by `cursor` | `id`, `text` (first line), `priority`, `state`, `depends_on` |
  | `view {board, card}` | `card` and `thread` | card: `id`, `text` (full), `priority`, `state`, `depends_on`, `source_ref`; thread: `time` (epoch ms), `type`, `profile`, `outcome`, `text` |

- **Paging.** `view {board}` returns at most one page; follow `cursor` until it is `null`.
- **Card detail on click.** Use one query with blanks, `{board: "{{board}}", card: "{{card}}"}`,
  with rules that pin the board to an `enum` of board names and the card to a positive number. Set
  both when a card row is clicked.
- **New boards** appear in `view {}` automatically, but a per-board card table needs its board
  name in a query, so adding a board means adding its table.

## Rejections

| `reason` | What it means | Do this |
|---|---|---|
| `not holder` | Your claim is over (lease lapsed or card cancelled) | Drop the work on that card, tell the user what was left unfinished, call `next` |
| `wrong state` | The card is not in a state that allows this call | `view` the card and act on its real state |
| `not permitted` | Wrong role for this tool, or a board your token does not cover | Stop and report; do not try other tools to get around it |
| `invalid` | A field is missing or malformed | Fix the field named in `field` and resend |
| `not found` | No such card or board | Check the card id and board name (`view {}` lists boards for coordinators) |

An HTTP 401 or a failed connection means the token is missing or wrong: see **Setup**. If the
`agent-board` server is not listed at all (rather than failed), the token is not the problem: the
plugin or its server is turned off (for example by `--strict-mcp-config`).

## Setup

1. Ask the board owner for a token. Each token is a profile: a worker token for one board, a
   coordinator token, or a read-only one. The owner keeps the list and rotates tokens.
2. Export it in the shell that starts Claude Code, then restart Claude Code:

   ```bash
   export AGENT_BOARD_TOKEN='<token>'                    # e.g. in ~/.zshrc, never in a repo
   export AGENT_BOARD_URL='https://board.example.com'     # only for a board other than board.starfysh.net
   ```

3. Run `/mcp` (interactive sessions only). `agent-board` should show as connected with the tools for
   your role. A missing or wrong token shows as a failed connection (HTTP 401). If `agent-board`
   is not listed at all, the plugin is disabled or its server was excluded, e.g. by
   `--strict-mcp-config`, which drops plugin servers: leave that flag off.

Never put the token in a repository: not in `.mcp.json`, a committed `.env`, `claude mcp add
--scope project`, or card text. If you ever see a token in output, do not repeat it.

**Claude app** (claude.ai, desktop, mobile): the plugin's server does not apply there. Add a custom
connector instead: Settings, Connectors, Add custom connector, URL `<base>/mcp` (for example
`https://board.starfysh.net/mcp`), and under request headers add `x-auth-token` with the token as
its value. The app reserves `Authorization`, so the board also accepts `x-auth-token`.
