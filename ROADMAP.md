# Roadmap

This file is the source of truth for what Bouncer does and since when. ✅ = shipped; ⬜ = not shipped yet.
The **Since** column gives the earliest release with the feature. For ⬜ rows it says `planned <version>` when the work is scheduled, or `backlog` when it isn't. A change that ships a feature flips its row to ✅ with the release version in the same commit.
The **Scope** column says what analysis a check needs:
- **F**: one file at a time. Fits Bouncer's current rule model.
- **X**: cross-file. Needs a repo-wide index, which Bouncer doesn't have yet.
- **T**: type or semantic info, which needs a real AST.

---

## 0. What's enforced today

**This repo's `.bouncer`:** `long-function` ≤ 10 lines (error) and `missing-documentation` with scope `all` (error); `swift-debug-print` is off, since a CLI writes its output with `print`. Excludes `Tests/**`, `**/*.md`, `.build/**`, and the vendored `Sources/CTreeSitter*` grammars.

**Kirby profile:** coverage ≥ 90%, function ≤ 10 lines, cyclomatic complexity ≤ 6, cognitive complexity ≤ 8, ≤ 3 parameters, no boolean flag parameters, ≤ 3 returns, nesting ≤ 3, LCOM4 = 1, ≤ 8 imports, ≤ 3 switch branches, naming, docs and god-class checks, and every single-location smell rule (`force-unwrap`, `force-try`, `force-cast`, `implicitly-unwrapped-optional`, `non-null-assertion`, `explicit-any`, `nested-ternary`, `empty-catch`, `unreachable-code`, `magic-number`), all as errors.

**Defaults (warnings):** file ≤ 500 lines, function ≤ 40 lines, nesting ≤ 16 by indentation, line ≤ 120 chars, ≤ 5 TODO markers per 100 lines, no repeated 6-line block, complexity ≤ 10, ≤ 15 imports, ≤ 6 switch branches, god-class at ≤ 20 members and ≤ 10 imports, coverage ≥ 80% (taken from the README example). On Swift, TypeScript and JavaScript also: ≤ 5 parameters, no boolean flag parameters, ≤ 4 returns, cognitive complexity ≤ 15, control-flow nesting ≤ 4, LCOM4 ≤ 2.

**Language support:** TypeScript (primary, including TSX), JavaScript (including JSX) and Swift get every check marked ✅ below unless a row says otherwise. Objective-C, Rust, Python and Go are parsed too and get the same function-shape, cohesion, and single-location rules wherever the language has the construct (Go has no classes, ternaries, or `catch`). Everything else is heuristic.

### 0.1 TypeScript type safety

| ✓ | Check | Scope | Notes | Since |
|---|---|---|---|---|
| ✅ | Explicit `any` (`explicit-any`) | F | | 1.0.0 |
| ✅ | Non-null assertion `x!` (`non-null-assertion`) | F | | 1.0.0 |
| ✅ | `@ts-ignore`/`@ts-nocheck`/`@ts-expect-error` with no reason (`ts-ignore-without-reason`) | F | | 1.0.0 |
| ✅ | Double cast `as unknown as T` (`ts-double-cast`) | F | | 1.0.0 |
| ✅ | `var` (`js-var`) | F | | 1.0.0 |
| ⬜ | Floating promise (missing `await`/`.catch`) | T | Needs type information; see section 10 | backlog |
| ✅ | `enum` where a union type would do (`ts-prefer-union-type`, opt-in) | F | TypeScript plain enums of string literals or implicit numbers | 1.0.0 |
| ✅ | Unused exports (`unused-export` for TS/JS named exports; opt-in `unused-public-symbol` for Swift `public` API) | X | Swift matches by name; matching by symbol through the compiler's index store (`IndexStoreDB`) is deferred until there's demand | 1.0.0 |

---

## 1. Size and length

| ✓ | Check | Scope | Notes | Since |
|---|---|---|---|---|
| ✅ | Long function (`long-function`) | F | | 1.0.0 |
| ✅ | Long file (`file-length`) | F | | 1.0.0 |
| ✅ | Long line (`long-lines`) | F | | 1.0.0 |
| ✅ | Long parameter list (`long-parameter-list`) | F | Default 5, Kirby 3. Swift, TS, JS, Python, Go | 1.0.0 |
| ✅ | Large class: line count per type (`large-type`) | F | Default 400 logical lines; `god-class` counts members | 1.0.0 |
| ✅ | Too many methods per type (`too-many-methods`); Swift, TS, JS, Python | F | | 1.0.0 |
| ✅ | Too many fields / stored properties per type (`too-many-fields`); Swift, TS, JS | F | | 1.0.0 |
| ✅ | Too many types per file (`too-many-types`) | F | | 1.0.0 |
| ✅ | Too many return statements per function (`too-many-returns`) | F | Default 4, Kirby 3. Swift, TS, JS, Python, Go | 1.0.0 |
| ✅ | Long lambda/closure body (`long-closure`) | F | Default 20 | 1.0.0 |
| ✅ | Long boolean expression (number of `&&`/`\|\|` operands) (`long-boolean-expression`) | F | Default 4 | 1.0.0 |
| ✅ | Long method chain (train wreck) (`long-message-chain`) | F | | 1.0.0 |
| ✅ | Too many local variables (`too-many-locals`) | F | Default 10 | 1.0.0 |
| ✅ | Too many generic parameters (`too-many-generic-parameters`) | F | Default 4; Swift, TS, JS, Go | 1.0.0 |

