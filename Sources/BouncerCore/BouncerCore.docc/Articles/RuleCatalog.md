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

These run on every language.

| Rule ID | Checks | Default severity | Parameters |
|---|---|---|---|
| `file-length` | A file's logical line count (blank and comment-only lines excluded) | warning | `maxLines` (500) |
| `long-function` | A function's logical line count | warning | `maxLines` (40) |
| `deep-nesting` | A line's indentation depth | warning | `maxDepth` (16), `indentWidth` (4) |
| `long-lines` | A line's character count | warning | `maxLength` (120) |
| `todo-density` | TODO/FIXME/HACK marker density across a file | warning | `maxPerHundredLines` (5) |
| `duplicate-block` | A repeated block of lines within the same file | warning | `windowSize` (6) |
| `commented-out-code` | A stretch of non-doc comment lines that reads as code, reported at its first line | warning | `minLines` (2) |
| `redundant-comment` | A one-line comment that only restates the statement below it; off unless configured | warning | none |
| `trailing-whitespace` | A line ending in a space or tab | warning | none |
| `secret-looking-pattern` | A line matching a small set of credential-shaped patterns | warning | none |
| `missing-final-newline` | A non-empty file that doesn't end with a newline | warning | none |
| `crlf-line-endings` | A file using Windows (CRLF) line endings, reported once per file | warning | none |
| `mixed-indentation` | A file indenting some lines with tabs and others with spaces | warning | none |
| `consecutive-blank-lines` | A run of blank lines longer than the limit | warning | `maxBlankLines` (2) |
| `weak-crypto` | MD5, SHA-1, DES, or ECB mode | warning | none |
| `disabled-tls-verification` | `rejectUnauthorized: false`, `NODE_TLS_REJECT_UNAUTHORIZED=0`, `verify=False`, `InsecureSkipVerify: true`, `curl -k` | warning | none |
| `insecure-http-url` | A plain `http://` URL, except localhost, `.local`/`.test`/`.example` hosts, and XML namespaces | warning | none |
| `sql-string-building` | SQL built by concatenation or interpolation (`"SELECT … " + x`, `${x}`, `\(x)`, f-strings) | warning | none |

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
| `type-check-chain` | Runtime type checks per function (`instanceof`, `is`, `as?`, `isinstance`, Go type assertions) | warning | `maxTypeChecks` (2) |
| `too-many-methods` | A class's method count, excluding initializers | warning | `maxMethods` (20) |
| `too-many-fields` | A class's stored property count | warning | `maxFields` (15) |
| `data-class` | A class with two or more fields and no methods (not structs) | warning | none |
| `too-many-types` | Classes and structs declared in one file | warning | `maxTypes` (5) |
| `else-after-return` | An `else` after a branch that always returns, throws, breaks, or continues | warning | none |
| `global-mutable-state` | A stored top-level or `static var`, a top-level `let`/`var` in TS/JS, Python's `global`, a Go package `var` | warning | none |
| `long-message-chain` | A chain of calls such as `a.b().c().d()` (Law of Demeter) | warning | `maxCalls` (5) |
| `test-without-assertions` | A test (`test…`/`@Test` in Swift, `it`/`test` callbacks in TS/JS, `test_` in Python, `Test…` in Go) that never asserts | warning | none |
| `short-identifier` | A variable or parameter name shorter than the minimum, except `i`, `j`, `k`, `x`, `y`, `z`, `e`, `n`, `t`, `_`, `id`, `ok` | warning | `minLength` (2) |
| `negated-boolean-name` | A name like `isNotReady` or `notFound` | warning | none |
| `hungarian-notation` | A name with a type prefix, such as `strName`, `bIsOpen`, `arrItems`, `m_value` | warning | none |
| `duplicated-string-literal` | The same plain string literal repeated in a file | warning | `minOccurrences` (3), `minLength` (5) |
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
| `unused-private-symbol` | A file-private declaration nothing else in its file uses: Swift `private`/`fileprivate` functions, properties, and types; unexported top-level TS/JS functions, classes, and variables in modules; `_`-prefixed Python module-level functions and classes | warning | none |
| `unused-import` (TS/JS, Python) | An import binding the file never uses | warning | none |
| `unused-parameter` | A parameter its function never uses; TS/JS only flags parameters after the last used one; off unless configured | warning | none |

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

