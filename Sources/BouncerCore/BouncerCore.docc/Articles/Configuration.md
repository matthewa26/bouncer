# Configuration

The `.bouncer` file format, how global and per-repo settings combine, and every top-level
section.

## Where settings live

Settings live in a plain JSON `.bouncer` file, in two possible locations:

- `~/.bouncer` for global defaults that apply everywhere.
- `<repo>/.bouncer` for settings specific to one repository.

When both exist, the repo's settings win over the global ones, field by field. If the repo
doesn't set a particular field, the global value (or the built-in default) still applies. The
one exception is `hooks`, which is additive rather than override-by-more-specific: a hook
declared globally and a hook declared in the repo both run.

## A complete example

```json
{
  "output": { "verbosity": "normal" },
  "coverage": {
    "enabled": true,
    "format": "auto",
    "reportPath": "coverage/lcov.info",
    "threshold": 80
  },
  "rules": {
    "long-function": { "severity": "warning", "params": { "maxLines": 40 } },
    "missing-documentation": { "params": { "scope": "public" } }
  },
  "customRules": [
    {
      "id": "no-print-statements",
      "type": "pattern",
      "pattern": "\\bprint\\(",
      "message": "Use a logger instead of print.",
      "severity": "warning"
    }
  ],
  "hooks": {
    "preCheck": ["swift test --enable-code-coverage"]
  },
  "exclude": ["Tests/**", "*.md"]
}
```

## Sections

### `output`

Controls console rendering. `verbosity` is one of `verbose`, `normal`, `quiet`, or `condensed`
(see ``OutputVerbosity``). It affects console output; `--format table` uses only `condensed`
(the summary line alone), and `--format json` and `--format html` always hold the complete
findings regardless of this setting, since machine consumers want completeness.

### `coverage`

Bouncer never runs your test suite. It only parses a coverage report that already exists on
disk. `format` is `"lcov"`, `"xccov"`, or `"auto"` (sniffed from the report path); LCOV works on
every platform, while `.xcresult`/xccov is macOS-only. `threshold` is the minimum acceptable
line coverage percentage. A below-threshold result becomes an ordinary finding with rule ID
`coverage-threshold`, so it flows through baseline filtering and severity thresholds like
everything else.

### `rules`

Every built-in rule can be enabled, disabled, re-severitied, and parameterized here, keyed by
its rule ID. See <doc:RuleCatalog> for the full list of IDs and their parameters.

### `customRules`

Declares your own pattern-based checks without writing Swift. Each entry needs an `id`, a
`type` (only `"pattern"` is supported currently), a `pattern` (a regular expression), and a
`message`. `severity` defaults to `warning`.

### `hooks`

Shell commands to run around a check. The motivating case is regenerating a coverage report
right before Bouncer reads it, so `coverage.threshold` is never evaluated against stale data.
See <doc:Hooks> for the full trust model, since a repo-committed `.bouncer` declaring hooks is
a real trust boundary and Bouncer gates it accordingly.

### `exclude`

Glob patterns, relative to the repo root, excluded from every check. Bouncer already skips a
handful of conventionally-noisy directories (`.git`, `node_modules`, `.build`, and similar) on
its own, and license and notice files anywhere in the tree: `LICENSE`, `LICENCE`, `COPYING`,
`NOTICE`, and `UNLICENSE`, in any case, alone or with an extension or suffix (`LICENSE.md`,
`COPYING.txt`, `LICENSE-MIT`), since they're legal text rather than code. `exclude` is for
anything else you want left alone, such as vendored code or generated files.

### `project`

```json
{ "project": { "inCheck": false } }
```

Project rules look across files rather than within one, such as `import-cycle` (see
<doc:RuleCatalog>). `bouncer review` always runs them, indexing the directory it reviews.
`bouncer check` skips them by default to keep pre-commit hooks fast; set `inCheck` to `true` to
have `check` index the whole repo (honoring `exclude`) and report project findings in the staged
files, such as a new import cycle that passes through one.

Each file's imports and exports are cached in `.bouncer-cache/facts.json` at the repo root,
keyed by the file's content, so unchanged files aren't re-parsed. Add `.bouncer-cache/` to your
`.gitignore`; deleting it is always safe.

### `profile`

Applies a bundled preset as the base layer beneath everything else in this file. `"kirby"` is
the only one that ships today. See <doc:KirbyMode>.

## Suppressing findings in code

A `.bouncer` file turns a rule off everywhere. To silence one rule in one place instead, put a
`bouncer:` comment in the file. It works in any comment style (`//`, `#`, `--`, `/* */`,
`<!-- -->`, `;`), so the same syntax covers every language Bouncer reads:

```swift
protocol ImportResolver { // bouncer:disable-line parallel-inheritance -- one per language, by design

// bouncer:disable-next-line magic-number
let retries = 7

// bouncer:disable long-function, cyclomatic-complexity
func generatedParser() { … }
// bouncer:enable long-function, cyclomatic-complexity
```

```python
# bouncer:disable-file duplicate-code -- generated from the schema
```

- `bouncer:disable-line <rules>` covers the line the comment is on.
- `bouncer:disable-next-line <rules>` covers the next line that isn't blank or another directive,
  so several can be stacked above one line.
- `bouncer:disable <rules>` covers every line until a `bouncer:enable` that names the rule, or
  the end of the file. Each rule is re-enabled separately.
- `bouncer:disable-file <rules>` covers the whole file.

List rules by ID, separated by commas or spaces; there's no blanket "disable everything", so
every suppression says what it silences. Anything after ` -- ` is a free-text reason, ignored by
Bouncer but useful to the next reader. Suppressions apply to every kind of finding, per-file,
project, and change rules alike, as long as it lands in the file holding the comment; a project
finding reported in another file is suppressed there. A suppressed finding never reaches the
baseline, so `baseline update` doesn't record it.

## Command-line overrides

Most settings can also be set per-invocation with a flag, which takes precedence over both
config layers for that one run: `--severity-threshold`, `--format` (`console`, `table`, `json`, or
`html`; see <doc:GettingStarted>), `--output`, `--verbosity`,
`--profile`, and (on `review`) `--coverage-report`/`--coverage-format`. Run `bouncer check --help`
or `bouncer review --help` for the complete flag list.
