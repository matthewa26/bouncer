# Roadmap

Every check below is meant to become part of Bouncer eventually. ✅ = Bouncer implements it today. ⬜ = not implemented yet.
The **Scope** column says what analysis a check needs:
- **F**: one file at a time. Fits Bouncer's current rule model.
- **X**: cross-file. Needs a repo-wide index, which Bouncer doesn't have yet.
- **T**: type or semantic info, which needs a real AST.

---

## 0. What's enforced today

**This repo's `.bouncer`:** `long-function` ≤ 10 lines (error) and `missing-documentation` with scope `all` (error); `swift-debug-print` is off, since a CLI writes its output with `print`. Excludes `Tests/**`, `**/*.md`, `.build/**`, and the vendored `Sources/CTreeSitter*` grammars.

**Kirby profile:** coverage ≥ 90%, function ≤ 10 lines, cyclomatic complexity ≤ 6, cognitive complexity ≤ 8, ≤ 3 parameters, no boolean flag parameters, ≤ 3 returns, nesting ≤ 3, LCOM4 = 1, ≤ 8 imports, ≤ 3 switch branches, naming, docs and god-class checks, and every single-location smell rule (`force-unwrap`, `force-try`, `force-cast`, `implicitly-unwrapped-optional`, `non-null-assertion`, `explicit-any`, `nested-ternary`, `empty-catch`, `unreachable-code`, `magic-number`), all as errors.

**Defaults (warnings):** file ≤ 500 lines, function ≤ 40 lines, nesting ≤ 16 by indentation, line ≤ 120 chars, ≤ 5 TODO markers per 100 lines, no repeated 6-line block, complexity ≤ 10, ≤ 15 imports, ≤ 6 switch branches, god-class at ≤ 20 members and ≤ 10 imports, coverage ≥ 80% (taken from the README example). On Swift, TypeScript and JavaScript also: ≤ 5 parameters, no boolean flag parameters, ≤ 4 returns, cognitive complexity ≤ 15, control-flow nesting ≤ 4, LCOM4 ≤ 2.

**Language support:** TypeScript (primary, including TSX), JavaScript (including JSX) and Swift get every check marked ✅ below unless a row says otherwise. Python and Go are parsed too and get the same function-shape, cohesion, and single-location rules wherever the language has the construct (Go has no classes, ternaries, or `catch`). Everything else is heuristic.

### 0.1 TypeScript type safety

| ✓ | Check | Scope | Notes |
|---|---|---|---|
| ✅ | Explicit `any` (`explicit-any`) | F | |
| ✅ | Non-null assertion `x!` (`non-null-assertion`) | F | |
| ✅ | `@ts-ignore`/`@ts-nocheck`/`@ts-expect-error` with no reason (`ts-ignore-without-reason`) | F | |
| ✅ | Double cast `as unknown as T` (`ts-double-cast`) | F | |
| ✅ | `var` (`js-var`) | F | |
| ⬜ | Floating promise (missing `await`/`.catch`) | T | Needs type information; see section 10 |
| ✅ | `enum` where a union type would do (`ts-prefer-union-type`, opt-in) | F | TypeScript plain enums of string literals or implicit numbers |
| ✅ | Unused exports (`unused-export` for TS/JS named exports; opt-in `unused-public-symbol` for Swift `public` API) | X | Swift matches by name; matching by symbol through the compiler's index store (`IndexStoreDB`) is deferred until there's demand |

---

## 1. Size and length

| ✓ | Check | Scope | Notes |
|---|---|---|---|
| ✅ | Long function (`long-function`) | F | |
| ✅ | Long file (`file-length`) | F | |
| ✅ | Long line (`long-lines`) | F | |
| ✅ | Long parameter list (`long-parameter-list`) | F | Default 5, Kirby 3. Swift, TS, JS, Python, Go |
| ✅ | Large class: line count per type (`large-type`) | F | Default 400 logical lines; `god-class` counts members |
| ✅ | Too many methods per type (`too-many-methods`); Swift, TS, JS, Python | F | |
| ✅ | Too many fields / stored properties per type (`too-many-fields`); Swift, TS, JS | F | |
| ✅ | Too many types per file (`too-many-types`) | F | |
| ✅ | Too many return statements per function (`too-many-returns`) | F | Default 4, Kirby 3. Swift, TS, JS, Python, Go |
| ✅ | Long lambda/closure body (`long-closure`) | F | Default 20 |
| ✅ | Long boolean expression (number of `&&`/`\|\|` operands) (`long-boolean-expression`) | F | Default 4 |
| ✅ | Long method chain (train wreck) (`long-message-chain`) | F | |
| ✅ | Too many local variables (`too-many-locals`) | F | Default 10 |
| ✅ | Too many generic parameters (`too-many-generic-parameters`) | F | Default 4; Swift, TS, JS, Go |

