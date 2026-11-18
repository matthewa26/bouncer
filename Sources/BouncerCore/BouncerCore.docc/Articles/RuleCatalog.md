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

These six come from the design-pattern and code-quality catalog taught in OSU CSE 3902.

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

## Function shape and single-location smells

These run on every parsed language: Swift, TypeScript (including TSX), JavaScript (including
JSX), Python, and Go, wherever the language has the construct. Go has no classes, ternaries, or
`catch`, so `lack-of-cohesion`, `nested-ternary`, and `empty-catch` don't apply to it; in Python,
an `except` that only `pass`es counts as empty, and methods take `self`, which isn't counted as a
parameter. The heuristic languages don't get these rules.

| Rule ID | Checks | Default severity | Parameters |
|---|---|---|---|
| `long-parameter-list` | A function's declared parameter count | warning | `maxParameters` (5) |
| `boolean-parameter` | Boolean flag parameters (typed `Bool`/`boolean`, or defaulting to `true`/`false`); initializers are exempt | warning | `maxBooleanParameters` (0) |
| `lack-of-cohesion` | LCOM4: how many unrelated groups a type's methods split into | warning | `maxGroups` (2) |
| `too-many-returns` | A function's `return` count, excluding nested functions and closures | warning | `maxReturns` (4) |
| `cognitive-complexity` | SonarSource-style cognitive complexity, which penalizes nesting | warning | `max` (15) |
| `nesting-depth` | How deeply `if`/loop/`switch`/`catch` structures nest in a function | warning | `maxDepth` (4) |
| `nested-ternary` | A ternary inside another ternary | warning | none |
| `empty-catch` | A `catch` with no statements and no explanatory comment | warning | none |
| `unreachable-code` | The first statement after `return`/`throw`/`break`/`continue` in a block | warning | none |
| `magic-number` | A numeric literal other than 0, 1, or 2 that nothing names | warning | none |
| `force-unwrap` (Swift) | A force unwrap, `x!` | warning | none |
| `force-try` (Swift) | `try!` | warning | none |
| `force-cast` (Swift) | `as!` | warning | none |
| `implicitly-unwrapped-optional` (Swift) | An implicitly unwrapped optional type, `T!` | warning | none |
| `non-null-assertion` (TypeScript) | A non-null assertion, `x!` | warning | none |
| `explicit-any` (TypeScript) | An explicit `any` type | warning | none |

`cognitive-complexity` follows SonarSource's scheme: each `if`, loop, `switch`, `catch`, and
ternary adds one plus its nesting level; `else` and `else if` add one; each run of mixed
`&&`/`||`/`??` adds one; and closures and nested functions deepen nesting without scoring.
Recursion and labeled jumps aren't counted.

`magic-number` treats a number as named, and doesn't flag it, when it's the value of a
`let`/`var`/`const` (including arithmetic, as in `let secondsPerHour = 60 * 60`), a default
argument, an enum raw value, an object property or dictionary entry, a Swift labeled argument
such as `timeout: 30`, or a `case` label. A number passed straight into an unlabeled call, such
as `setTimeout(run, 3000)`, is flagged.

`lack-of-cohesion` connects two methods when they use a common field or method, or one calls
the other, counting both `self.x`/`this.x` and Swift's implicit-`self` references. Initializers
and `static` methods are left out. A value of 1 means every method is connected; 2 or more means
the type holds that many independent responsibilities that could be split apart.

`empty-catch` accepts a comment inside the braces as a deliberate "nothing to do here".

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
| Python | `python-debug-print` | A `print(...)` statement |
| TypeScript/JavaScript | `js-console-log` | `console.log`/`debugger` left in |
| TypeScript/JavaScript | `js-loose-equality` | `==`/`!=` instead of `===`/`!==` |
| TypeScript/JavaScript | `ts-ignore-without-reason` | `@ts-ignore`/`@ts-nocheck`/`@ts-expect-error` with no explanation |
| TypeScript/JavaScript | `ts-double-cast` | `as unknown as T` |
| TypeScript/JavaScript | `js-var` | `var` instead of `let`/`const` |
| TypeScript/JavaScript | `js-eval` | `eval(...)` or `new Function(...)` |
| TypeScript/JavaScript | `js-raw-html` | `innerHTML`/`outerHTML` assignment, `insertAdjacentHTML`, `dangerouslySetInnerHTML` |
| Swift | `swift-fatal-error` | `fatalError(...)` |
| Swift | `swift-unchecked-sendable` | `@unchecked Sendable` or `nonisolated(unsafe)` |
| Swift | `swift-debug-print` | A `print`/`debugPrint`/`dump`/`NSLog` statement |
| Swift | `swift-discarded-try` | A `try?` whose result is thrown away |
| C | `c-gets-usage` | `gets(...)`, which can't bound its input |
| C | `c-unsafe-string-function` | `strcpy`/`strcat`/`sprintf` |
| PowerShell | `powershell-invoke-expression` | `Invoke-Expression`/`iex` usage |
| PowerShell | `powershell-plaintext-password` | `-AsPlainText` password conversion |
| C++ | `cpp-raw-new-delete` | Raw `new`/`delete` instead of a smart pointer |
| C++ | `cpp-using-namespace-std` | File-scope `using namespace std;` |
| Java | `java-generic-exception-catch` | Catching `Exception`/`Throwable` broadly |
| Java | `java-print-stack-trace` | `.printStackTrace()` instead of a logger |
| Java | `java-system-out` | `System.out`/`System.err` printing |
| Go | `go-discarded-return-value` | A return value discarded with `_ =` |
| Go | `go-panic-usage` | `panic()` usage |
| Go | `go-debug-print` | A `fmt.Print`/`Println`/`Printf` statement |
| SQL | `sql-select-star` | `SELECT *` instead of named columns |
| SQL | `sql-missing-where` | `UPDATE`/`DELETE` with no `WHERE` clause |

These are all declarative pattern rules, the same mechanism `customRules` in your own
`.bouncer` file uses; see <doc:Configuration>. Adding one for a language that doesn't have it
yet is a data change, not new code.

## Coverage

A below-threshold coverage result becomes a finding with rule ID `coverage-threshold`, so it
respects the same baseline and severity-threshold rules as everything else. See
<doc:Configuration> for how to configure the report path and threshold.