The naming and duplicated-string rules, and class field counts, run on Swift, TypeScript, and
JavaScript; the other rules in this table also run on Python and Go where the language has the
construct. `duplicated-string-literal` will also flag the repeated target names in a Swift
`Package.swift`; raise `minOccurrences` or exclude the manifest if that's noise for you.

`empty-catch` accepts a comment inside the braces as a deliberate "nothing to do here".

The dead-code rules (`unused-private-symbol`, `unused-import`, `unused-parameter`) match by name
within one file: a same-named use anywhere outside the declaration counts, and a declaration's use
of itself (recursion) doesn't. They skip what something outside the code may call: in Swift,
overrides, `@objc` and Interface Builder hooks, property wrappers, stored class properties, and
every member of a type that declares a conformance or superclass in the file; in TS/JS, top-level
names in scripts (files with no imports or exports) and `.d.ts` files; in Python, `__init__.py`
imports, `from __future__`, star imports, `# noqa` imports, and names in `__all__`. JSX, type
positions, re-exports, and Python string annotations count as uses. Go is left out: a package
spans files, and the compiler already rejects unused imports. `unused-parameter` also skips
`_`-prefixed names, stub bodies (empty, or only a `throw`/`fatalError`/`pass`/`raise`), methods of
subclasses and conforming types, Python `self`/`cls`/`*args`/`**kwargs`, protocol dunders, pytest
tests and fixtures, and TypeScript constructor parameter properties.

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
| bash/zsh | `shell-debug-trace` | `set -x` tracing left on |
| Python | `python-bare-except` | A bare `except:` clause |
| Python | `python-mutable-default-arg` | A mutable (`[]`/`{}`) default argument |
| Python | `python-debug-print` | A `print(...)` statement |
| Python | `python-eval-exec` | `eval(...)`/`exec(...)` |
| Python | `python-unsafe-deserialization` | `pickle`/`marshal` loads, or `yaml.load` without `SafeLoader` |
| Python | `python-shell-injection` | `subprocess` with `shell=True`, or `os.system` |
| Python | `skipped-test` | `@skip`/`@unittest.skip`/`pytest.mark.skip` |
| TypeScript/JavaScript | `js-console-log` | `console.log`/`debugger` left in |
| TypeScript/JavaScript | `js-loose-equality` | `==`/`!=` instead of `===`/`!==` |
| TypeScript/JavaScript | `ts-ignore-without-reason` | `@ts-ignore`/`@ts-nocheck`/`@ts-expect-error` with no explanation |
| TypeScript/JavaScript | `ts-double-cast` | `as unknown as T` |
| TypeScript/JavaScript | `js-var` | `var` instead of `let`/`const` |
| TypeScript/JavaScript | `js-eval` | `eval(...)` or `new Function(...)` |
| TypeScript/JavaScript | `js-raw-html` | `innerHTML`/`outerHTML` assignment, `insertAdjacentHTML`, `dangerouslySetInnerHTML` |
| TypeScript/JavaScript | `js-shell-injection` | `exec`/`execSync` with a template string containing `${…}` |
| TypeScript/JavaScript | `skipped-test` | `it/test/describe.skip` or `.only`, `xit`/`xdescribe`, `fit`/`fdescribe` |
| Swift | `swift-fatal-error` | `fatalError(...)` |
| Swift | `swift-unchecked-sendable` | `@unchecked Sendable` or `nonisolated(unsafe)` |
| Swift | `swift-debug-print` | A `print`/`debugPrint`/`dump`/`NSLog` statement |
| Swift | `swift-discarded-try` | A `try?` whose result is thrown away |
| Swift | `swift-main-sync` | `DispatchQueue.main.sync`, which deadlocks on the main thread |
| Swift | `swift-semaphore-wait` | Blocking `semaphore.wait()` |
| Swift | `skipped-test` | `XCTSkip` or a `.disabled(...)` trait |
| C | `c-gets-usage` | `gets(...)`, which can't bound its input |
| C | `c-unsafe-string-function` | `strcpy`/`strcat`/`sprintf` |
| PowerShell | `powershell-invoke-expression` | `Invoke-Expression`/`iex` usage |
| PowerShell | `powershell-plaintext-password` | `-AsPlainText` password conversion |
| C++ | `cpp-raw-new-delete` | Raw `new`/`delete` instead of a smart pointer |
| C++ | `cpp-using-namespace-std` | File-scope `using namespace std;` |
| Java | `java-generic-exception-catch` | Catching `Exception`/`Throwable` broadly |
| Java | `java-print-stack-trace` | `.printStackTrace()` instead of a logger |
| Java | `java-system-out` | `System.out`/`System.err` printing |
| Java | `skipped-test` | `@Disabled`/`@Ignore` |
| Go | `go-discarded-return-value` | A return value discarded with `_ =` |
| Go | `go-panic-usage` | `panic()` usage |
| Go | `go-debug-print` | A `fmt.Print`/`Println`/`Printf` statement |
| Go | `go-shell-injection` | `exec.Command("sh", "-c", …)` |
| Go | `skipped-test` | `t.Skip`/`t.Skipf`/`t.SkipNow` |
| SQL | `sql-select-star` | `SELECT *` instead of named columns |
| SQL | `sql-missing-where` | `UPDATE`/`DELETE` with no `WHERE` clause |

