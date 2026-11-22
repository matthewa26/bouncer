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

On a large repo, `--changed-since` narrows a review to what a branch or session touched: files that
differ from a git ref (committed since, staged, or unstaged) plus untracked files git doesn't ignore,
under the reviewed directory and minus the usual excludes. Project rules such as `unused-export` still
index every file, so they see the whole module graph, but only report findings in the changed files.

```sh
bouncer review . --changed-since main
bouncer review Sources --changed-since HEAD~3
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
  **Table** view loads 100 rows at a time as you scroll, so it stays fast with millions of findings.
  It filters by text and severity, sorts by any column, and has a **Rules** panel to hide noisy rules
  (remembered per repository) and copy them as `.bouncer` settings that switch them off. Its **JSON**
  view previews the first findings, with buttons to copy or download the same data as `--format json`.
- `agent`: findings in as few tokens as possible, for a coding agent. See below.

```sh
bouncer review . --format html                       # writes .bouncer-cache/report.html
bouncer review . --format json --output report.json  # for another tool to read
bouncer check --format table                         # staged changes, as a table
```

When a report goes to a file, Bouncer prints the summary, the file's path, and an `Open:` link.
Under WSL, where a Linux path or a `localhost` address doesn't reach the file from a Windows
browser, the `Open:` link is the Windows address, so clicking it in Windows Terminal works:
`file://wsl.localhost/<distro>/…` for files in the Linux filesystem, or `file:///C:/…` for files
under `/mnt/c`. A `Windows path:` line gives the same location for Explorer. `.bouncer-cache/` is git-ignored, so the default HTML
report never gets committed.

### Using Bouncer from an agent

`--format agent` lists each file once, with paths relative to the repository root, and one
`LINE RULE MESSAGE` line per finding under it. A message that repeats the last one for its rule is left
out, and a footer says how many findings are shown out of how many, and which `--offset` gets the next
page. `--group-by rule` lists a header per rule instead, with `PATH:LINE MESSAGE` lines.

Filters and paging work with every format, after the baseline and suppressions apply:

- `--rule ID` and `--path GLOB` (relative to the repository root, such as `'Sources/**'`), both
  repeatable, and `--min-severity info|warning|error`.
- `--limit N` and `--offset N`, over findings sorted by file, line, and rule.
- `--summary`, to print only the summary: totals by severity, top rules and files, and the time. In
  JSON it's an object with no `findings`.

The exit code still follows `--severity-threshold`, over every finding the filters keep, not just the
page shown. When one rule has more than half of all findings, the summary names it, so you can disable
or baseline it and look at the rest.

```sh
bouncer review . --summary
bouncer review . --format agent --rule force-unwrap --limit 20
bouncer check --files Sources/App.swift --format agent
```

## Watching a run

On a terminal, `check` and `review` draw a live progress line on standard error: a bar, the
current phase and file, and the elapsed time. Piped or in CI, they print one line per phase
instead, with a heartbeat during long phases, so a stalled run is easy to spot. When an agent
runs Bouncer (`--files`, `--stdin`, or `review --format json`), progress is off. Choose
explicitly with `--progress live|plain|off`.

`--verbose` (`-v`) logs everything a run does: which config files were found, every file with
its analyzer, finding count and time, each phase's timing, cache use, and hooks. Standard output
is never affected, so reports stay clean for scripts.

After the report, a short summary on standard error lists the totals, the five rules and files
with the most findings, and how long the run took.

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

`bouncer configure` walks you through setup: start from the defaults or a profile, then choose
verbosity, coverage, the thresholds people most often disagree on (function length, line length,
file length, complexity, parameters, nesting, magic numbers, doc comments), and where to save:
this repo, your global settings, or a named profile (see <doc:Profiles>). You can also set
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
