# Hooks

Running shell commands before and after a check, and the trust model that guards them.

## Why hooks exist

Bouncer never runs your test suite itself; the coverage-threshold check only ever parses a
report that already exists on disk (see <doc:Configuration>). Hooks are the bridge: a
`preCheck` hook can regenerate that report immediately before Bouncer reads it, so the
threshold check is never evaluated against stale data. That matters most for agentic
workflows, where a coding agent wants fresh, trustworthy signal on every single invocation
rather than a coverage number from an hour ago.

## Declaring hooks

```json
{
  "hooks": {
    "preCheck": ["swift test --enable-code-coverage"],
    "postCheck": ["echo 'bouncer run complete' >> .bouncer.log"]
  }
}
```

`preCheck` commands run first, in order, with their output streamed to your own stdout and
stderr. If any of them exits non-zero, the entire run aborts with exit code 2, before any file
is analyzed: if regenerating coverage fails, Bouncer refuses to evaluate a stale or missing
report rather than silently passing. `postCheck` commands run after the report is printed; a
failure there is logged as a warning but doesn't change the run's exit code, since the analysis
result is already final by that point.

Hooks are the one section of `.bouncer` that merges additively rather than override-by-more-specific:
a hook declared in `~/.bouncer` and a hook declared in the repo's own `.bouncer` both run, global
ones first. Every other section in the file follows the usual override rule described in
<doc:Configuration>.

## The trust boundary

A repo-committed `.bouncer` can declare arbitrary shell commands. Left unchecked, that would
mean cloning a repo and running `bouncer check` could execute anything its author put in that
file, the moment you (or an agent acting on your behalf) ran the command. Bouncer gates this
the same way `direnv` gates a repo's `.envrc`:

- The first time a repo-level `.bouncer` with a non-empty `hooks` section is encountered,
  Bouncer refuses to run those hooks. In an interactive terminal, it prints what they are and
  asks you to confirm; anywhere else (CI, a script, a coding agent), it silently skips them and
  continues without blocking on input, since there's no one there to answer a prompt.
- `bouncer configure --trust` records a hash of the current `hooks` section as trusted, for
  that repo. Editing the hooks afterward changes the hash and re-triggers the prompt, exactly
  like `direnv allow`.
- `--allow-hooks` bypasses the prompt for a single invocation, for CI where the pipeline
  configuration itself is the trust boundary.
- Hooks declared in your own `~/.bouncer` are always trusted. They're a file on your own
  machine, not something a cloned repo can plant.