## 2. Complexity

| ✓ | Check | Scope | Notes |
|---|---|---|---|
| ✅ | Cyclomatic complexity | F | Exact for Swift, heuristic elsewhere |
| ✅ | Deep nesting by indentation (`deep-nesting`) | F | |
| ✅ | Cognitive complexity, SonarSource-style (`cognitive-complexity`) | F | Default 15, Kirby 8. Swift, TS, JS, Python, Go |
| ✅ | Nesting by control-flow depth, not indentation (`nesting-depth`) | T | Default 4, Kirby 3. Swift, TS, JS, Python, Go |
| ✅ | NPath complexity (`npath-complexity`, opt-in) | F | Number of acyclic execution paths; default 200 |
| ✅ | Halstead volume / difficulty / effort (`halstead-complexity`, opt-in) | F | Defaults 1000 / 30 / 30000 |
| ✅ | Maintainability Index (`maintainability-index`) | F | Combines Halstead, cyclomatic and LOC; Visual Studio 0–100 scale, minimum 20 |
| ✅ | Nested ternaries (`nested-ternary`) | F | Swift, TS, JS, Python |
| ✅ | Arrow code: deep `if` pyramids; suggest guard clauses (`arrow-code`) | F | Default depth 2 |
| ✅ | `else` after `return`/`throw` (`else-after-return`) | F | |
| ✅ | Too many `break`/`continue` in a loop (`too-many-loop-jumps`) | F | Default 3 |
| ✅ | Recursion without an obvious base case (`recursion-without-base-case`) | T | Direct self-calls only |

## 3. Classic code smells (Fowler, *Refactoring*)

### Bloaters
| ✓ | Smell | Scope | How to detect |
|---|---|---|---|
| ✅ | Large class / god class | F | `god-class` (Swift, TS, JS, Python) |
| ✅ | Long method | F | `long-function` |
| ✅ | Long parameter list | F | `long-parameter-list` |
| ✅ | Primitive obsession (`primitive-obsession`, opt-in) | T | ≥ 4 required string/number params, or ID/money/date/URL-named params and fields typed as plain strings or numbers; explicit annotations only |
| ✅ | Data clumps (`data-clump`) | X | The same 3+ params or fields (name and type) in 4+ functions/types across files |

### Object-orientation abusers
| ✓ | Smell | Scope | How to detect |
|---|---|---|---|
| ✅ | Switch statements on a type tag | F | `switch-on-type-smell` |
| ✅ | Repeated switches on the same discriminator (`repeated-switch`) | X | The same subject with shared cases in 3+ files |
| ✅ | Type-checking chains (`type-check-chain`) | F | Replace with polymorphism |
| ✅ | Temporary field (`temporary-field`) | T | A private, unset mutable field one method alone assigns first and then reads; the set-in-one, read-in-a-later-one variant isn't checked |
| ✅ | Refused bequest (`refused-bequest`) | X/T | A subclass overrides methods to throw or no-op |
| ✅ | Alternative classes with different interfaces (`alternative-interfaces`, opt-in) | X | 3+ methods with matching parameter and return types under different names in unrelated types; shape stands in for purpose |

### Change preventers
| ✓ | Smell | Scope | How to detect |
|---|---|---|---|
| ✅ | Divergent change (`divergent-change`, opt-in) | X + git | A file's commits fall into 3+ reasons, approximated by co-changed modules that share no module or import |
| ✅ | Shotgun surgery (`shotgun-surgery`, opt-in) | X + git | The file's median commit also changes 6+ hand-written files across 3+ modules |
| ✅ | Parallel inheritance hierarchies (`parallel-inheritance`) | X | Subtypes pairing up by name stem |

