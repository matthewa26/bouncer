# Getting Started

Install Bouncer, wire it into a pre-commit hook, and run your first check.

## Installing

The installer works on every platform. It picks the right build for your OS and CPU,
verifies it against the release's `SHA256SUMS`, and installs it for the current user:

```sh
# macOS, Linux, and WSL1/WSL2, on x86-64 or ARM64
curl -fsSL https://matthewa26.github.io/bouncer/install.ps1 | sh
```

```powershell
# Windows PowerShell or PowerShell 7
irm https://matthewa26.github.io/bouncer/install.ps1 | iex
```

`install.ps1` is one polyglot file that runs under both `sh` and PowerShell. Set
`BOUNCER_VERSION` to pin a release or `BOUNCER_INSTALL_DIR` to choose where it goes. The builds
it installs don't need Swift: a universal macOS binary, fully static Linux binaries, and a
Windows x86-64 zip with the Swift runtime included (ARM64 Windows runs it under emulation).

Other ways:

- **Homebrew**: `brew tap matthewa26/tap && brew install bouncer`. Works natively on macOS
  and Linux. On Windows, Homebrew only runs inside WSL2, since WSL2 runs a real Linux kernel.
  WSL1 is not supported.
- **Prebuilt archive**: download the archive for your platform from the latest GitHub release.
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

## Reports

`check` and `review` print their findings to the terminal by default. `--format` picks another
shape, and `--output <file>` writes it to a file instead of printing it:

- `console`, the default: one line per finding, for a terminal.
- `table`: an aligned Markdown table of severity, rule, location, and message, most severe first,
  ending with a summary line. It reads well in a terminal and pastes cleanly into an issue, a pull
  request, or an AI chat.
- `json`: the complete structured findings, for scripts, CI, and coding agents.
- `html`: one self-contained page with no external files, so it opens straight from disk. Its
  **Table** view filters by text and severity and sorts by any column; its **JSON** view shows the
  same data as `--format json`, with buttons to copy or download it.

```sh
bouncer review . --format html                       # writes .bouncer-cache/report.html
bouncer review . --format json --output report.json  # for another tool to read
bouncer check --format table                         # staged changes, as a table
```

When a report goes to a file, Bouncer prints the summary, the file's path, and a `file://` link
to open it. Under WSL, where a Linux path or a `localhost` address doesn't reach the file from a
Windows browser or tool, it also prints the Windows address: `file://wsl.localhost/<distro>/…`
(and `\\wsl.localhost\<distro>\…`) for files in the Linux filesystem, or the drive path, such as
`C:\Users\…`, for files under `/mnt/c`. `.bouncer-cache/` is git-ignored, so the default HTML
report never gets committed.

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
