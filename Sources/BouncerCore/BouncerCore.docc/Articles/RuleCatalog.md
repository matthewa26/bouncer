# Rule Catalog

Every built-in rule, what it checks, its default severity, and its parameters.

## Where each rule runs

Swift, TypeScript (`.ts`, `.mts`, `.cts`, and `.tsx` via the TSX grammar), JavaScript
(`.js`, `.mjs`, `.cjs`, `.jsx`), Python, and Go get most of these rules computed exactly from
a real parse tree. Every other supported language (zsh, bash, PowerShell, C++, Java, SQL, C,
and anything unrecognized) gets the same checks computed heuristically instead, from
indentation and regular expressions rather than a real grammar. The rule IDs, defaults, and
config keys are identical either way; only the precision of the check differs. `missing-documentation`'s
`scope` parameter is the one exception worth calling out: heuristic languages can't reliably
determine a declaration's access level, so the heuristic version always behaves as `scope: all`,
regardless of what's configured.

## Code smells

These eight run on every language.

| Rule ID | Checks | Default severity | Parameters |
|---|---|---|---|
| `file-length` | A file's logical line count (blank and comment-only lines excluded) | warning | `maxLines` (500) |
| `long-function` | A function's logical line count | warning | `maxLines` (40) |
| `deep-nesting` | A line's indentation depth | warning | `maxDepth` (16), `indentWidth` (4) |
| `long-lines` | A line's character count | warning | `maxLength` (120) |
| `todo-density` | TODO/FIXME/HACK marker density across a file | warning | `maxPerHundredLines` (5) |
| `duplicate-block` | A repeated block of lines within the same file | warning | `windowSize` (6) |
| `trailing-whitespace` | A line ending in a space or tab | warning | none |
| `secret-looking-pattern` | A line matching a small set of credential-shaped patterns | warning | none |

`secret-looking-pattern` is a narrow check for obvious mistakes, not a secrets-scanner
replacement; use a dedicated tool such as gitleaks or trufflehog for real secret-scanning
coverage. `duplicate-block` is intra-file only and requires an exact match; it's a deliberately
cheap approximation of clone detection, not a real one.

## Code quality

These five come from the design-pattern and code-quality catalog taught in OSU CSE 3902.

| Rule ID | Checks | Default severity | Parameters |
|---|---|---|---|
| `cyclomatic-complexity` | A function's branch count (an approximation of McCabe complexity) | warning | `max` (10) |
| `naming-convention` | A declaration's name against its language's expected pattern | warning | none (patterns are built in per language) |
| `high-coupling` | A file's import/using/require count, as a coupling proxy | warning | `maxImports` (15) |
| `switch-on-type-smell` | A switch/match statement's branch count | warning | `maxBranches` (6) |
| `missing-documentation` | Whether a declaration has a doc comment | warning | `scope` (`public`), see below |
| `god-class` (Swift, TypeScript, JavaScript, Python) | A type's member count combined with its file's import count | warning | `maxMembers` (20), `maxImportsForGodClass` (10) |

`god-class` only applies where the language has classes with a real member list Bouncer can
count; Go, for instance, has no equivalent. `high-coupling` counts import statements as a
coupling proxy, not an actual dependency graph; a real cross-file coupling metric is out of
scope for a rule engine that only ever looks at one file at a time.

### `missing-documentation`'s `scope` parameter

Three values: `"public"` (the default), `"internal"`, or `"all"`. On Swift, TypeScript,
JavaScript, Python, and Go, this is checked against the declaration's real access level:
Swift's `public`/`open` versus `internal` versus `private`/`fileprivate`; TypeScript and
JavaScript's `export` (an exported function, or any class member, is public; an unexported
top-level function or `protected` member is internal; a `private` or `#name` member is
private); Python's leading-underscore convention (no underscore is public, one is internal,
two is private); Go's exported-by-capitalization convention (uppercase first letter is
public, lowercase is internal, since Go has no true private).

TypeScript and JavaScript count only a `/** */` JSDoc comment as documentation, directly above
the declaration or the `export`/`const` that wraps it. Anonymous inline callbacks are never
flagged, since there's nothing to name in a doc comment; they still count toward
`long-function` and `cyclomatic-complexity`. Functions exported through a separate
`export { name }` list are treated as internal. Every other language always behaves as `scope: all`, since a heuristic pass over the
text can't determine access level reliably enough to filter on it.

## Per-language extras

A handful of languages get one or two additional pattern-based checks for a specific, common
mistake in that language, layered on top of the shared rules above:

| Language | Rule ID | Checks |
|---|---|---|
| bash/zsh | `shell-unquoted-variable` | An unquoted `$variable` expansion |
| bash/zsh | `shell-eval-usage` | `eval` usage |
| Python | `python-bare-except` | A bare `except:` clause |
| Python | `python-mutable-default-arg` | A mutable (`[]`/`{}`) default argument |
| TypeScript/JavaScript | `js-console-log` | `console.log`/`debugger` left in |
| TypeScript/JavaScript | `js-loose-equality` | `==`/`!=` instead of `===`/`!==` |
| PowerShell | `powershell-invoke-expression` | `Invoke-Expression`/`iex` usage |
| PowerShell | `powershell-plaintext-password` | `-AsPlainText` password conversion |
| C++ | `cpp-raw-new-delete` | Raw `new`/`delete` instead of a smart pointer |
| C++ | `cpp-using-namespace-std` | File-scope `using namespace std;` |
| Java | `java-generic-exception-catch` | Catching `Exception`/`Throwable` broadly |
| Java | `java-print-stack-trace` | `.printStackTrace()` instead of a logger |
| Go | `go-discarded-return-value` | A return value discarded with `_ =` |
| Go | `go-panic-usage` | `panic()` usage |
| SQL | `sql-select-star` | `SELECT *` instead of named columns |
| SQL | `sql-missing-where` | `UPDATE`/`DELETE` with no `WHERE` clause |

These are all declarative pattern rules, the same mechanism `customRules` in your own
`.bouncer` file uses; see <doc:Configuration>. Adding one for a language that doesn't have it
yet is a data change, not new code.

## Coverage

A below-threshold coverage result becomes a finding with rule ID `coverage-threshold`, so it
respects the same baseline and severity-threshold rules as everything else. See
<doc:Configuration> for how to configure the report path and threshold.
