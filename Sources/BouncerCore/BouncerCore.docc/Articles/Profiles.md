# Profiles

Named presets you can keep for yourself, share with a team, and pick per run or per repository.

## Overview

A profile is a set of settings in the same JSON format as `.bouncer`, applied as the base layer
underneath your global and repo settings. Anything those files set explicitly still wins. Bouncer
ships one profile, `kirby` (see <doc:KirbyMode>), and you can add your own.

## Where profiles live

- `<repo>/.bouncer-profiles/<name>.json`: a repo profile. Commit it to share it with everyone who
  works on the repository.
- `~/.bouncer-profiles/<name>.json`: a global profile, available in every repository you work in.

When the same name exists in more than one place, the repo profile wins, then the global one,
then the bundled one. A profile name may use letters, digits, `.`, `_`, and `-`.

## Choosing a profile

In order of precedence:

1. `--profile <name>` on `check` or `review`, for one run.
2. `"profile": "<name>"` in the repo's `.bouncer`.
3. `"profile": "<name>"` in `~/.bouncer`.

An unknown name is an error that lists every place Bouncer looked, rather than silently running
without a profile.

## Managing profiles

```sh
bouncer profile list                      # every profile, where it lives; * marks the default
bouncer profile show strict               # print a profile as JSON
bouncer profile create strict             # build one with the setup wizard (a repo profile)
bouncer profile create mine --global      # ...or a global one
bouncer profile set-default strict        # select it in this repo's .bouncer
bouncer profile set-default mine --global # select it in ~/.bouncer
bouncer profile delete strict             # asks first; --yes skips the question
```

`bouncer configure` can also save its answers as a named profile, and offers to make it the
default. A profile is self-contained: it can't select another profile, so a profile started from
`kirby` holds a copy of Kirby's settings plus your changes.

## Profiles and hooks

A profile can't declare `hooks`. Hooks run shell commands, so they belong in `.bouncer`, where a
repository's hooks need your trust before they run (see <doc:Hooks>). A profile containing hooks
is rejected with an error.
