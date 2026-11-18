# Bouncer

Bouncer is a configurable coding-standards and code-smell checker. It analyzes TypeScript (including TSX), JavaScript (including JSX), Swift, Python, and Go with real parse trees, and everything else (zsh, bash, PowerShell, C++, Java, SQL, C, and best-effort anything else) heuristically, all through the same dependency-injected rule engine. It runs as a Husky pre-commit hook, as an ad-hoc audit of any codebase, and as a self-check a coding agent can run after every edit.

Full documentation, including the config reference and rule catalog, is at [matthewayers.github.io/bouncer](https://matthewayers.github.io/bouncer/).

## Install

Three ways, on any platform:

- **Build from source**: `swift build -c release` (needs a Swift 6 toolchain).
- **Prebuilt binary**: download the archive for your platform from the latest GitHub release.
- **Homebrew**: `brew tap matthewayers/tap && brew install bouncer`. Works natively on macOS and Linux. On Windows, Homebrew only runs inside **WSL2** (a real Linux kernel) - it does not work under WSL1 or natively on Windows. For native Windows without WSL, use the prebuilt binary instead.

## Usage

```
bouncer check                          # analyze git-staged files, exit non-zero on violations
bouncer check --files a.swift b.py     # analyze exactly these files (agent post-edit self-check)
bouncer check --stdin                  # analyze a newline-delimited file list piped in
bouncer review .                       # recursively audit a directory, independent of git
bouncer review . --format json         # structured output for CI or an agent
bouncer configure                      # create or edit .bouncer interactively
bouncer configure --set coverage.threshold=90
bouncer configure --husky              # wire 'bouncer check' into .husky/pre-commit
bouncer baseline update                # accept every current finding, so only new ones are flagged
```

### Husky integration

Bouncer has no Node/npm dependency. The entire integration is one line in `.husky/pre-commit`:

```sh
#!/usr/bin/env sh
bouncer check
```

A non-zero exit blocks the commit. `bouncer configure --husky` adds this line for you.

### Configuration

Settings live in a JSON `.bouncer` file: `~/.bouncer` for global defaults, `<repo>/.bouncer` for per-repo overrides. Repo settings win over global ones field-by-field; `hooks` is the one section that's additive instead - a global hook and a repo hook both run.

```json
{
  "output": { "verbosity": "normal" },
  "coverage": { "enabled": true, "format": "auto", "reportPath": "coverage/lcov.info", "threshold": 80 },
  "rules": {
    "long-function": { "severity": "warning", "params": { "maxLines": 40 } },
    "missing-documentation": { "params": { "scope": "public" } }
  },
  "customRules": [
    { "id": "no-print-statements", "type": "pattern", "pattern": "\\bprint\\(", "message": "Use a logger instead of print.", "severity": "warning" }
  ],
  "hooks": {
    "preCheck": ["swift test --enable-code-coverage"]
  }
}
```

Every built-in rule can be enabled, disabled, re-severitied, and parameterized this way. `--profile kirby` applies a strict, opinionated preset as the base layer beneath your own config (see below).

### Kirby mode

`--profile kirby` (or `"profile": "kirby"` in `.bouncer`) applies a bundled, strict preset named for Professor Neil Kirby (OSU CSE 3902, formerly Bell Labs), whose teaching on simplicity, low coupling and high cohesion, small focused functions, and eliminating code smells shaped this rule catalog. It holds your code to the same 10-line-function, fully-documented standard Bouncer holds its own codebase to. Anything you set explicitly in your own `.bouncer` still overrides it.

### Hooks and trust

A repo's `.bouncer` can declare `hooks.preCheck`/`hooks.postCheck` shell commands, most commonly to regenerate a coverage report right before Bouncer reads it. Because a repo-committed `.bouncer` could otherwise auto-execute arbitrary commands the moment you clone and run Bouncer, repo-declared hooks are gated behind trust the same way direnv gates `.envrc`: the first run prompts, `bouncer configure --trust` records a hash of the current hooks, and any edit to them re-prompts. `--allow-hooks` bypasses the prompt for a single CI run. Hooks declared in your own `~/.bouncer` are always trusted.

### Baseline

`bouncer baseline update` snapshots every current finding as accepted, so adopting Bouncer on an existing codebase only ever flags *new* violations from that point on. `bouncer baseline clear` resets it.

## Coverage

Bouncer never runs your tests - it only parses a report that already exists. LCOV works everywhere; Xcode's `.xcresult`/`xccov` format is macOS-only.

## Building this project

Every function in this repository is capped at 10 lines of logical code and carries a doc comment, enforced by Bouncer against its own source (`.bouncer` at the repo root).

The documentation site (this README's usage guide plus the full config reference, rule catalog, and API reference) is generated with DocC from `Sources/BouncerCore/BouncerCore.docc`:

```sh
swift package generate-documentation --target BouncerCore --output-path docs
```

It deploys automatically to GitHub Pages on every push to `main` (see `.github/workflows/docs.yml`).
