# Bouncer

Bouncer is a configurable coding-standards and code-smell checker. It analyzes TypeScript (including TSX), JavaScript (including JSX), Swift, Objective-C, Rust, Python, and Go with real parse trees, and everything else (zsh, bash, PowerShell, C++, Java, SQL, C, and best-effort anything else) heuristically, all through the same dependency-injected rule engine. It runs as a Husky pre-commit hook, as an ad-hoc audit of any codebase, and as a self-check a coding agent can run after every edit.

Full documentation, including the config reference and rule catalog, is at [matthewa26.github.io/bouncer](https://matthewa26.github.io/bouncer/documentation/bouncercore/).

## Install

One installer for every platform. It picks the right build for your OS and CPU, verifies it against the release's `SHA256SUMS`, and installs it for the current user, no admin rights or Swift toolchain needed:

```sh
# macOS, Linux, and WSL (x86-64 or ARM64): installs to ~/.local/bin
curl -fsSL https://matthewa26.github.io/bouncer/install.ps1 | sh
```

```powershell
# Windows PowerShell or PowerShell 7: installs to %LOCALAPPDATA%\Programs\bouncer and adds it to your user PATH
irm https://matthewa26.github.io/bouncer/install.ps1 | iex
```

`install.ps1` is a single polyglot file that runs under both `sh` and PowerShell. Set `BOUNCER_VERSION` to pin a release, `BOUNCER_INSTALL_DIR` to change where it goes, or `BOUNCER_NO_MODIFY_PATH=1` to leave your Windows PATH alone.

The release builds behind it run without Swift installed: a universal macOS binary, fully static Linux binaries for x86-64 and ARM64 (any distro, WSL1 and WSL2), and a Windows x86-64 zip that bundles the Swift runtime (it also uses the Microsoft Visual C++ Redistributable, which most Windows machines already have; the installer warns if it's missing). There's no native Windows ARM64 build yet; the installer gives ARM64 Windows the x86-64 build, which runs under Windows' built-in emulation.

Other ways to install:

- **Build from source**: `swift build -c release` (needs a Swift 6 toolchain).
- **Prebuilt archive**: download the archive for your platform from [the site's download folder](https://matthewa26.github.io/bouncer/download/latest/SHA256SUMS) (the latest release) or a GitHub release, and check it against `SHA256SUMS`.
- **Homebrew**: `brew tap matthewa26/tap && brew install bouncer`. Works natively on macOS and Linux. On Windows, Homebrew only runs inside **WSL2** (a real Linux kernel) - it does not work under WSL1 or natively on Windows. For native Windows without WSL, use the installer above.

## Usage

```
bouncer check                          # analyze git-staged files, exit non-zero on violations
bouncer check --files a.swift b.py     # analyze exactly these files (agent post-edit self-check)
bouncer check --stdin                  # analyze a newline-delimited file list piped in
bouncer review .                       # recursively audit a directory, independent of git
bouncer review . --format json         # structured output for CI or an agent
bouncer review . --format table        # an aligned Markdown table, to read or paste anywhere
bouncer review . --format html         # a self-contained page with table and JSON views
bouncer review . --format agent        # compact findings grouped by file, for a coding agent's context
bouncer review . --summary             # only the totals, top rules, and top files (any format)
bouncer review . --rule force-unwrap --path 'Sources/**' --min-severity warning --limit 20 --offset 20
bouncer review . --group-by rule       # group agent or console output by rule instead of file
bouncer review . --progress plain      # one progress line per phase (auto: a live bar on a terminal)
bouncer review . --verbose             # log everything the run does to stderr
bouncer review . --changed-since main  # only files changed since a git ref, plus untracked files
bouncer review . --full                # analyze every file, not just those changed since the saved run
bouncer configure                      # guided setup: thresholds, coverage, where to save
bouncer profile create strict          # save a named profile, then pick it with --profile strict
bouncer profile set-default strict     # use a profile by default in this repo
bouncer configure --set coverage.threshold=90
bouncer configure --husky              # wire 'bouncer check' into .husky/pre-commit
bouncer baseline update                # accept every current finding, so only new ones are flagged
bouncer xcode install                  # add a Bouncer build phase to an Xcode project (macOS)
bouncer review . --format xcode        # compiler-style diagnostics that Xcode shows inline
```

### Xcode and Swift packages

`bouncer xcode install` adds a Run Script phase to your Xcode targets, and the [bouncer-plugin](https://github.com/matthewa26/bouncer-plugin) package runs Bouncer as a SwiftPM build-tool plugin. Either way, findings appear inline in Xcode and in `swift build` output.

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

Every built-in rule can be enabled, disabled, re-severitied, and parameterized this way. Project rules, which look across files (such as `import-cycle`), cache each file's imports in `.bouncer-cache/` at the repo root; add it to your `.gitignore`. `review` also saves its result there (`last-run.json`), so the next `review` analyzes only the files that changed since; `--full` forces a fresh run, and `"output": { "saveRun": false }` or `--no-save-run` turns saving off. `--profile kirby` applies a strict, opinionated preset as the base layer beneath your own config (see below).

Profiles are named presets in the same format. Keep your own in `~/.bouncer-profiles/<name>.json`, or share one with your team by committing it to `<repo>/.bouncer-profiles/<name>.json`. Select one with `--profile <name>` or `"profile": "<name>"` in `.bouncer`; `bouncer profile list` shows what's available and which is the default. Profiles can't declare hooks, which belong in `.bouncer` behind the trust prompt.

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

### Windows tests on a Mac

`Scripts/windows-vm/windows-vm.sh` runs the Windows tests locally, in a QEMU Windows 11 ARM64 VM on Apple Silicon (`brew install qemu wimlib`). Download the Windows 11 Arm64 ISO from Microsoft, then:

```sh
Scripts/windows-vm/windows-vm.sh create ~/Downloads/Windows11_*_arm64_*.iso   # once: hands-off install and provisioning, about 20 minutes
Scripts/windows-vm/windows-vm.sh test                                          # every run: build, test, package, and installer tests
```

`create` installs Windows unattended (accepting its license and creating a local `bouncer` account), then the VS Build Tools, Swift, Git, PowerShell 7, and OpenSSH. `test` boots a throwaway copy, copies in your working tree over SSH, and runs `swift build`, `swift test`, the release packaging script, and both installer tests under Windows PowerShell 5.1 and PowerShell 7. After editing the provisioning script, `reprovision` applies the change without reinstalling. VM state lives in `~/.cache/bouncer-windows-vm`.

## License

Copyright (C) 2026 Matthew Ayers.

Bouncer is free software: you can redistribute it and/or modify it under the terms of the
[GNU General Public License v3.0](LICENSE), or (at your option) any later version. The
vendored tree-sitter grammars under `Sources/CTreeSitter*` keep their own MIT licenses.
