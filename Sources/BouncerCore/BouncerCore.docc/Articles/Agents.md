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
| `next_batch` | `rule?`, `path?`, `max_tokens?`, `max_chars?` | The one file and rule to fix next, picked by the work order, with the code around each finding and the `verify` call to make after. |
| `verify` | `files`, `max_tokens?`, `max_chars?` | Re-analyzes only those files and returns what changed: fixed, still there, and new. |
| `check` | `max_tokens?`, `max_chars?` | The pre-commit check on the staged diff, change rules included. Returns only what would block the commit. |
| `explain_rule` | `id` | What a rule checks, its default severity and parameters, and how to configure or suppress it. |

Every response has a size cap. `max_tokens` is estimated as characters divided by 4 and defaults
to 2,000; `max_chars` is exact. Given both, the smaller wins. A response that doesn't fit ends
with a `cursor`; pass it back to `findings` for the rest.

### The fix loop

1. `scan`, then `status` until it returns the summary.
2. `next_batch` for the one file and rule to fix next: its findings, the code around each, and what to
   `verify` after.
3. Edit the code.
4. `verify` the edited file, and repeat from 2.

When the budget runs out, report what's left from the summary `status` returns. `findings` lists any other
slice, such as one rule in one folder. Before committing, `check` shows exactly what the pre-commit hook would
block, and `explain_rule` covers any rule the agent doesn't recognize.

### What next_batch picks

`next_batch` returns one cluster: one file's findings from one rule, so a fix needs one file read. The work
order (`agent.workOrder`) decides first: quick fixes first (the default) puts every mechanical fix before any
refactor, then errors before warnings; most severe first swaps the two. A cluster's severity is its most
severe finding, and a rule with no fix-cost tag, such as a custom rule, counts as mechanical. Ties go to
security rules (those mapped to an OWASP category), then files the agent verified this session (most recent
first) or that the scan's `changed_since` narrowed it to, then larger clusters, then path and rule.

```
Results from 2 s ago; verify re-checks files you edited.
Sources/App/Login.swift · force-unwrap (mechanical, warning) · 2 findings · 37 clusters left
  41 Force unwrap can crash at runtime.
    40|     let user = session.user
    41|     return user!.name
    42|   }
  88
    87|     let token = keychain.token
    88|     send(token!)
    89|   }
Next: fix these, then call verify with files ["Sources/App/Login.swift"]; then next_batch again.
```

Each finding shows the line above and below it, merged when windows touch. A refactor, such as a long
function, shows the enclosing declaration's line instead. A file that changed since the scan shows no code,
and its header says to verify it. A cluster that doesn't fit the budget ends with how many findings are left in
it and the `findings` call that lists them.

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

### Work order

Every rule carries a fix cost. `mechanical` means a local fix that doesn't change the code's
structure, such as `force-unwrap`, `trailing-whitespace`, `magic-number`, or
`missing-documentation`. `refactor` means the code has to be restructured, such as
`duplicate-block`, `long-function`, `god-class`, or `cyclomatic-complexity`. `explain_rule` shows a
rule's cost on its `Fix cost:` line.

`agent.workOrder` in `.bouncer` uses those costs to decide what the server recommends fixing first:

- `quick-fixes-first` (the default): every mechanical finding before any refactor; within each,
  errors before warnings before info. The agent clears the most findings fastest.
- `severity-first`: errors before warnings before info, whatever the effort; within each severity,
  mechanical before refactor. Slower, but the riskiest problems go first.

```json
{ "agent": { "workOrder": "severity-first" } }
```

`bouncer configure` asks about it right after `agent.refresh`.

## Teaching an agent the loop

An agent works best when it's told the loop up front. Two short files do that; both cost context in every
session, so they're kept brief.

### A Claude Code skill

Save this as `.claude/skills/bouncer/SKILL.md` in the repo (or in `~/.claude/skills/` for every repo):

```markdown
---
name: bouncer
description: Fix Bouncer code-quality findings. Use when asked to fix lint or code-quality issues, reduce Bouncer findings, or clean up a change before committing.
---

# Fixing Bouncer findings

With the bouncer MCP server:

1. `scan`, then `status` until it returns the summary.
2. `next_batch`: the one file and rule to fix next, with the code around each finding.
3. Fix those findings. `explain_rule` says how for a rule you don't know.
4. `verify` the file you edited, and fix anything it reports as new.
5. Repeat from 2. Before committing, run `check`. When you stop, report what's left from `status`.

Without MCP, the same loop in a shell:

- `bouncer review --summary`: totals, top rules and files.
- `bouncer review --format agent --rule RULE --path GLOB --limit 20`: one slice.
- `bouncer check --files FILE... --format agent`: re-check the files you edited.
- `bouncer review --changed-since main --summary`: only what your branch changed.
- `bouncer check --format agent`: what the pre-commit hook would block in the staged diff.

Never print a whole report: always pass `--summary`, or `--format agent` with `--limit`.
```

### An AGENTS.md snippet

For agents that read `AGENTS.md`, add:

```markdown
## Code quality: Bouncer

- MCP (`bouncer mcp`): `scan` → `next_batch` → fix → `verify` the file → repeat. `check` before
  committing; `explain_rule` for an unknown rule. When you stop, report what's left from `status`.
- Shell: `bouncer review --summary`; `bouncer review --format agent --rule RULE --path GLOB --limit 20`;
  after editing, `bouncer check --files FILE... --format agent`; on a branch,
  `bouncer review --changed-since main --summary`; before committing, `bouncer check --format agent`.
- Never print a whole report: pass `--summary`, or `--format agent` with `--limit`.
```
