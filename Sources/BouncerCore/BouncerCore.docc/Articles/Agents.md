# Using Bouncer with coding agents

Keeping a coding agent's context small: summaries first, slices on request, and a fix loop that
re-checks only the files it edited.

## Overview

A full report on a large repo is far bigger than any context window: tens of thousands of
findings, megabytes of text. An agent doesn't need all of it. It needs a summary, one slice to
work on, and a quick way to confirm its fix. Bouncer offers that two ways: command-line flags that
work in any agent with a shell, and `bouncer mcp`, a long-lived server for agents that speak the
Model Context Protocol.

## From the command line

Every flag below works on `bouncer review`; all but `--changed-since` and the saved-run flags
work on `bouncer check` too.

- `--summary` prints only the totals by severity, the top rules and files, and the time taken, in
  a few hundred tokens. Start here. In JSON it's an object with no `findings`.
- `--format agent` prints findings grouped by file, with paths relative to the repo root, one
  `LINE RULE MESSAGE` line each, and a rule's message left out when it repeats the line before.
  It ends with how many were shown and the flags for the next page.
- `--group-by file|rule` picks the grouping for `agent` and `console` output.
- `--rule ID` and `--path GLOB` (both repeatable) and `--min-severity info|warning|error` narrow
  what's reported, after analysis. The exit code still follows `--severity-threshold`, on the
  narrowed set.
- `--limit N` and `--offset N` page through the findings in a stable file, line, and rule order.
- `review --changed-since REF` analyzes only the files changed since a git ref, plus untracked
  files. Project rules still see the whole module graph, from the facts cache.

`review` saves each run to `.bouncer-cache/last-run.json`, and once a run is saved, the next one
starts from it (`--from-last-run` is the default), re-analyzing only files whose contents changed.
So a filtered page costs about as long as reading the saved result. `--full` forces a fresh
analysis, and `--no-save-run` skips saving.

```
bouncer review --summary
bouncer review --format agent --rule force-unwrap --limit 20
bouncer review --format agent --rule force-unwrap --limit 20 --offset 20
bouncer check --files Sources/App/Login.swift --format agent
```

## The MCP server

`bouncer mcp` runs a Model Context Protocol server over stdin and stdout. It analyzes once, keeps
the result in memory (and in `.bouncer-cache/`, so a restarted server picks up where it left off),
and answers each question from it without analyzing again. It reads the same layered `.bouncer`,
profiles, and baseline as the command line.

Register it with Claude Code:

```
claude mcp add bouncer -- bouncer mcp
```

Or with any client that reads an `mcpServers` config:

```json
{ "mcpServers": { "bouncer": { "command": "bouncer", "args": ["mcp"] } } }
```

### Tools

| Tool | Arguments | Returns |
|---|---|---|
| `scan` | `path?`, `profile?`, `changed_since?`, `full?` | The summary, or "running" with a percentage if the scan takes longer. Starts from the saved last run unless `full` is set. |
| `status` | none | A running scan's progress, then its summary. |
| `findings` | `rule?`, `path?`, `severity?`, `group_by?`, `cursor?`, `max_tokens?`, `max_chars?` | One slice, as `--format agent` lines. |
| `verify` | `files`, `max_tokens?`, `max_chars?` | Re-analyzes only those files and returns what changed: fixed, still there, and new. |
| `check` | `max_tokens?`, `max_chars?` | The pre-commit check on the staged diff, change rules included. Returns only what would block the commit. |
| `explain_rule` | `id` | What a rule checks, its default severity and parameters, and how to configure or suppress it. |

Every response has a size cap. `max_tokens` is estimated as characters divided by 4 and defaults
to 2,000; `max_chars` is exact. Given both, the smaller wins. A response that doesn't fit ends
with a `cursor`; pass it back to `findings` for the rest.

### The fix loop

1. `scan` for the summary.
2. `findings` for one slice, such as one rule in one folder.
3. Edit the code.
4. `verify` the edited files, and repeat from 2.

Before committing, `check` shows exactly what the pre-commit hook would block. `explain_rule`
covers any rule the agent doesn't recognize. When the work runs out, the summary from `status` says
what's left.

### Hooks

The server never prompts, since stdin carries the protocol, and it never runs `preCheck` or
`postCheck` hooks, trusted or not: a hook's output would land on stdout and corrupt the protocol.
If a hook regenerates a coverage report, run it yourself, or use `bouncer review` for that run.
See <doc:Hooks>.

### Picking up edits

`agent.refresh` in `.bouncer` decides when the server notices files that changed while the agent
works:

- `next-scan` (the default): the result stays as it was until the next `scan`, or until `verify`
  re-checks the files it's given. Cheap and predictable on large repos.
- `immediate`: before every answer, the server re-checks any analyzed file that changed on disk,
  plus files that appeared or vanished. Always current, but slower on large repos.

```json
{ "agent": { "refresh": "immediate" } }
```

`bouncer configure` asks about it, and recommends `immediate` for repos under 5,000 files. `verify`
always re-reads its files, whichever you choose.
