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
| `inconsistent-indent` | A block indented by a different number of spaces than the file's other blocks, reported once per file (not Go or SQL) | warning | none |
| `hardcoded-ip` | An IPv4 address in a string literal, except loopback, `0.x`, link-local, multicast and netmasks, documentation ranges, versions, and test files | warning | `allow`: address prefixes to accept (none) |
| `duplicate-import` (Swift, TS/JS, Python, Go) | A module imported twice in one file | warning | none |
| `unsorted-imports` (Swift, TS/JS, Python) | An import out of alphabetical order within its group; off unless configured | warning | none |
| `generic-error-message` | An error built with a message of only generic words (`"Something went wrong"`, `"failed"`, `"invalid input"`), outside tests | warning | none |
| `resource-leak` (Go, Python, Java, Swift, TS/JS, C/C++, PowerShell) | A file or stream opened into a local that the rest of its block never closes, returns, defers, or stores | warning | none |
| `test-sleep` | A real sleep in a test file (`sleep`, `Thread.sleep`, `Task.sleep`, `time.Sleep`, `setTimeout` with a delay, `asyncio.sleep`) | warning | none |
| `test-network-call` | A test calling a real network service (`URLSession.shared`, or `fetch`/`requests`/`http.Get`/`axios` with a non-local URL) | warning | none |
| `test-real-clock` | A test reading the real clock (`Date()`, `Date.now`, `time.Now()`, `datetime.now()`); off unless configured | warning | none |
| `missing-file-header` | A file that doesn't open with a header comment, or whose header doesn't match `pattern`; off unless configured | warning | `pattern`: a regex the header must contain (none) |
| `abbreviation` | A declared name using a known abbreviation (`usrMgr`, `btnCnt`), less each language's idioms; off unless configured | warning | `allow`, `deny`: words, as `word` or `word=expansion` |
| `forbidden-import` (Swift, TS/JS, Python, Go, Java, C/C++) | An import that `deny` forbids for the file's path, or that `allow` leaves out; does nothing until configured | warning | `deny`, `allow`: `"<glob>=<module>,<module>"` entries (a bare module list applies everywhere) |
| `path-traversal` | Request input (`req.params`, `request.args`, `r.URL.Query()`, …) reaching a path join or file call, on the same line or through a variable assigned within 10 lines | warning | none |
| `logged-secret` | A log or print call that writes a password, secret, API or private key, auth token, SSN, or card number | warning | none |
| `empty-catch` (Java, C++, PowerShell, C#/Kotlin/PHP/Dart files) | A `catch` block with nothing but whitespace inside; the parse-tree version covers Swift, TS/JS, Python, and Go | warning | none |
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
| `lack-of-cohesion` | LCOM4 by default; `variant` picks `lcom1`/`lcom2` (method pairs sharing no field), `lcom3` (field-sharing groups, ignoring calls), or `lcom-hs` (Henderson-Sellers, 0–1) | warning | `maxGroups` (2), `variant` (`lcom4`), `maxPairs` (20), `maxScore` (0.9) |
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
| `large-type` | Logical lines in one class, struct, enum, actor, protocol, or interface (Go: struct and interface types) | warning | `maxLines` (400) |
| `long-closure` | Logical lines in a closure, lambda, or anonymous function, reporting only the outermost | warning | `maxLines` (20) |
| `long-boolean-expression` | Operands in one `&&`/`\|\|` (`and`/`or`) chain, counted through parentheses and negation; `==`/`__eq__`/`equals` implementations are exempt | warning | `maxOperands` (4) |
| `too-many-locals` | Distinct local variables declared in a function, excluding nested functions and closures (a TS/JS destructuring pattern counts once) | warning | `maxLocals` (10) |
| `too-many-generic-parameters` (Swift, TS/JS, Go) | Generic parameters on one type or function | warning | `maxParameters` (4) |
| `long-identifier` | A variable, property, parameter, function, or type name longer than the maximum; test functions are exempt | warning | `maxLength` (50) |
| `boolean-name-prefix` (Swift, TS/JS, Python) | A boolean variable or property whose name doesn't read as a yes/no question; off unless configured | warning | `prefixes` (is, has, should, can, will, did, was, and more), `includeParameters` (false) |
| `type-in-name` | A name whose last word restates its declared or literal type, such as `userList: [User]` or `idSet = Set<Int>()` | warning | `suffixes` (List, Array, Dict, Dictionary, Map, Set, Bool, Boolean, Int, Integer, Double, Float) |
| `file-name-mismatch` (Swift, TS/JS) | A file whose only visible top-level type is named differently from the file | warning | none |
| `npath-complexity` | NPath: acyclic execution paths through a function, saturating at 1,000,000,000; off unless configured | warning | `max` (200) |
| `maintainability-index` | Visual Studio's 0–100 maintainability index, 100 × (171 − 5.2 ln(Halstead volume) − 0.23 × cyclomatic complexity − 16.2 ln(logical lines)) / 171 | warning | `minIndex` (20) |
| `halstead-complexity` | Halstead volume, difficulty, and effort of a function body, one finding when any is over; off unless configured | warning | `maxVolume` (1000), `maxDifficulty` (30), `maxEffort` (30000) |
| `arrow-code` | A pyramid of `if`s without `else`, each the last statement of its block, that guard clauses could flatten | warning | `maxDepth` (2) |
| `too-many-loop-jumps` | The most `break`/`continue` statements leaving or restarting one loop | warning | `maxJumps` (3) |
| `recursion-without-base-case` | A function that calls itself with no branch, loop, early exit, or short circuit in its body | warning | none |
| `weighted-methods` | WMC: the sum of a class's methods' and initializers' cyclomatic complexities; test suites are skipped | warning | `max` (50) |
| `class-cohesion` | TCC/LCC (Bieman–Kang) over a class's methods that use fields; off unless configured | warning | `minTCC` (0.33), `minLCC` (0), `minMethods` (4) |
| `lazy-class` | A type with no fields, one branch-free method, and nothing else; off unless configured | warning | none |
| `middle-man` | A type where at least `minDelegations` methods, and more than half, only call a field's same-named method | warning | `minDelegations` (3) |
| `law-of-demeter` | A member chain reaching more than `maxReach` steps past its first object; off unless configured | warning | `maxReach` (2) |
| `incomplete-documentation` | A structured doc comment (Swift `- Parameter`/`- Returns`/`- Throws`, JSDoc `@param`/`@returns`/`@throws`, Python Google/NumPy/reST) that leaves out a parameter, the return value, or what's thrown | warning | `requireReturns` (true), `requireThrows` (true) |
| `stale-documentation` | A structured doc comment describing a parameter the signature doesn't have | warning | none |
| `oversized-test` | A test in a test file (path mentions `test`/`spec`) longer than `maxLines` logical lines or with more than `maxAssertions` assertions | warning | `maxLines` (50), `maxAssertions` (15) |

`npath-complexity` multiplies statements in sequence; an `if` adds its branches plus one per
`&&`/`||` and one when there's no `else`, a loop or `guard` adds one for skipping, a `switch`
sums its cases (plus one without a default, except Swift's exhaustive switches), a `try` sums
its handlers, and closures and nested functions count as one path. Halstead treats identifiers,
literals, and `self`/`true`/`nil`-style keywords as operands and every other token as an
operator (closing brackets aren't counted). `recursion-without-base-case` looks for a direct
self-call (`f(…)`, `self.f(…)`, or `this.f(…)` with the same argument labels) in a body with
no `if`, `guard`, `switch`, loop, `catch`, `throw`, ternary, `&&`, `||`, or `??`; overloaded
names and initializers are skipped, and mutual recursion isn't detected. `law-of-demeter`
counts the first field after `self`/`this` as a friend and skips chains that start from a type,
literal, or imported module, that include a pipeline, string, or builder step (`map`, `then`,
`trim`, `with…`, `set…`), or that never call a method. `lazy-class` skips public, inheriting,
conforming, attributed, generic, extended, and test types; `middle-man` skips types extended in
the same file. The doc rules only judge doc comments that already use the structured style, so
a one-line summary isn't "incomplete"; a return value is expected for a Swift non-`Void` return
type or a JS/Python function that returns a value, and a throw for a Swift `throws` function
that throws or calls `try`, or a JS/Python `throw`/`raise` outside any `try`. Go has no
parameter-doc convention, so the doc rules skip it, and the class rules don't apply to Go.

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

`long-closure` skips named function expressions (`long-function` measures them), Swift
`= { … }()` initializers and result-builder bodies passed to a type (`VStack { … }`), test-suite
blocks (`describe`, `it`, Go's `t.Run`), and JavaScript immediately invoked functions.
`boolean-name-prefix` accepts a name whose first word is one of `prefixes` or a third-person verb
(`startsWith…`), or that has an `is`/`has`/`was` word later (`tokenIsMissing`); `ALL_CAPS`
constants and `ok` are exempt, and Go is skipped, since `ok` and `found` are idiomatic there.
`type-in-name` leaves `String`/`Str` out of its default suffixes, since names like
`lineNumberString` usually mean the string form of a non-string value. `file-name-mismatch` only
applies when a file holds exactly one visible top-level type and nothing else visible but that
type's own extensions (in TS/JS, only `export`ed declarations count). It compares names ignoring
case, `-`, `_`, and `.`, so `user-service.ts` and `user.service.ts` match `UserService`; it
ignores a `Test`/`Tests` suffix and a TS `I` interface prefix, accepts either side of
`Type+Extension.swift` and a type whose name contains the file's, and skips `main`, `index`,
`package`, `mod`, `.d.ts`, `.test.`, `.spec.`, and `.stories.` files. Python and Go have no
file-per-type convention, so it doesn't apply to them.

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
| Swift | `swift-fatal-error` | `fatalError(...)`; `libraryOnly: true` limits it, and `swift-precondition`, to library code |
| Swift | `swift-precondition` | `precondition`/`preconditionFailure`; off unless configured |
| Swift | `fire-and-forget-task` | `Task { }`/`Task.detached { }` started as a statement with no cancellation check; off unless configured |
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
| Swift | `swift-shell-injection` | A `Process` running a shell with `-c` and an interpolated command string |
| TypeScript/JavaScript | `insecure-random` | `Math.random()` feeding a token, ID, secret, password, nonce, salt, or session value |
| Python | `insecure-random` | The `random` module feeding a token, ID, secret, or password |
| Go | `insecure-random` | `math/rand` feeding a token, ID, or secret |
| Go | `go-unwrapped-error` | `if err != nil { return err }` with no wrapping context; off unless configured |
| Go | `go-unmanaged-goroutine` | `go` in a function with no context, WaitGroup, errgroup, or channel |
| C | `c-debug-print` | `printf`/`fprintf(stderr, …)` of a `DEBUG`/`DBG`/`XXX`/`debug:`/`"here"` message |
| C++ | `cpp-debug-print` | The same, plus `std::cout`/`cerr`/`clog <<` a debug marker |
| PowerShell | `powershell-debug-leftover` | `Set-PSDebug -Trace`, `$DebugPreference = 'Continue'`, `Wait-Debugger`, `Set-PSBreakpoint`, `Write-Host "DEBUG…"` |

Most of these are declarative pattern rules, the same mechanism `customRules` in your own
`.bouncer` file uses; see <doc:Configuration>. Adding one for a language that doesn't have it
yet is a data change, not new code. `swift-fatal-error`, `swift-precondition`,
`swift-shell-injection`, `insecure-random`, `fire-and-forget-task`, `go-unwrapped-error`, and
`go-unmanaged-goroutine` are small text rules instead, because they need more context than one
line.

`swift-fatal-error` and `swift-precondition` take `libraryOnly`: when true, test files and
executable code are skipped. A file is executable when it is `main.swift` or declares `@main`,
when a directory between it and its target root holds `main.swift` or an `@main` file, or when
`Package.swift` declares an `executableTarget` with the target's name. `resource-leak` follows
the variable to the end of its block; returning, yielding, deferring, `with`/`using`, storing it
in a field or struct literal, appending it, or wrapping it in `new` counts as handing it off, and
Java try-with-resources headers are skipped. `go-unmanaged-goroutine` treats any mention of
`ctx`, `context.`, `WaitGroup`, `errgroup`, `chan`, `<-`, `select`, `close(`, `done`, `quit`,
`stop`, or `shutdown` in the enclosing function, or in the goroutine's own block, as
coordination. `test-sleep`, `test-network-call`, and `test-real-clock` run only on test paths;
fake timers or frozen time turn off the `setTimeout` and clock checks, and an intercepting HTTP
mock (nock, msw, fetch-mock, responses, requests_mock, respx, httpretty, vcr, URLProtocol, gock,
httpmock) turns off the network check. `generic-error-message` needs a plain literal of at most
five words, all generic. `path-traversal` is approximate: it follows request input only on the
same line or through an assignment within the 10 lines above, and `basename`,
`filepath.Base`, `secure_filename`, `lastPathComponent`, `safe_join`, `parseInt`, `int(`,
`Atoi`, and `sanitize…` clear it. `logged-secret` reads identifiers and interpolations, never
words inside strings; names ending in a describing word (`passwordField`, `tokenCount`),
presence or length checks, and lines that redact or mask are skipped. `forbidden-import`
matches a module, anything under it (`lodash/fp`, `UIKit.UIView`), or a trailing-`*` prefix.

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
| `hotspot` | A file that changes often and is complex: commits over `sinceDays` days × total cyclomatic complexity; the top `top` are reported at their most complex function | warning | `sinceDays` (180), `minCommits` (5), `minComplexity` (30), `top` (5), `ignore` (none) |
| `change-coupling` | Two files that keep changing in the same commits although neither imports the other | warning | `sinceDays` (180), `minShared` (5), `minRatio` (0.5), `maxFilesPerCommit` (30) |
| `single-author-file` | A file nearly all of whose recent commits are by one author (bus factor 1); off unless configured | warning | `sinceDays` (365), `minCommits` (5), `minShare` (0.9) |
| `deep-inheritance` | A class more than `maxDepth` project classes deep (DIT) | warning | `maxDepth` (4) |
| `many-subclasses` | A class with more direct subclasses than allowed (NOC); off unless configured | warning | `maxChildren` (10) |
| `refused-bequest` | A subclass overriding inherited methods only to throw, trap, or do nothing | warning | none |
| `parallel-inheritance` | Two hierarchies whose subtypes pair up by name (`CircleShape`/`CircleRenderer`) | warning | `minPairs` (3), `minShare` (0.75) |
| `main-sequence-distance` | A module far from the main sequence, `abs(A + I − 1)`; off unless configured | warning | `minTypes` (5), `maxDistance` (0.7) |
| `data-clump` | The same 3+ parameters or fields (name and type) in several functions and types across files | warning | `minMembers` (3), `minOccurrences` (4), `maxMembers` (12) |
| `repeated-switch` | The same `switch` subject with shared cases in several files | warning | `minOccurrences` (3), `minFiles` (3), `minSharedCases` (2), `ignoreSubjects` (none) |
| `single-implementation-interface` | A protocol or interface with one implementation and no test double; off unless configured | warning | `includePublic` (false) |
| `unused-dependency` | A SwiftPM, `package.json`, or `go.mod` dependency no code imports | warning | `ignore` (none) |
| `inconsistent-terminology` | A module mixing synonym verbs (`fetchX`, `getY`, `loadZ`); off unless configured | warning | `groups`, `ignoreNames` |
| `missing-readme` | A SwiftPM target, `package.json` package, or Go module without a README; off unless configured | warning | `includeTests` (false) |

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

`inconsistent-indent` measures each block's first line against the line that opens it (`{`,
Python's `:`, a shell `then`/`do`/`else`), skipping blocks opened on continuation lines or inside
an open bracket, comments, multi-line strings, and tab-indented lines (those are
`mixed-indentation`'s). The most common step is the file's width; it reports the first block that
differs, once per file, only when that width covers at least two blocks and more than the others
combined. `hardcoded-ip` only looks inside quoted strings on code lines and skips test, fixture,
and mock files. It still flags private ranges (`10.x`, `172.16–31.x`, `192.168.x`), which are
deployment details too; list prefixes such as `"10."` in `allow` to accept them. IPv6 isn't
checked. `insecure-random` needs the random value to be assigned to a token-, ID-, or
secret-like name, built with `.toString(36)`, or produced in a function with such a name; Python
needs `import random`, and Go a `math/rand` import without `crypto/rand`.
`swift-shell-injection` follows only an interpolated string literal right after `"-c"`, with a
shell named in the same argument list or as the nearest `executableURL`/`launchPath`; a command
built into a variable first isn't followed. `duplicate-import` ignores Swift imports in different
`#if` branches, Python imports that aren't at module level, and TypeScript type-only or
namespace imports next to value imports. `unsorted-imports` compares runs of import lines with no
blank line or comment between them, ignoring case and Swift attributes; TypeScript and JavaScript
sort packages before `@/`/`~` aliases, then `../`, then `./`, and side-effect imports stay put;
Python accepts isort's default or a plain order by module. Go isn't checked, since gofmt sorts
imports.

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

`hotspot`, `change-coupling`, and `single-author-file` read the repository's history with one
`git log` call per run. They count the window back from `HEAD`'s commit date rather than today,
skip merge commits, follow renames to each file's current path, and tell authors apart by email
as `.mailmap` maps it. Outside a git repository they do nothing. `hotspot` measures the
`10 × top` most-changed code files with the same analyzers as `cyclomatic-complexity`, and skips
generated files (a header saying `DO NOT EDIT`, `@generated`, or `Code generated by`).
`change-coupling` scores a pair as shared commits over the average of the two files' commit
counts and ignores commits touching more than `maxFilesPerCommit` files. It only pairs files in
the dependency graph that aren't in the same Swift target or Go package and aren't joined by an
import either way, since that coupling is already visible. `single-author-file` stays quiet when
the window has fewer than two authors.

The structure rules (`deep-inheritance` through `inconsistent-terminology`) read the types,
functions, and `switch` statements each analyzer caches in `.bouncer-cache/facts.json`.
Supertypes resolve by bare name within the same language, preferring the same module, so
classes outside the project (`NSObject`, `React.Component`) don't count toward depth. Test
files, DocC catalogs, and files with a generated-code header aren't judged. `refused-bequest`
counts a method whose body is empty or only throws (`throw`, `fatalError`,
`preconditionFailure`, `raise NotImplementedError`) when a project ancestor implements it for
real; a Swift `override` of a class outside the project counts only if it throws or traps.
`parallel-inheritance` strips each subtype's name to a stem (without the parent's name, or the
subtypes' common words) and reports two hierarchies sharing at least `minPairs` stems covering
`minShare` of the smaller one; a deliberate per-language or per-platform family of types
trips it by design, so turn it off where that's the architecture. `main-sequence-distance`
measures Swift targets, Go packages, and TS/JS/Python folders, with abstractness as the share
of protocols, interfaces, and abstract classes and instability as `unstable-dependency`'s.
`data-clump` counts an initializer with its type and same-named functions once, skips numbered
names (`spec1, spec2, spec3`), and skips a clump a type already holds unless `minOccurrences`
functions still pass it loose. `repeated-switch` compares subjects without whitespace, wrapping
parentheses, or a leading `self.`/`this.`, and requires shared case labels.
`single-implementation-interface` skips protocols a test file implements or mentions, Swift
`public` protocols (unless `includePublic`), interfaces that only declare properties, and
`Any…`/`…Protocol` names; Go interfaces are implicit and never count as implemented. Unused
parameters are `unused-parameter`'s. `inconsistent-terminology`'s default groups are
fetch/get/load/retrieve/read, create/make/build, delete/remove/destroy, and update/modify;
functions named only the verb and framework-dictated names (`buildBlock`, `makeIterator`) don't
count.

`unused-dependency` reads manifests as text. For SwiftPM, a `.package` is used if its identity
appears quoted elsewhere in the manifest (plugin packages are skipped), and a
`.product(name:package:)` in a target is reported if none of the target's files import it. For
`package.json` it checks `dependencies` only, exempting `@types/` packages, peer dependencies,
runtime helpers (`tslib`, `@babel/runtime`, `regenerator-runtime`, `core-js`), tools the
`scripts` run, and packages named elsewhere in the manifest; a workspace root's dependencies
count as used by every workspace. For `go.mod` it checks direct requirements. Python isn't
checked, since distribution names differ from import names. `missing-readme` accepts any
`README*` file, and a DocC catalog in a Swift target.

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

## Change rules

`bouncer check` runs these over the change being checked, whether or not `project.inCheck` is set.

| Rule ID | Checks | Default severity | Parameters |
|---|---|---|---|
| `oversized-change` | A staged change too big to review well, reported once at its largest changed file | warning | `maxChangedLines` (400), `maxFiles` (30), `ignore` (none) |
| `complexity-ratchet` | A function already over the complexity or length limit on the base branch that got worse | warning | `base` (see below), `maxComplexity` (`cyclomatic-complexity`'s `max`), `maxLines` (`long-function`'s `maxLines`) |
| `public-api-growth` | Public symbols a change adds (Swift `public`/`open`, TS/JS exports, Go capitalized names); off unless configured | warning | `base` (as `complexity-ratchet`), `ignore` (none) |

`oversized-change` only applies to staged files (not `--files` or `--stdin`). It counts added
plus deleted lines from `git diff --cached`, so a pure rename counts 0, and leaves out lockfiles
(`package-lock.json`, `yarn.lock`, `pnpm-lock.yaml`, `Package.resolved`, `go.sum`, `Cargo.lock`,
`poetry.lock`, `Gemfile.lock`, `composer.lock`), `*.snap` files, `exclude`, and `ignore`.
`complexity-ratchet` compares each checked file with its version at the merge base of `HEAD` and
`base`, by default the first of `origin/main`, `main`, `origin/master`, and `master` that exists;
with none, it does nothing. Functions are matched by name, and a function is reported only if it
was already over a limit at the base and grew. New, renamed, and unnamed functions, names
declared a different number of times in the two versions, and functions that merely cross a
limit are left to `cyclomatic-complexity` and `long-function`.

`public-api-growth` aligns each checked file's public symbols with its version at the same merge
base, by name in line order, and reports those left over; a new file gets one finding listing
its symbols. Conformance members (`encode`, `hash`, `description`, `debugDescription`, `body`,
`id`) and test files are skipped. Turn it on for library repos that review API growth.

## Coverage

A below-threshold coverage result becomes a finding with rule ID `coverage-threshold`, so it
respects the same baseline and severity-threshold rules as everything else. See
<doc:Configuration> for how to configure the report path and threshold.