### Dispensables
| ✓ | Smell | Scope | How to detect |
|---|---|---|---|
| ✅ | Duplicate code within a file (exact match) | F | `duplicate-block` |
| ✅ | Duplicate code across files | X | `duplicate-code`: token-based clone detection with winnowing |
| ✅ | Near-duplicates (Type-2/3 clones: renamed identifiers, small edits) (`duplicate-code`) | F/X | Renamed copies and copies with an inserted, deleted, or changed line; near-duplicates are reported with an estimated similarity (`maxGap`, `minSimilarity`) |
| ✅ | Dead code: unused private functions, vars, params, imports | F/T | `unused-private-symbol`, `unused-import`, opt-in `unused-parameter`; per file, by name |
| ✅ | Unreachable code after `return`/`throw`/`break` (`unreachable-code`) | F | Swift, TS, JS, Python, Go |
| ✅ | Speculative generality: protocol/interface with one implementation (opt-in `single-implementation-interface`), unused params (`unused-parameter`); hooks aren't checked | X | Matches your "no single-implementation interfaces" principle |
| ✅ | Lazy class: a type that does almost nothing (`lazy-class`, opt-in) | F | No fields and one branch-free method |
| ✅ | Data class: only fields, no behavior (`data-class`); classes only, not structs | F | |
| ✅ | Commented-out code | F | `commented-out-code` |
| ✅ | Excessive or redundant comments (restating the code) | F | Opt-in `redundant-comment`; comment density isn't checked |
| ✅ | TODO/FIXME/HACK density | F | `todo-density` |

### Couplers
| ✓ | Smell | Scope | How to detect |
|---|---|---|---|
| ✅ | High coupling, measured by import count | F | `high-coupling` (a proxy only) |
| ✅ | Feature envy (`feature-envy`, opt-in) | T | ≥ 5 data reads of one parameter or local, over twice the method's own member uses; objects told apart by name |
| ✅ | Inappropriate intimacy (`inappropriate-intimacy`) | X | Two types each read 2+ of the other's stored fields or `_names`, through values whose type is written or constructed |
| ✅ | Message chains / Law of Demeter (`long-message-chain`) | F | |
| ✅ | Middle man: a type that mostly just delegates (`middle-man`) | F | ≥ 3 and > half of methods forward |
| ✅ | Global mutable state (`global-mutable-state`) | F | |

## 4. Object-oriented design metrics (Chidamber–Kemerer and others)

