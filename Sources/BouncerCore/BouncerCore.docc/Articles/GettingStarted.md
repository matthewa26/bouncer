# Getting Started

Install Bouncer, wire it into a pre-commit hook, and run your first check.

## Installing

Three ways, on any platform:

- **Homebrew**: `brew tap matthewayers/tap && brew install bouncer`. Works natively on macOS
  and Linux. On Windows, Homebrew only runs inside WSL2, since WSL2 runs a real Linux kernel.
  WSL1 is not supported.
- **Prebuilt binary**: download the archive for your platform from the latest GitHub release.
- **Build from source**: `swift build -c release`, using a Swift 6 toolchain.

## Your first check

Run `bouncer` from inside a git repository, with no arguments, to analyze whatever's staged:

```sh
bouncer check
```

Nothing staged yet, or want to check a file you just edited without touching git's index? Pass
it directly:

```sh
bouncer check --files path/to/file.swift
```

To audit an entire directory, independent of git state, use `review` instead:

```sh
bouncer review .
bouncer review . --format json
```

`--format json` is worth knowing about even outside of CI: it's the structured output a coding
agent should ask for when it wants findings it can act on, rather than parsing console text.

## Wiring up Husky

Bouncer has no Node or npm dependency of its own. The entire Husky integration is one line in
`.husky/pre-commit`:

```sh
#!/usr/bin/env sh
bouncer check
```

A non-zero exit blocks the commit. Run `bouncer configure --husky` to add this line for you
(it expects `.husky/` to already exist; if it doesn't, run `npx husky init` first).

## Configuring

`bouncer configure` walks you through the most common settings interactively, or you can set
values directly:

```sh
bouncer configure --set coverage.threshold=90
bouncer configure --set output.verbosity=condensed
```

See <doc:Configuration> for the full `.bouncer` file format, and <doc:RuleCatalog> for every
built-in rule and its parameters.

## Adopting Bouncer on an existing codebase

Running Bouncer on a codebase that's never used it before will likely surface a lot of
pre-existing findings at once. Accept all of them as a starting baseline, so only genuinely new
issues get flagged from that point on:

```sh
bouncer baseline update
```