These are all declarative pattern rules, the same mechanism `customRules` in your own
`.bouncer` file uses; see <doc:Configuration>. Adding one for a language that doesn't have it
yet is a data change, not new code.

## Project rules

These look across files, using each file's imports and exports. `bouncer review` runs them;
`bouncer check` runs them only with `project.inCheck` set (see <doc:Configuration>).

| Rule ID | Checks | Default severity | Parameters |
|---|---|---|---|
| `import-cycle` | A cycle of imports, reported once at an import inside it with the full path | warning | none |
| `layer-violation` | An import from a lower layer into a higher one | warning | `layers`: path globs, top layer first (none, so off) |
| `unused-export` | A TS/JS named export nothing in the project imports | warning | `entryPoints`: globs whose exports are used externally |
| `high-fan-out` | A file, Swift target, or Go package depending on too many others in the project | warning | `maxDependencies` (15) |
| `hub-module` | A file, target, or package too much of the project depends on | warning | `maxDependents` (30) |
| `unstable-dependency` | A stable module importing a less stable one (Stable Dependencies Principle) | warning | `minDifference` (30, a percentage) |
| `missing-test-file` | A source file with no conventionally named test file; off unless configured | warning | none |
| `unused-public-symbol` | A Swift `public`/`open` declaration no other target uses; off unless configured | warning | `publicTargets`, `ignoreNames` |
| `duplicate-code` | A block of code copied into another file, exactly or with renamed identifiers or changed literals | warning | `minTokens` (50), `minLines` (6), `ignoreLiterals` (true), `ignore` (none) |

`layer-violation` reads `layers` as an ordered list: a file in one layer may import its own layer
or any later one, never an earlier one, and files matching no layer are unconstrained. For
example, `["src/ui/**", "src/domain/**", "src/infra/**"]` lets the UI use the domain and the
domain use infrastructure, but not the reverse.

`unused-export` skips default exports, which frameworks load by convention (pages, stories,
configs), and entry points: `index` files, `.d.ts` files, tests, stories, `*.config.*` files, and
anything matching `entryPoints`. A namespace import or `export *` counts every export as used.

`unstable-dependency` uses Robert Martin's instability, `outgoing / (incoming + outgoing)`: 0 for
code everything depends on, 1 for code nothing depends on. It flags an import whose target is
more unstable than its source by more than `minDifference` percentage points, since changes to
volatile code then ripple into the stable code that depends on it.