| ✓ | Metric | Scope | Typical limit |
|---|---|---|---|
| ✅ | WMC: weighted methods per class (sum of complexity) (`weighted-methods`) | F | Default ≤ 50 |
| ✅ | LCOM4: lack of cohesion of methods (`lack-of-cohesion`) | F | 1 is cohesive; more means the type splits into that many groups. Default ≤ 2, Kirby 1. Swift, TS, JS, Python |
| ✅ | LCOM1–3 and LCOM-HS variants (`lack-of-cohesion`'s `variant`) | F | |
| ✅ | TCC/LCC: tight/loose class cohesion (`class-cohesion`, opt-in) | F | Default TCC ≥ 0.33 |
| ✅ | CBO: coupling between objects (types referenced) (`coupling-between-objects`, opt-in) | T | ≤ 10; distinct type names in annotations, heritage, constructor calls, and static access, minus built-ins |
| ✅ | RFC: response for a class (`response-for-class`, opt-in) | T | ≤ 50; methods plus distinct callees, by name |
| ✅ | DIT: depth of inheritance tree (`deep-inheritance`) | X | Default 4, project classes only |
| ✅ | NOC: number of children (opt-in `many-subclasses`) | X | Default ≤ 10 |
| ✅ | Fan-in / fan-out per module (`hub-module`, `high-fan-out`) | X | |
| ✅ | Instability I = Ce / (Ca + Ce), via the Stable Dependencies Principle (`unstable-dependency`) | X | |
| ✅ | Abstractness A and distance from the main sequence \|A + I − 1\| (opt-in `main-sequence-distance`) | X | Default ≤ 0.7 |
| ✅ | ATFD (access to foreign data) for god-class detection (`god-class` with `formula: lanza-marinescu`) | T | WMC ≥ 47, ATFD ≥ 6, TCC < 1/3; ATFD counts other objects' properties and getters read, per object name |

## 5. SOLID and design principles

| ✓ | Principle | Detectable proxy | Scope |
|---|---|---|---|
| ✅ | Single Responsibility | LCOM4 > 1 (`lack-of-cohesion`), god class, many unrelated imports | F |
| ✅ | Open/Closed | Type-switches and `is`/`instanceof` chains (`switch-on-type-smell`); the same switch repeated across files (`repeated-switch`) | F |
| ✅ | Liskov Substitution | Requirements implemented only to throw or trap; overrides opening with an argument check the parent lacks (`liskov-substitution`; inherited refusals are `refused-bequest`'s) | X/T |
| ✅ | Interface Segregation | A 5+ requirement protocol, interface, or abstract class a conformer stubs 3+ and half of (`interface-segregation`) | X |
| ✅ | Dependency Inversion | A type keeps an instance it built of a class implementing a project abstraction, or of a `…Service`/`…Client`/`…Repository`, that no initializer takes (`dependency-inversion`, opt-in) | T |
| ✅ | DRY | Clone detection: `duplicate-block` within a file, `duplicate-code` across files (exact, renamed, and near-duplicates) | X |
| ✅ | YAGNI | Unused params (`unused-parameter`), single-implementation abstractions (`single-implementation-interface`), dead code (`unused-private-symbol`, `unused-export`); unused config keys aren't checked | X |
| ✅ | Law of Demeter | Message chains reaching past the first object (`law-of-demeter`, opt-in) | F |
| ✅ | Composition over inheritance | Deep DIT (`deep-inheritance`); a fieldless subclass overriding exactly one method (`single-override-subclass`, opt-in) | X |
| ✅ | Tell, don't ask | An `if` that reads another object's state and sets that same state in its body (`tell-dont-ask`, opt-in) | T |
| ✅ | Command–query separation | A method that changes its own fields and returns a computed value, minus fluent, status-returning, `mutating`, override, caching, and `pop`/`next`-style methods (`command-query-separation`, opt-in) | T |

## 6. Architecture and dependencies

| ✓ | Check | Scope |
|---|---|---|
| ✅ | Cyclic dependencies between files, modules, and targets (`import-cycle`) | X |
| ✅ | Layering rules declared as ordered path globs (`layer-violation`) | X |
| ✅ | Forbidden imports per path (custom allow/deny list) (`forbidden-import`) | F |
| ✅ | Hub modules (`hub-module`) | X |
| ✅ | Unused dependencies in the package manifest (`unused-dependency`: SwiftPM, package.json, go.mod; not Python) | X |
| ✅ | Public API surface growth (new public symbols in a diff) (opt-in `public-api-growth`, in `check`) | X + git |

## 7. Naming and readability

| ✓ | Check | Scope |
|---|---|---|
| ✅ | Naming convention (case style per language) | F |
| ✅ | Identifier too short, except loop indices and conventional names (`short-identifier`); Swift, TS, JS | F |
| ✅ | Identifier too long (`long-identifier`) | F |
| ✅ | Boolean names without `is`/`has`/`should` (`boolean-name-prefix`, opt-in) | F |
| ✅ | Negated boolean names (`negated-boolean-name`); Swift, TS, JS | F |
| ✅ | Hungarian notation (`hungarian-notation`); Swift, TS, JS | F |
| ✅ | Type-in-name suffixes (`userList`, `nameString`) (`type-in-name`) | F |
| ✅ | Abbreviations not in an allowlist (`abbreviation`, opt-in) | F |
| ✅ | Magic numbers (`magic-number`); Swift, TS, JS, Python, Go | F |
| ✅ | Magic strings: literals repeated in a file (`duplicated-string-literal`); Swift, TS, JS | F |
| ✅ | Boolean parameters (flag arguments) (`boolean-parameter`); Swift, TS, JS, Python, Go. Initializers are exempt | F |
| ✅ | Inconsistent terminology (`fetch`/`get`/`load` mixed in one module) (opt-in `inconsistent-terminology`) | X |
| ✅ | Inconsistent file name vs. primary type name (`file-name-mismatch`; Swift, TS, JS) | F |

## 8. Documentation

| ✓ | Check | Scope |
|---|---|---|
| ✅ | Missing doc comment, by visibility scope | F |
| ✅ | Doc doesn't list every parameter, return value, or throw (`incomplete-documentation`) | F |
| ✅ | Stale doc: parameter names don't match the signature (`stale-documentation`) | F |
| ✅ | Missing file/module header (`missing-file-header`, opt-in) | F |
| ✅ | Missing README per package or target (opt-in `missing-readme`) | X |

## 9. Error handling and robustness

| ✓ | Check | Scope |
|---|---|---|
| ✅ | Python bare `except:` | F |
| ✅ | Java broad `catch (Exception)` | F |
| ✅ | Go `panic()` and discarded returns | F |
| ✅ | Empty catch block (`empty-catch`); Swift, TS, JS, Python (an `except` that only `pass`es) | F |
| ✅ | Empty catch block in the remaining languages (`empty-catch`, text-based: Java, C++, PowerShell, C#/Kotlin/PHP/Dart) | F |
| ✅ | Swift `try!`, force-unwrap `!`, `as!`, implicitly unwrapped optionals (`force-try`, `force-unwrap`, `force-cast`, `implicitly-unwrapped-optional`) | F |
| ✅ | Swift `fatalError` (`swift-fatal-error`) | F |
| ✅ | Swift `precondition` (`swift-precondition`, opt-in), and limiting either to library (non-app) code (`libraryOnly`) | F |
| ✅ | Swift `try?` that silently discards errors (`swift-discarded-try`) | F |
| ✅ | Go `if err != nil { return err }` with no wrapping context (`go-unwrapped-error`, opt-in) | F |
| ✅ | Returning `null`/`nil` where an empty collection would do (`null-collection-return`, opt-in; Swift, TS, Python, Java) | T |
| ✅ | Error message without context (`generic-error-message`) | F |
| ✅ | Resource leaks: file or handle opened with no `defer`/`with`/`using` (`resource-leak`) | F/T |

## 10. Concurrency

| ✓ | Check | Scope |
|---|---|---|
| ✅ | Swift `@unchecked Sendable` and `nonisolated(unsafe)` (`swift-unchecked-sendable`) | F |
| ✅ | `DispatchQueue.main.sync` and `semaphore.wait()` (`swift-main-sync`, `swift-semaphore-wait`) | F |
| ✅ | Mutable shared state without a lock or actor (`shared-mutable-state`; Swift and Go by default, TS/JS and Python via `languages`) | T |
| ✅ | Fire-and-forget `Task {}` with no cancellation handling (`fire-and-forget-task`, opt-in) | F |
| ✅ | Go goroutine without context or a `WaitGroup` (`go-unmanaged-goroutine`) | F |
| ⬜ | JS floating promise (missing `await`/`.catch`) | T |

## 11. Security

| ✓ | Check | Scope |
|---|---|---|
| ✅ | Secret-looking strings | F |
| ✅ | Shell `eval`; PowerShell `iex`; plaintext password conversion | F |
| ✅ | C `gets`, `strcpy`/`strcat`/`sprintf` | F |
| ✅ | SQL `UPDATE`/`DELETE` without `WHERE` | F |
| ✅ | SQL built by string concatenation or interpolation (`sql-string-building`); every language | F |
| ✅ | Shell command built from variables (`python-shell-injection`, `js-shell-injection`, `go-shell-injection`) | F |
| ✅ | Swift `Process` launched through a shell with interpolated input (`swift-shell-injection`; literal interpolation only) | T |
| ✅ | Weak crypto: MD5, SHA-1, DES, ECB (`weak-crypto`); every language | F |
| ✅ | `Math.random` used for tokens or IDs (`insecure-random`; also Python `random`, Go `math/rand`) | T |
| ✅ | `http://` in non-local code (`insecure-http-url`); every language | F |
| ✅ | Hardcoded IP addresses (`hardcoded-ip`; IPv4 in strings) | F |
| ✅ | Disabled TLS verification (`disabled-tls-verification`); every language | F |
| ✅ | Path traversal: user input joined into a file path (`path-traversal`; same line or a 10-line assignment window) | T |
| ✅ | Unsafe deserialization (`python-unsafe-deserialization`) | F |
| ✅ | JS `eval`/`new Function` (`js-eval`) and `innerHTML`/`dangerouslySetInnerHTML` (`js-raw-html`) | F |
| ✅ | Python `eval`/`exec` (`python-eval-exec`) | F |
| ✅ | Logging of secrets or PII (`logged-secret`) | T |

## 12. Testing

| ✓ | Check | Scope |
|---|---|---|
| ✅ | Line coverage threshold | X (report) |
| ⬜ | Branch coverage threshold | X (report) |
| ⬜ | Coverage on changed lines only (diff coverage) | X + git |
| ✅ | Source file with no matching test file (`missing-test-file`, opt-in) | X |
| ✅ | Test with no assertions (`test-without-assertions`) | F |
| ✅ | Disabled, skipped, or focused tests (`skipped-test`); TS/JS, Swift, Python, Go, Java | F |
| ✅ | Sleeps or real network or clock calls in tests (`test-sleep`, `test-network-call`; opt-in `test-real-clock`) | F |
| ✅ | Test function too long or with too many assertions (`oversized-test`) | F |
| ⬜ | Mutation score (would need an external tool) | X |

## 13. Formatting and hygiene

| ✓ | Check | Scope |
|---|---|---|
| ✅ | Trailing whitespace | F |
| ✅ | Missing newline at end of file (`missing-final-newline`) | F |
| ✅ | Mixed tabs and spaces (`mixed-indentation`) | F |
| ✅ | Inconsistent indent width (`inconsistent-indent`) | F |
| ✅ | CRLF line endings (`crlf-line-endings`) | F |
| ✅ | Multiple consecutive blank lines (`consecutive-blank-lines`) | F |
| ✅ | Unsorted or duplicate imports (`duplicate-import`; opt-in `unsorted-imports`, not Go) | F |
| ✅ | Debug leftovers: Swift `print`/`dump`/`NSLog` (`swift-debug-print`), JS (`js-console-log`), Python (`python-debug-print`), Go (`go-debug-print`), Java (`java-system-out`) | F |
| ✅ | Shell `set -x` left on (`shell-debug-trace`) | F |
| ✅ | Debug leftovers in C, C++, and PowerShell (`c-debug-print`, `cpp-debug-print`, `powershell-debug-leftover`; explicit debug markers only) | F |

## 14. Process and churn (git-aware)

| ✓ | Check | Scope |
|---|---|---|
| ✅ | Hotspots: high churn × high complexity (`hotspot`) | X + git |
| ✅ | Bus factor / single-author files (`single-author-file`, opt-in) | X + git |
| ✅ | Change coupling: files that always change together (`change-coupling`) | X + git |
| ✅ | Oversized commits or diffs (`oversized-change`, staged diff) | git |
| ✅ | Complexity or size increased vs. the base branch (`complexity-ratchet`) | X + git |

---

## Notes on the current implementation

- **Coverage gap:**
  - Class rules (`god-class`, `lack-of-cohesion`) don't apply to Go, which has no classes. Python's decorated methods (`@property`, `@staticmethod`) are left out of LCOM4.
  - The heuristic languages get none of the AST rules, the dead-code rules, or `duplicate-code`. A new tree-sitter language gets the shared AST rules by adding a `TreeSitterQualitySpec`, with no new rule code.
  - The dead-code rules cover Swift, TS/JS, and Python. Go is left out because a package spans files.
- **Precision gaps:**
  - Without type information, the design-principle rules (SOLID, feature envy, CBO/RFC, tell-don't-ask) are syntactic approximations; the catalog states each one's definition.
  - Dead-code rules and `unused-public-symbol` match by name, not by symbol, so a same-named identifier hides a dead declaration. Symbol-level Swift matching through the compiler's index store is deferred until there's demand.
  - `duplicate-code`'s near-duplicate similarity is an estimate from fingerprints, and its region edges can start a line or two late.
  - Coupling is an import count. These are labelled as proxies in the docs.
- **Git-aware rules:** `hotspot`, `change-coupling`, and `single-author-file` read history in the project pass; `oversized-change` and `complexity-ratchet` run in `check` through the change pass (`ChangePhase`), independent of `project.inCheck`. Function complexity for both comes from `LanguageAnalyzer.measureFunctions`.
- **Suppressions:** `bouncer:disable-line`/`disable-next-line`/`disable`/`enable`/`disable-file` comments silence named rules in place (see Configuration); there's no check yet for suppressions that no longer silence anything.
- **Architecture:** the project pass (`ProjectRules` over cached `FileFacts` in `.bouncer-cache/facts.json`) is where cross-file rules go, such as cycles, layers, unused exports, and clones. It runs in `review` and `baseline update`, and in `check` only with `project.inCheck`. Each file is parsed once for both per-file rules and facts.
- **Easiest wins:**
  - Many remaining **F** items are a few lines of `LanguageProfiles` pattern data, such as a new language's debug-print or unsafe-call pattern.
  - Shared AST rules live once in `DeclarationFindings`. A new per-function metric is one `MetricRule` entry, and a new single-location smell is one `MarkerKind` case plus where each parser detects it.
  - Per-type metrics sit on `CollectedType`, as LCOM4 does via `CohesionGraph`.
