# Kirby Mode

A bundled, strict preset for holding your own code to the same bar Bouncer holds itself to.

## Overview

`--profile kirby` (or `"profile": "kirby"` in `.bouncer`) applies a bundled preset named for
Professor Neil Kirby of OSU CSE 3902, formerly of Bell Labs. His teaching on simplicity, low
coupling and high cohesion, small focused functions, and eliminating code smells shaped the
rule catalog Bouncer is built around, and shaped how this tool's own source is written.

A profile applies as the base layer underneath everything else in your config, in the same
layering order as global and repo settings: built-in defaults, then the selected profile, then
`~/.bouncer`, then the repo's `.bouncer`, then command-line flags. Anything you set explicitly
at a higher layer still wins. Selecting a profile is just "start from these stricter defaults,"
not a lock.

## What it sets

- `long-function`'s `maxLines` to 10, the same limit Bouncer's own source is held to.
- `cyclomatic-complexity`'s `max` to a single digit.
- `naming-convention` enforced at `error` rather than `warning`.
- `missing-documentation`'s `scope` to `"all"`, so private and internal declarations need doc
  comments too, not just public ones.
- `high-coupling` and `god-class` at tighter thresholds than the defaults.
- `switch-on-type-smell` at a lower branch-count threshold, since a long type-switch is one of
  the clearest signals that a Strategy or State pattern is missing.
- `long-parameter-list` to 3 parameters, `too-many-returns` to 3 returns,
  `cognitive-complexity` to 8, and `nesting-depth` to 3 levels, all at `error`.
- Every single-location smell (`force-unwrap`, `force-try`, `force-cast`,
  `implicitly-unwrapped-optional`, `non-null-assertion`, `explicit-any`, `nested-ternary`,
  `empty-catch`, `unreachable-code`, `magic-number`) at `error` rather than `warning`.
- `coverage.threshold` raised above the generic default.

These numbers are Bouncer's own calibration of that teaching, not published thresholds; the
source material (see <doc:RuleCatalog>) doesn't specify exact figures. Override anything that
doesn't fit your project the normal way, in your own `.bouncer`.

## Trying it

```sh
bouncer review . --profile kirby
```

Running this against an established codebase for the first time will likely surface a lot at
once. Consider `bouncer baseline update` first, so only new violations are flagged going
forward. See <doc:GettingStarted>.