`unused-public-symbol` infers usage by name, since Swift imports name a module rather than
symbols: a public declaration counts as used if any file in another target (test targets
included) refers to it, or declares the same name, which is how a protocol requirement's
implementation elsewhere shows up. Overrides, operators, `@objc` declarations, protocol
requirements, and `@main` types are skipped, and so are `body`, `description`,
`debugDescription`, `hash`, `encode`, and `id` plus anything in `ignoreNames`. List library
targets whose public API is meant for other packages in `publicTargets`. Because it matches by
name, two symbols sharing a name hide each other, and a value used without naming its type can
look unused; treat its findings as candidates to make `internal`.

Matching by symbol instead is possible but not built. It would read the index store the Swift
compiler writes during `swift build`, through `IndexStoreDB`, and match each declaration's
unique symbol ID (USR) to its references and protocol conformances. The cost: the rule would
need a fresh build, so it couldn't run in `check`, and Bouncer would take on a dependency that
tracks the Swift toolchain version. It can be built if there's demand.

`commented-out-code` scores each comment line on code shapes (a trailing `;`, `{`, or `}`,
assignments, calls, keywords) against prose shapes (mostly plain words, English function words,
a sentence-ending period). A stretch needs `minLines` code-like lines, or one unambiguous line
such as `// let total = compute(items)`. It skips doc comments, license headers, Python
docstrings, examples (fenced, indented under prose, or after a line ending in `:` or `e.g.`),
URLs, task markers, tool directives (`swiftlint:`, `eslint-disable`, `@ts-`, `noqa`, `go:`), and
Go cgo preambles, and it doesn't run on unrecognized languages. `redundant-comment` flags a lone
line comment of two or more content words that all appear in the next statement's identifiers,
keywords, or the verbs its operators imply, such as `// increment counter` above `counter += 1`.

`missing-test-file` looks for `foo.test.ts`/`foo.spec.ts`, `test_foo.py`/`foo_test.py`,
`foo_test.go`, or `FooTests.swift`/`FooTest.swift` anywhere in the project. It's off by default;
turn it on by listing it under `rules`.

`duplicate-code` tokenizes each Swift, TypeScript/JavaScript, Python, and Go file without
whitespace or comments, normalizing identifiers (by consistent renaming, so a copy with renamed
variables still matches) and literals, and fingerprints it with k-gram winnowing; fingerprints
are cached in `.bouncer-cache/facts.json`. Copies of at least `minTokens` tokens and `minLines`
code lines are grouped into clone classes, and each copy is reported once, naming the first copy
(by path, then line) and, for three or more, how many copies there are. Copies within one file
are left to `duplicate-block`. Set `ignoreLiterals` to `false` to require literal values to
match, and list generated or vendored paths in `ignore` (or `exclude`). Copies with small edits
or inserted lines (Type-3 clones) show up only as their unchanged parts.

Imports are resolved per language. TypeScript and JavaScript resolve relative specifiers (trying
each TS/JS extension, `index` files, and `.js` written for a `.ts` file); `baseUrl` and `paths`
aliases from each file's nearest `tsconfig.json`, following relative `extends` chains; and the
repo's own workspace packages, found from every `package.json` above a source file. A workspace
package import such as `@acme/ui` or `@acme/ui/button` resolves through `exports`, `source`,
`module`, or `main`, mapping build output like `dist/index.js` back to `src/`, and falling back to
`src/index`. Third-party packages are external. Swift resolves
`import X` to the SwiftPM target in `Sources/X` or `Tests/X`. Python resolves dotted and relative
imports to `.py` files or packages at the root or under `src/`. Go resolves imports under the
`go.mod` module path to package directories.

## Coverage

A below-threshold coverage result becomes a finding with rule ID `coverage-threshold`, so it
respects the same baseline and severity-threshold rules as everything else. See
<doc:Configuration> for how to configure the report path and threshold.