## 2. Complexity

| ✓ | Check | Scope | Notes | Since |
|---|---|---|---|---|
| ✅ | Cyclomatic complexity | F | Exact for Swift, heuristic elsewhere | 1.0.0 |
| ✅ | Deep nesting by indentation (`deep-nesting`) | F | | 1.0.0 |
| ✅ | Cognitive complexity, SonarSource-style (`cognitive-complexity`) | F | Default 15, Kirby 8. Swift, TS, JS, Python, Go | 1.0.0 |
| ✅ | Nesting by control-flow depth, not indentation (`nesting-depth`) | T | Default 4, Kirby 3. Swift, TS, JS, Python, Go | 1.0.0 |
| ✅ | NPath complexity (`npath-complexity`, opt-in) | F | Number of acyclic execution paths; default 200 | 1.0.0 |
| ✅ | Halstead volume / difficulty / effort (`halstead-complexity`, opt-in) | F | Defaults 1000 / 30 / 30000 | 1.0.0 |
| ✅ | Maintainability Index (`maintainability-index`) | F | Combines Halstead, cyclomatic and LOC; Visual Studio 0–100 scale, minimum 20 | 1.0.0 |
| ✅ | Nested ternaries (`nested-ternary`) | F | Swift, TS, JS, Python | 1.0.0 |
| ✅ | Arrow code: deep `if` pyramids; suggest guard clauses (`arrow-code`) | F | Default depth 2 | 1.0.0 |
| ✅ | `else` after `return`/`throw` (`else-after-return`) | F | | 1.0.0 |
| ✅ | Too many `break`/`continue` in a loop (`too-many-loop-jumps`) | F | Default 3 | 1.0.0 |
| ✅ | Recursion without an obvious base case (`recursion-without-base-case`) | T | Direct self-calls only | 1.0.0 |

## 3. Classic code smells (Fowler, *Refactoring*)

### Bloaters
| ✓ | Smell | Scope | How to detect | Since |
|---|---|---|---|---|
| ✅ | Large class / god class | F | `god-class` (Swift, TS, JS, Python) | 1.0.0 |
| ✅ | Long method | F | `long-function` | 1.0.0 |
| ✅ | Long parameter list | F | `long-parameter-list` | 1.0.0 |
| ✅ | Primitive obsession (`primitive-obsession`, opt-in) | T | ≥ 4 required string/number params, or ID/money/date/URL-named params and fields typed as plain strings or numbers; explicit annotations only | 1.0.0 |
| ✅ | Data clumps (`data-clump`) | X | The same 3+ params or fields (name and type) in 4+ functions/types across files | 1.0.0 |

### Object-orientation abusers
| ✓ | Smell | Scope | How to detect | Since |
|---|---|---|---|---|
| ✅ | Switch statements on a type tag | F | `switch-on-type-smell` | 1.0.0 |
| ✅ | Repeated switches on the same discriminator (`repeated-switch`) | X | The same subject with shared cases in 3+ files | 1.0.0 |
| ✅ | Type-checking chains (`type-check-chain`) | F | Replace with polymorphism | 1.0.0 |
| ✅ | Temporary field (`temporary-field`) | T | A private, unset mutable field one method alone assigns first and then reads; the set-in-one, read-in-a-later-one variant isn't checked | 1.0.0 |
| ✅ | Refused bequest (`refused-bequest`) | X/T | A subclass overrides methods to throw or no-op | 1.0.0 |
| ✅ | Alternative classes with different interfaces (`alternative-interfaces`, opt-in) | X | 3+ methods with matching parameter and return types under different names in unrelated types; shape stands in for purpose | 1.0.0 |

### Change preventers
| ✓ | Smell | Scope | How to detect | Since |
|---|---|---|---|---|
| ✅ | Divergent change (`divergent-change`, opt-in) | X + git | A file's commits fall into 3+ reasons, approximated by co-changed modules that share no module or import | 1.0.0 |
| ✅ | Shotgun surgery (`shotgun-surgery`, opt-in) | X + git | The file's median commit also changes 6+ hand-written files across 3+ modules | 1.0.0 |
| ✅ | Parallel inheritance hierarchies (`parallel-inheritance`) | X | Subtypes pairing up by name stem | 1.0.0 |

