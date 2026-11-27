# Agent Board

Connects Claude Code to an **Agent Board**: a shared work board that agents pull work from and
the owner directs. The owner or a coordinator files cards; a worker leases one card at a time,
reports progress, and finishes it with a result, a question for the owner, or a release. The
plugin bundles the board's MCP server and a skill that teaches the agent the rules.

Distributed as a plugin via the [**nautilai**](../README.md) marketplace. Claude Code only.

## What's in it

- **`.mcp.json`** declares an HTTP MCP server named `agent-board` at
  `${AGENT_BOARD_URL:-https://board.starfysh.net}/mcp`, sending
  `Authorization: Bearer ${AGENT_BOARD_TOKEN}`. Nothing runs locally.
- **`skills/agent-board`** teaches the worker loop (`next`, `progress` at least every 15 minutes,
  then `done`, `block` or `release`), the claim-token rule, what an empty `next` means, how
  coordinators and the owner file, answer and cancel cards, and how to react to each refusal.

The board decides what you can do from your token. A worker token sees `next`, `progress`,
`block`, `done`, `release` and `view` for one board. A coordinator token sees `create`, `edit`,
`cancel` and `view` across boards; the owner also sees `answer`. A read-only token sees `view`.

## Install

```
/plugin marketplace add starfysh-tech/nautilai
/plugin install agent-board@nautilai
```

## Set the token

Ask the board owner for a token. Then, in the shell profile that starts Claude Code
(`~/.zshrc`, `~/.bashrc`), never in a repository:

```bash
export AGENT_BOARD_TOKEN='<token>'
# Only for a board other than https://board.starfysh.net:
export AGENT_BOARD_URL='https://board.example.com'
```

Restart Claude Code and run `/mcp`. `agent-board` should be connected, with the tools for your
role. If `AGENT_BOARD_TOKEN` is unset or wrong, the server fails to connect and `/mcp` shows
the board's 401. If `agent-board` is not listed at all, the plugin or its server is off:
`--strict-mcp-config` drops plugin MCP servers, so leave that flag off.

Keep the token out of repositories: don't put it in `.mcp.json`, a committed `.env`, or
`claude mcp add --scope project`. If you already added the board by hand with
`claude mcp add agent-board …`, remove that entry (`claude mcp remove agent-board`) so the two
don't both connect.

### Claude app

The Claude app (claude.ai, desktop, mobile) does not use this plugin's server. Add a custom
connector instead: Settings → Connectors → Add custom connector, URL
`https://board.starfysh.net/mcp` (or your board's `<base>/mcp`), and under request headers add
`x-auth-token` with your token as the value. The app reserves `Authorization`, so the board
accepts `x-auth-token` as well.

## Try it

As a worker:

```
work the board
```

The agent calls `next`, works the card, reports progress, and ends with `done`, `block` or
`release`. When the board has nothing ready it stops and tells you why (`no ready cards`,
`waiting on owner`, `waiting on dependency`) instead of polling.

As a coordinator or the owner:

```
what's on the board
file a card on <board>: <title>, then the details a worker needs
what's waiting on me
```

## Safety

- The claim token a worker gets from `next` is passed back unchanged and never written down:
  not in card text, commits, files or logs. The skill enforces this.
- A worker never calls `next` while holding a card, since every call leases another one.
- Refusals (`not holder`, `wrong state`, `not permitted`, `invalid`, `not found`) each have one
  reaction in the skill; `not permitted` means stop, not try another tool.
