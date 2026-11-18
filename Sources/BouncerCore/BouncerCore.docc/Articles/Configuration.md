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
(see ``OutputVerbosity``). It only affects human-readable console output; `--format json` always
returns the complete structured findings regardless of this setting, since machine consumers
want completeness.

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
its own; `exclude` is for anything else you want left alone, such as vendored code or generated
files.

### `profile`

Applies a bundled preset as the base layer beneath everything else in this file. `"kirby"` is
the only one that ships today. See <doc:KirbyMode>.

## Command-line overrides

Most settings can also be set per-invocation with a flag, which takes precedence over both
config layers for that one run: `--severity-threshold`, `--format`, `--verbosity`,
`--profile`, and (on `review`) `--coverage-report`/`--coverage-format`. Run `bouncer check --help`
or `bouncer review --help` for the complete flag list.