### Dispensables
| ✓ | Smell | Scope | How to detect | Since |
|---|---|---|---|---|
| ✅ | Duplicate code within a file (exact match) | F | `duplicate-block` | 1.0.0 |
| ✅ | Duplicate code across files | X | `duplicate-code`: token-based clone detection with winnowing | 1.0.0 |
| ✅ | Near-duplicates (Type-2/3 clones: renamed identifiers, small edits) (`duplicate-code`) | F/X | Renamed copies and copies with an inserted, deleted, or changed line; near-duplicates are reported with an estimated similarity (`maxGap`, `minSimilarity`) | 1.0.0 |
| ✅ | Dead code: unused private functions, vars, params, imports | F/T | `unused-private-symbol`, `unused-import`, opt-in `unused-parameter`; per file, by name | 1.0.0 |
| ✅ | Unreachable code after `return`/`throw`/`break` (`unreachable-code`) | F | Swift, TS, JS, Python, Go | 1.0.0 |
| ✅ | Speculative generality: protocol/interface with one implementation (opt-in `single-implementation-interface`), unused params (`unused-parameter`); hooks aren't checked | X | Matches your "no single-implementation interfaces" principle | 1.0.0 |
| ✅ | Lazy class: a type that does almost nothing (`lazy-class`, opt-in) | F | No fields and one branch-free method | 1.0.0 |
| ✅ | Data class: only fields, no behavior (`data-class`); classes only, not structs | F | | 1.0.0 |
| ✅ | Commented-out code | F | `commented-out-code` | 1.0.0 |
| ✅ | Excessive or redundant comments (restating the code) | F | Opt-in `redundant-comment`; comment density isn't checked | 1.0.0 |
| ✅ | TODO/FIXME/HACK density | F | `todo-density` | 1.0.0 |

### Couplers
| ✓ | Smell | Scope | How to detect | Since |
|---|---|---|---|---|
| ✅ | High coupling, measured by import count | F | `high-coupling` (a proxy only) | 1.0.0 |
| ✅ | Feature envy (`feature-envy`, opt-in) | T | ≥ 5 data reads of one parameter or local, over twice the method's own member uses; objects told apart by name | 1.0.0 |
| ✅ | Inappropriate intimacy (`inappropriate-intimacy`) | X | Two types each read 2+ of the other's stored fields or `_names`, through values whose type is written or constructed | 1.0.0 |
| ✅ | Message chains / Law of Demeter (`long-message-chain`) | F | | 1.0.0 |
| ✅ | Middle man: a type that mostly just delegates (`middle-man`) | F | ≥ 3 and > half of methods forward | 1.0.0 |
| ✅ | Global mutable state (`global-mutable-state`) | F | | 1.0.0 |

## 4. Object-oriented design metrics (Chidamber–Kemerer and others)

| ✓ | Metric | Scope | Typical limit | Since |
|---|---|---|---|---|
| ✅ | WMC: weighted methods per class (sum of complexity) (`weighted-methods`) | F | Default ≤ 50 | 1.0.0 |
| ✅ | LCOM4: lack of cohesion of methods (`lack-of-cohesion`) | F | 1 is cohesive; more means the type splits into that many groups. Default ≤ 2, Kirby 1. Swift, TS, JS, Python | 1.0.0 |
| ✅ | LCOM1–3 and LCOM-HS variants (`lack-of-cohesion`'s `variant`) | F | | 1.0.0 |
| ✅ | TCC/LCC: tight/loose class cohesion (`class-cohesion`, opt-in) | F | Default TCC ≥ 0.33 | 1.0.0 |
| ✅ | CBO: coupling between objects (types referenced) (`coupling-between-objects`, opt-in) | T | ≤ 10; distinct type names in annotations, heritage, constructor calls, and static access, minus built-ins | 1.0.0 |
| ✅ | RFC: response for a class (`response-for-class`, opt-in) | T | ≤ 50; methods plus distinct callees, by name | 1.0.0 |
| ✅ | DIT: depth of inheritance tree (`deep-inheritance`) | X | Default 4, project classes only | 1.0.0 |
| ✅ | NOC: number of children (opt-in `many-subclasses`) | X | Default ≤ 10 | 1.0.0 |
| ✅ | Fan-in / fan-out per module (`hub-module`, `high-fan-out`) | X | | 1.0.0 |
| ✅ | Instability I = Ce / (Ca + Ce), via the Stable Dependencies Principle (`unstable-dependency`) | X | | 1.0.0 |
| ✅ | Abstractness A and distance from the main sequence \|A + I − 1\| (opt-in `main-sequence-distance`) | X | Default ≤ 0.7 | 1.0.0 |
| ✅ | ATFD (access to foreign data) for god-class detection (`god-class` with `formula: lanza-marinescu`) | T | WMC ≥ 47, ATFD ≥ 6, TCC < 1/3; ATFD counts other objects' properties and getters read, per object name | 1.0.0 |

## 5. SOLID and design principles

| ✓ | Principle | Detectable proxy | Scope | Since |
|---|---|---|---|---|
| ✅ | Single Responsibility | LCOM4 > 1 (`lack-of-cohesion`), god class, many unrelated imports | F | 1.0.0 |
| ✅ | Open/Closed | Type-switches and `is`/`instanceof` chains (`switch-on-type-smell`); the same switch repeated across files (`repeated-switch`) | F | 1.0.0 |
| ✅ | Liskov Substitution | Requirements implemented only to throw or trap; overrides opening with an argument check the parent lacks (`liskov-substitution`; inherited refusals are `refused-bequest`'s) | X/T | 1.0.0 |
| ✅ | Interface Segregation | A 5+ requirement protocol, interface, or abstract class a conformer stubs 3+ and half of (`interface-segregation`) | X | 1.0.0 |
| ✅ | Dependency Inversion | A type keeps an instance it built of a class implementing a project abstraction, or of a `…Service`/`…Client`/`…Repository`, that no initializer takes (`dependency-inversion`, opt-in) | T | 1.0.0 |
| ✅ | DRY | Clone detection: `duplicate-block` within a file, `duplicate-code` across files (exact, renamed, and near-duplicates) | X | 1.0.0 |
| ✅ | YAGNI | Unused params (`unused-parameter`), single-implementation abstractions (`single-implementation-interface`), dead code (`unused-private-symbol`, `unused-export`); unused config keys aren't checked | X | 1.0.0 |
| ✅ | Law of Demeter | Message chains reaching past the first object (`law-of-demeter`, opt-in) | F | 1.0.0 |
| ✅ | Composition over inheritance | Deep DIT (`deep-inheritance`); a fieldless subclass overriding exactly one method (`single-override-subclass`, opt-in) | X | 1.0.0 |
| ✅ | Tell, don't ask | An `if` that reads another object's state and sets that same state in its body (`tell-dont-ask`, opt-in) | T | 1.0.0 |
| ✅ | Command–query separation | A method that changes its own fields and returns a computed value, minus fluent, status-returning, `mutating`, override, caching, and `pop`/`next`-style methods (`command-query-separation`, opt-in) | T | 1.0.0 |

## 6. Architecture and dependencies

| ✓ | Check | Scope | Since |
|---|---|---|---|
| ✅ | Cyclic dependencies between files, modules, and targets (`import-cycle`) | X | 1.0.0 |
| ✅ | Layering rules declared as ordered path globs (`layer-violation`) | X | 1.0.0 |
| ✅ | Forbidden imports per path (custom allow/deny list) (`forbidden-import`) | F | 1.0.0 |
| ✅ | Hub modules (`hub-module`) | X | 1.0.0 |
| ✅ | Unused dependencies in the package manifest (`unused-dependency`: SwiftPM, package.json, go.mod; not Python) | X | 1.0.0 |
| ✅ | Public API surface growth (new public symbols in a diff) (opt-in `public-api-growth`, in `check`) | X + git | 1.0.0 |

## 7. Naming and readability

| ✓ | Check | Scope | Since |
|---|---|---|---|
| ✅ | Naming convention (case style per language) | F | 1.0.0 |
| ✅ | Identifier too short, except loop indices and conventional names (`short-identifier`); Swift, TS, JS | F | 1.0.0 |
| ✅ | Identifier too long (`long-identifier`) | F | 1.0.0 |
| ✅ | Boolean names without `is`/`has`/`should` (`boolean-name-prefix`, opt-in) | F | 1.0.0 |
| ✅ | Negated boolean names (`negated-boolean-name`); Swift, TS, JS | F | 1.0.0 |
| ✅ | Hungarian notation (`hungarian-notation`); Swift, TS, JS | F | 1.0.0 |
| ✅ | Type-in-name suffixes (`userList`, `nameString`) (`type-in-name`) | F | 1.0.0 |
| ✅ | Abbreviations not in an allowlist (`abbreviation`, opt-in) | F | 1.0.0 |
| ✅ | Magic numbers (`magic-number`); Swift, TS, JS, Python, Go | F | 1.0.0 |
| ✅ | Magic strings: literals repeated in a file (`duplicated-string-literal`); Swift, TS, JS | F | 1.0.0 |
| ✅ | Boolean parameters (flag arguments) (`boolean-parameter`); Swift, TS, JS, Python, Go. Initializers are exempt | F | 1.0.0 |
| ✅ | Inconsistent terminology (`fetch`/`get`/`load` mixed in one module) (opt-in `inconsistent-terminology`) | X | 1.0.0 |
| ✅ | Inconsistent file name vs. primary type name (`file-name-mismatch`; Swift, TS, JS) | F | 1.0.0 |

## 8. Documentation

| ✓ | Check | Scope | Since |
|---|---|---|---|
| ✅ | Missing doc comment, by visibility scope | F | 1.0.0 |
| ✅ | Doc doesn't list every parameter, return value, or throw (`incomplete-documentation`) | F | 1.0.0 |
| ✅ | Stale doc: parameter names don't match the signature (`stale-documentation`) | F | 1.0.0 |
| ✅ | Missing file/module header (`missing-file-header`, opt-in) | F | 1.0.0 |
| ✅ | Missing README per package or target (opt-in `missing-readme`) | X | 1.0.0 |

## 9. Error handling and robustness

| ✓ | Check | Scope | Since |
|---|---|---|---|
| ✅ | Python bare `except:` | F | 1.0.0 |
| ✅ | Java broad `catch (Exception)` | F | 1.0.0 |
| ✅ | Go `panic()` and discarded returns | F | 1.0.0 |
| ✅ | Empty catch block (`empty-catch`); Swift, TS, JS, Python (an `except` that only `pass`es) | F | 1.0.0 |
| ✅ | Empty catch block in the remaining languages (`empty-catch`, text-based: Java, C++, PowerShell, C#/Kotlin/PHP/Dart) | F | 1.0.0 |
| ✅ | Swift `try!`, force-unwrap `!`, `as!`, implicitly unwrapped optionals (`force-try`, `force-unwrap`, `force-cast`, `implicitly-unwrapped-optional`) | F | 1.0.0 |
| ✅ | Swift `fatalError` (`swift-fatal-error`) | F | 1.0.0 |
| ✅ | Swift `precondition` (`swift-precondition`, opt-in), and limiting either to library (non-app) code (`libraryOnly`) | F | 1.0.0 |
| ✅ | Swift `try?` that silently discards errors (`swift-discarded-try`) | F | 1.0.0 |
| ✅ | Go `if err != nil { return err }` with no wrapping context (`go-unwrapped-error`, opt-in) | F | 1.0.0 |
| ✅ | Returning `null`/`nil` where an empty collection would do (`null-collection-return`, opt-in; Swift, TS, Python, Java) | T | 1.0.0 |
| ✅ | Error message without context (`generic-error-message`) | F | 1.0.0 |
| ✅ | Resource leaks: file or handle opened with no `defer`/`with`/`using` (`resource-leak`) | F/T | 1.0.0 |

## 10. Concurrency

| ✓ | Check | Scope | Since |
|---|---|---|---|
| ✅ | Swift `@unchecked Sendable` and `nonisolated(unsafe)` (`swift-unchecked-sendable`) | F | 1.0.0 |
| ✅ | `DispatchQueue.main.sync` and `semaphore.wait()` (`swift-main-sync`, `swift-semaphore-wait`) | F | 1.0.0 |
| ✅ | Mutable shared state without a lock or actor (`shared-mutable-state`; Swift and Go by default, TS/JS and Python via `languages`) | T | 1.0.0 |
| ✅ | Fire-and-forget `Task {}` with no cancellation handling (`fire-and-forget-task`, opt-in) | F | 1.0.0 |
| ✅ | Go goroutine without context or a `WaitGroup` (`go-unmanaged-goroutine`) | F | 1.0.0 |
| ⬜ | JS floating promise (missing `await`/`.catch`) | T | backlog |

## 11. Security (OWASP Top 10:2025)

Grouped by [OWASP Top 10:2025](https://owasp.org/Top10/2025/) category. A rule appears under the one category it is mapped to in reports. Static, mostly per-file checks can't prove an application secure: categories that are about runtime behavior or design are only partly detectable, and the table says so instead of shipping a rule that only looks like coverage.

### A01 Broken Access Control (partial: static checks see only data flow into URLs and redirects)

| ✓ | Check | Scope | Since |
|---|---|---|---|
| ✅ | Path traversal: user input joined into a file path (`path-traversal`; same line or a 10-line assignment window) | T | 1.0.0 |
| ✅ | Server-side request forgery: user input in a fetched URL (`ssrf`) | T | 1.2.0 |
| ✅ | Open redirect: user input in a redirect target (`open-redirect`) | T | 1.2.0 |
| ✅ | CORS allowing any origin with credentials (`cors-credentials-any-origin`) | F | 1.2.0 |

### A02 Security Misconfiguration

| ✓ | Check | Scope | Since |
|---|---|---|---|
| ✅ | `http://` in non-local code (`insecure-http-url`); every language | F | 1.0.0 |
| ✅ | Hardcoded IP addresses (`hardcoded-ip`; IPv4 in strings) | F | 1.0.0 |
| ✅ | Debug mode enabled in app config (`debug-mode-enabled`: Flask, Django, Express) | F | 1.2.0 |
| ✅ | CORS allowing any origin (`permissive-cors`) | F | 1.2.0 |
| ✅ | Cookies set without `Secure`/`HttpOnly`/`SameSite` (`insecure-cookie`) | F | 1.2.0 |
| ✅ | XML parser with external entities enabled (`xml-external-entities`) | F | 1.2.0 |

### A03 Software Supply Chain Failures

| ✓ | Check | Scope | Since |
|---|---|---|---|
| ✅ | Unpinned dependency: `*`, `latest`, open ranges, git deps without a rev (`unpinned-dependency`: `package.json`, `Cargo.toml`, `Package.swift`) | X | 1.2.0 |
| ✅ | Manifest without a lockfile (`missing-lockfile`) | X | 1.2.0 |
| ✅ | Download piped into a shell, `curl … \| sh` (`pipe-to-shell`) | F | 1.2.0 |
| ✅ | GitHub Action referenced by tag instead of commit SHA (`unpinned-ci-action`, opt-in) | F | 1.2.0 |

### A04 Cryptographic Failures

| ✓ | Check | Scope | Since |
|---|---|---|---|
| ✅ | Secret-looking strings | F | 1.0.0 |
| ✅ | Weak crypto: MD5, SHA-1, DES, ECB (`weak-crypto`); every language | F | 1.0.0 |
| ✅ | `Math.random` used for tokens or IDs (`insecure-random`; also Python `random`, Go `math/rand`) | T | 1.0.0 |
| ✅ | Disabled TLS verification (`disabled-tls-verification`); every language | F | 1.0.0 |
| ✅ | Hardcoded IV, nonce or salt (`hardcoded-iv`) | F | 1.2.0 |
| ✅ | RSA keys under 2048 bits, EC curves of 192 bits or fewer (`short-crypto-key`) | F | 1.2.0 |

### A05 Injection

| ✓ | Check | Scope | Since |
|---|---|---|---|
| ✅ | Shell `eval`; PowerShell `iex`; plaintext password conversion | F | 1.0.0 |
| ✅ | C `gets`, `strcpy`/`strcat`/`sprintf` | F | 1.0.0 |
| ✅ | SQL `UPDATE`/`DELETE` without `WHERE` | F | 1.0.0 |
| ✅ | SQL built by string concatenation or interpolation (`sql-string-building`); every language | F | 1.0.0 |
| ✅ | Shell command built from variables (`python-shell-injection`, `js-shell-injection`, `go-shell-injection`) | F | 1.0.0 |
| ✅ | Swift `Process` launched through a shell with interpolated input (`swift-shell-injection`; literal interpolation only) | T | 1.0.0 |
| ✅ | JS `eval`/`new Function` (`js-eval`) and `innerHTML`/`dangerouslySetInnerHTML` (`js-raw-html`) | F | 1.0.0 |
| ✅ | Python `eval`/`exec` (`python-eval-exec`) | F | 1.0.0 |
| ✅ | Rust shell command built from formatted input (`rust-shell-injection`) | F | 1.2.0 |
| ✅ | Objective-C `NSTask`/`system` with formatted input (`objc-shell-injection`) | F | 1.2.0 |
| ✅ | Template injection: user input rendered as a template (`template-injection`) | T | 1.2.0 |
| ✅ | NoSQL injection: `$where` or query objects built from input (`nosql-injection`) | F | 1.2.0 |

### A06 Insecure Design (not statically checkable)

Insecure design is about missing threat modeling and controls, which no syntax pattern reveals. Bouncer doesn't claim coverage here.

### A07 Authentication Failures (partial)

| ✓ | Check | Scope | Since |
|---|---|---|---|
| ✅ | JWT with `alg: none` or signature verification disabled (`jwt-verification-disabled`) | F | 1.2.0 |
| ✅ | Secret or token compared with `==` instead of a constant-time comparison (`timing-unsafe-comparison`) | F | 1.2.0 |

### A08 Software or Data Integrity Failures

| ✓ | Check | Scope | Since |
|---|---|---|---|
| ✅ | Unsafe deserialization (`python-unsafe-deserialization`) | F | 1.0.0 |
| ✅ | Unsafe deserialization in every language (`unsafe-deserialization`: Java `ObjectInputStream`, YAML `load`, `NSKeyedUnarchiver` without secure coding) | F | 1.2.0 |

### A09 Security Logging & Alerting Failures

| ✓ | Check | Scope | Since |
|---|---|---|---|
| ✅ | Logging of secrets or PII (`logged-secret`) | T | 1.0.0 |
| ✅ | Security failure caught and swallowed without logging (`unlogged-security-failure`; a proxy on auth and security paths) | T | 1.2.0 |

### A10 Mishandling of Exceptional Conditions

The existing error-handling rules in section 9 (`empty-catch`, `force-try`, swallowed errors) are mapped to A10 in reports.

| ✓ | Check | Scope | Since |
|---|---|---|---|
| ✅ | Fail-open: a catch block that returns success or grants access (`fail-open`) | T | 1.2.0 |
| ✅ | Rust `unwrap()`/`expect()` outside tests (`rust-unwrap`) | F | 1.2.0 |

### Reporting

| ✓ | Check | Scope | Since |
|---|---|---|---|
| ✅ | OWASP category on every security finding (JSON `owasp` field, HTML filter, rule catalog) | F | 1.2.0 |
| ✅ | Bundled `owasp` profile: every security rule as an error | F | 1.2.0 |

## 12. Testing

| ✓ | Check | Scope | Since |
|---|---|---|---|
| ✅ | Line coverage threshold | X (report) | 1.0.0 |
| ⬜ | Branch coverage threshold | X (report) | backlog |
| ⬜ | Coverage on changed lines only (diff coverage) | X + git | backlog |
| ✅ | Source file with no matching test file (`missing-test-file`, opt-in) | X | 1.0.0 |
| ✅ | Test with no assertions (`test-without-assertions`) | F | 1.0.0 |
| ✅ | Disabled, skipped, or focused tests (`skipped-test`); TS/JS, Swift, Python, Go, Java | F | 1.0.0 |
| ✅ | Sleeps or real network or clock calls in tests (`test-sleep`, `test-network-call`; opt-in `test-real-clock`) | F | 1.0.0 |
| ✅ | Test function too long or with too many assertions (`oversized-test`) | F | 1.0.0 |
| ⬜ | Mutation score (would need an external tool) | X | backlog |

## 13. Formatting and hygiene

| ✓ | Check | Scope | Since |
|---|---|---|---|
| ✅ | Trailing whitespace | F | 1.0.0 |
| ✅ | Missing newline at end of file (`missing-final-newline`) | F | 1.0.0 |
| ✅ | Mixed tabs and spaces (`mixed-indentation`) | F | 1.0.0 |
| ✅ | Inconsistent indent width (`inconsistent-indent`) | F | 1.0.0 |
| ✅ | CRLF line endings (`crlf-line-endings`) | F | 1.0.0 |
| ✅ | Multiple consecutive blank lines (`consecutive-blank-lines`) | F | 1.0.0 |
| ✅ | Unsorted or duplicate imports (`duplicate-import`; opt-in `unsorted-imports`, not Go) | F | 1.0.0 |
| ✅ | Debug leftovers: Swift `print`/`dump`/`NSLog` (`swift-debug-print`), JS (`js-console-log`), Python (`python-debug-print`), Go (`go-debug-print`), Java (`java-system-out`) | F | 1.0.0 |
| ✅ | Shell `set -x` left on (`shell-debug-trace`) | F | 1.0.0 |
| ✅ | Debug leftovers in C, C++, and PowerShell (`c-debug-print`, `cpp-debug-print`, `powershell-debug-leftover`; explicit debug markers only) | F | 1.0.0 |

## 14. Process and churn (git-aware)

| ✓ | Check | Scope | Since |
|---|---|---|---|
| ✅ | Hotspots: high churn × high complexity (`hotspot`) | X + git | 1.0.0 |
| ✅ | Bus factor / single-author files (`single-author-file`, opt-in) | X + git | 1.0.0 |
| ✅ | Change coupling: files that always change together (`change-coupling`) | X + git | 1.0.0 |
| ✅ | Oversized commits or diffs (`oversized-change`, staged diff) | git | 1.0.0 |
| ✅ | Complexity or size increased vs. the base branch (`complexity-ratchet`) | X + git | 1.0.0 |

---

## 15. Tooling and user experience

| ✓ | Feature | Notes | Since |
|---|---|---|---|
| ✅ | Console and JSON reports (`--format console\|json`) | | 1.0.0 |
| ✅ | Markdown table and HTML reports (`--format table\|html`), `--output` to write any report to a file | | 1.1.0 |
| ✅ | WSL: Windows path and URL printed for a written report | | 1.1.0 |
| ✅ | License and notice files skipped when picking files to check | | 1.1.0 |
| ✅ | Bundled `kirby` profile (`--profile kirby`) | | 1.0.0 |
| ✅ | Baseline (`bouncer baseline update\|clear`) | | 1.0.0 |
| ✅ | `bouncer configure` with `--set`, `--husky`, `--trust` | | 1.0.0 |
| ✅ | Live progress screen on a terminal: bar, current phase and file, elapsed time (`--progress live`) | stderr only | 1.2.0 |
| ✅ | Non-interactive progress: one line per phase (`--progress plain`); `auto` picks live, plain, or off for agents | | 1.2.0 |
| ✅ | Verbose logs of everything a run does (`--verbose`/`-v`) | config layers, files, analyzers, timings, cache, hooks | 1.2.0 |
| ✅ | Concise end-of-run summary: totals by severity, top rules, top files, elapsed time | | 1.2.0 |
| ✅ | WSL: the `Open:` link is the Windows URL, so clicking it opens in a Windows browser | | 1.2.0 |
| ✅ | HTML report loads lazily, 100 rows at a time, with a compact row encoding | built for millions of findings | 1.2.0 |
| ✅ | HTML report: visible column sort state, keyboard-operable headers | | 1.2.0 |
| ✅ | HTML report: rule panel to hide noisy rules, with counts and "Copy as `.bouncer`" | | 1.2.0 |
| ✅ | Interactive setup (`bouncer configure`): starting point, output, coverage, contested thresholds, where to save | | 1.2.0 |
| ✅ | `"profile"` key in `.bouncer` selects a profile | documented before, but ignored | 1.2.0 |
| ✅ | User profiles: repo `.bouncer-profiles/` (shareable) and global `~/.bouncer-profiles/` | | 1.2.0 |
| ✅ | `bouncer profile list\|show\|create\|set-default\|delete` | | 1.2.0 |
| ✅ | Landing page at the site root, with the bouncer mascot | | 1.2.0 |
| ✅ | Saved runs: `review` saves its result to `.bouncer-cache/` and re-analyzes only changed files next time (`--from-last-run`, `--full`, `--no-save-run`, `output.saveRun`) | identical findings to a full run | 1.3.0 |
| ⬜ | FAQ on the landing page | | backlog |

## 16. Integrations

| ✓ | Feature | Notes | Since |
|---|---|---|---|
| ✅ | Husky pre-commit hook (`bouncer configure --husky`) | | 1.0.0 |
| ✅ | Agent self-check (`bouncer check --files`/`--stdin`) | | 1.0.0 |
| ✅ | Xcode coverage from `.xcresult` (`xcrun xccov`) | macOS | 1.0.0 |
| ✅ | Xcode diagnostics output (`--format xcode`), shown inline in Xcode | | 1.2.0 |
| ✅ | `bouncer xcode install\|uninstall`: adds a Run Script build phase to `.xcodeproj` targets | macOS | 1.2.0 |
| ✅ | SwiftPM build-tool and command plugin, prebuilt binary, for Swift without an Xcode project | separate plugin package | 1.2.0 |
| ✅ | Token-efficient agent output (`--format agent`, `--group-by file\|rule`) | grouped, relative paths, repeated messages dropped | 1.3.0 |
| ✅ | Report filters and paging (`--rule`, `--path`, `--min-severity`, `--limit`, `--offset`); exit code follows the filtered set | | 1.3.0 |
| ✅ | Summary-only output (`--summary`), with a hint when one rule is over half the findings | | 1.3.0 |
| ✅ | Review only files changed since a git ref (`review --changed-since REF`) | project rules still see the whole graph | 1.3.0 |
| ⬜ | MCP server (`bouncer mcp`): summary-first tools, paged drill-down, next fix batch, verify, check | designed, not built yet | planned 1.3 |
| ⬜ | Agent skills (`SKILL.md`, `AGENTS.md` snippet) for the scan, fix, verify loop | | planned 1.3 |
| ⬜ | Symbol-level Swift analysis from the compiler's index store | deferred until there's demand | backlog |

## 17. Languages

| ✓ | Language | Analysis | Since |
|---|---|---|---|
| ✅ | Swift | SwiftSyntax | 1.0.0 |
| ✅ | TypeScript (including TSX) | tree-sitter | 1.0.0 |
| ✅ | JavaScript (including JSX) | tree-sitter | 1.0.0 |
| ✅ | Python | tree-sitter | 1.0.0 |
| ✅ | Go | tree-sitter | 1.0.0 |
| ✅ | zsh, bash, PowerShell, C, C++, Java, SQL, and any other file | heuristic | 1.0.0 |
| ✅ | Objective-C (`.m`, `.mm`, ObjC `.h` by content), with Swift/ObjC import edges | tree-sitter | 1.2.0 |
| ✅ | Rust, with `mod`/`use` and Cargo workspace edges | tree-sitter | 1.2.0 |

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
