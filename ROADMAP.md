# Roadmap

Every check below is meant to become part of Bouncer eventually. ✅ = Bouncer implements it today. ⬜ = not implemented yet.
The **Scope** column says what analysis a check needs:
- **F**: one file at a time. Fits Bouncer's current rule model.
- **X**: cross-file. Needs a repo-wide index, which Bouncer doesn't have yet.
- **T**: type or semantic info, which needs a real AST.

---

## 0. What's enforced today

**This repo's `.bouncer`:** `long-function` ≤ 10 lines (error) and `missing-documentation` with scope `all` (error); `swift-debug-print` is off, since a CLI writes its output with `print`. Excludes `Tests/**`, `**/*.md`, `.build/**`, and the vendored `Sources/CTreeSitter*` grammars.

**Kirby profile:** coverage ≥ 90%, function ≤ 10 lines, cyclomatic complexity ≤ 6, cognitive complexity ≤ 8, ≤ 3 parameters, ≤ 3 returns, nesting ≤ 3, ≤ 8 imports, ≤ 3 switch branches, naming, docs and god-class checks, and every single-location smell rule (`force-unwrap`, `force-try`, `force-cast`, `implicitly-unwrapped-optional`, `non-null-assertion`, `explicit-any`, `nested-ternary`, `empty-catch`, `unreachable-code`, `magic-number`), all as errors.

**Defaults (warnings):** file ≤ 500 lines, function ≤ 40 lines, nesting ≤ 16 by indentation, line ≤ 120 chars, ≤ 5 TODO markers per 100 lines, no repeated 6-line block, complexity ≤ 10, ≤ 15 imports, ≤ 6 switch branches, god-class at ≤ 20 members and ≤ 10 imports, coverage ≥ 80% (taken from the README example). On Swift, TypeScript and JavaScript also: ≤ 5 parameters, ≤ 4 returns, cognitive complexity ≤ 15, control-flow nesting ≤ 4.

**Language support:** TypeScript (primary, including TSX), JavaScript (including JSX) and Swift get every check marked ✅ below unless a row says otherwise. Python and Go are parsed too, but don't yet get the function-shape and single-location rules added for TS/JS/Swift. Everything else is heuristic.

### 0.1 TypeScript type safety

| ✓ | Check | Scope | Notes |
|---|---|---|---|
| ✅ | Explicit `any` (`explicit-any`) | F | |
| ✅ | Non-null assertion `x!` (`non-null-assertion`) | F | |
| ✅ | `@ts-ignore`/`@ts-nocheck`/`@ts-expect-error` with no reason (`ts-ignore-without-reason`) | F | |
| ✅ | Double cast `as unknown as T` (`ts-double-cast`) | F | |
| ✅ | `var` (`js-var`) | F | |
| ⬜ | Floating promise (missing `await`/`.catch`) | T | Needs type information; see section 10 |
| ⬜ | `enum` where a union type would do | F | Style preference; would be opt-in |
| ⬜ | Unused exports | X | |

---

## 1. Size and length

| ✓ | Check | Scope | Notes |
|---|---|---|---|
| ✅ | Long function (`long-function`) | F | |
| ✅ | Long file (`file-length`) | F | |
| ✅ | Long line (`long-lines`) | F | |
| ✅ | Long parameter list (`long-parameter-list`) | F | Default 5, Kirby 3. Swift, TS, JS |
| ⬜ | Large class: line count per type | F | `god-class` counts members, not lines |
| ⬜ | Too many methods per type | F | |
| ⬜ | Too many fields / stored properties per type | F | |
| ⬜ | Too many types per file | F | One primary type per file |
| ✅ | Too many return statements per function (`too-many-returns`) | F | Default 4, Kirby 3. Swift, TS, JS |
| ⬜ | Long lambda/closure body | F | |
| ⬜ | Long boolean expression (number of `&&`/`\|\|` operands) | F | |
| ⬜ | Long method chain (train wreck) | F | Also a Law of Demeter signal |
| ⬜ | Too many local variables | F | |
| ⬜ | Too many generic parameters | F | |

## 2. Complexity

| ✓ | Check | Scope | Notes |
|---|---|---|---|
| ✅ | Cyclomatic complexity | F | Exact for Swift, heuristic elsewhere |
| ✅ | Deep nesting by indentation (`deep-nesting`) | F | |
| ✅ | Cognitive complexity, SonarSource-style (`cognitive-complexity`) | F | Default 15, Kirby 8. Swift, TS, JS |
| ✅ | Nesting by control-flow depth, not indentation (`nesting-depth`) | T | Default 4, Kirby 3. Swift, TS, JS |
| ⬜ | NPath complexity | F | Number of acyclic execution paths |
| ⬜ | Halstead volume / difficulty / effort | F | |
| ⬜ | Maintainability Index | F | Combines Halstead, cyclomatic and LOC |
| ✅ | Nested ternaries (`nested-ternary`) | F | Swift, TS, JS |
| ⬜ | Arrow code: deep `if` pyramids; suggest guard clauses | F | |
| ⬜ | `else` after `return`/`throw` | F | |
| ⬜ | Too many `break`/`continue` in a loop | F | |
| ⬜ | Recursion without an obvious base case | T | |

## 3. Classic code smells (Fowler, *Refactoring*)

### Bloaters
| ✓ | Smell | Scope | How to detect |
|---|---|---|---|
| ✅ | Large class / god class | F | `god-class` (Swift, TS, JS, Python) |
| ✅ | Long method | F | `long-function` |
| ✅ | Long parameter list | F | `long-parameter-list` |
| ⬜ | Primitive obsession | T | Many `String`/`Int` params; stringly-typed IDs, money, dates |
| ⬜ | Data clumps | X | The same 3+ params or fields appearing together repeatedly |

### Object-orientation abusers
| ✓ | Smell | Scope | How to detect |
|---|---|---|---|
| ✅ | Switch statements on a type tag | F | `switch-on-type-smell` |
| ⬜ | Repeated switches on the same discriminator | X | The same `switch x.kind` in several places |
| ⬜ | Type-checking chains (`is`/`as?`/`instanceof`/`isinstance`) | F | Replace with polymorphism |
| ⬜ | Temporary field | T | A field set or used in only one method path |
| ⬜ | Refused bequest | X/T | A subclass overrides methods to throw or no-op |
| ⬜ | Alternative classes with different interfaces | X | |

### Change preventers
| ✓ | Smell | Scope | How to detect |
|---|---|---|---|
| ⬜ | Divergent change | X + git | One file changes for many unrelated reasons (churn by commit topic) |
| ⬜ | Shotgun surgery | X + git | One change touches many files (co-change analysis) |
| ⬜ | Parallel inheritance hierarchies | X | |

### Dispensables
| ✓ | Smell | Scope | How to detect |
|---|---|---|---|
| ✅ | Duplicate code within a file (exact match) | F | `duplicate-block` |
| ⬜ | Duplicate code across files | X | Token-based clone detection |
| ⬜ | Near-duplicates (Type-2/3 clones: renamed identifiers, small edits) | F/X | Normalize identifiers and literals before comparing |
| ⬜ | Dead code: unused private functions, vars, params, imports | F/T | |
| ✅ | Unreachable code after `return`/`throw`/`break` (`unreachable-code`) | F | Swift, TS, JS |
| ⬜ | Speculative generality: protocol/interface with one implementation, unused params, hooks | X | Matches your "no single-implementation interfaces" principle |
| ⬜ | Lazy class: a type that does almost nothing | F | Very few members |
| ⬜ | Data class: only fields and accessors, no behavior | F | |
| ⬜ | Commented-out code | F | Comment lines that parse as code |
| ⬜ | Excessive or redundant comments (restating the code) | F | |
| ✅ | TODO/FIXME/HACK density | F | `todo-density` |

### Couplers
| ✓ | Smell | Scope | How to detect |
|---|---|---|---|
| ✅ | High coupling, measured by import count | F | `high-coupling` (a proxy only) |
| ⬜ | Feature envy | T | A method uses another type's members more than its own |
| ⬜ | Inappropriate intimacy | X | Two types access each other's internals |
| ⬜ | Message chains / Law of Demeter (`a.b().c().d()`) | F | |
| ⬜ | Middle man: a type that mostly just delegates | F | |
| ⬜ | Global mutable state / singletons | F | `static var`, `shared`, module-level mutables |

## 4. Object-oriented design metrics (Chidamber–Kemerer and others)

| ✓ | Metric | Scope | Typical limit |
|---|---|---|---|
| ⬜ | WMC: weighted methods per class (sum of complexity) | F | ≤ 20–50 |
| ⬜ | LCOM / LCOM4: lack of cohesion of methods | F | LCOM4 should be 1; > 1 means the type should be split |
| ⬜ | TCC/LCC: tight/loose class cohesion | F | |
| ⬜ | CBO: coupling between objects (types referenced) | T | ≤ 5–10 |
| ⬜ | RFC: response for a class | T | |
| ⬜ | DIT: depth of inheritance tree | X | ≤ 3–5 |
| ⬜ | NOC: number of children | X | |
| ⬜ | Fan-in / fan-out per module | X | |
| ⬜ | Instability I = Ce / (Ca + Ce) | X | Robert Martin's package metrics |
| ⬜ | Abstractness A and distance from the main sequence \|A + I − 1\| | X | |
| ⬜ | ATFD (access to foreign data) for god-class detection | T | The Lanza–Marinescu god-class formula: WMC + ATFD + TCC |

## 5. SOLID and design principles

| ✓ | Principle | Detectable proxy | Scope |
|---|---|---|---|
| ⬜ | Single Responsibility | LCOM4 > 1, many unrelated imports, god class | F |
| ⬜ | Open/Closed | Type-switches, `is`/`instanceof` chains | F |
| ⬜ | Liskov Substitution | Overrides that throw "not supported", or narrow preconditions | X/T |
| ⬜ | Interface Segregation | Protocols with many methods; conformers stubbing most of them | X |
| ⬜ | Dependency Inversion | Concrete types instantiated inside business logic; no injected protocol | T |
| ⬜ | DRY | Clone detection (see section 3) | X |
| ⬜ | YAGNI | Unused params, single-implementation abstractions, unused config | X |
| ⬜ | Law of Demeter | Message chains | F |
| ⬜ | Composition over inheritance | Deep DIT; subclass that only overrides one method | X |
| ⬜ | Tell, don't ask | Getter followed by a decision on another object's state | T |
| ⬜ | Command–query separation | Function both mutates and returns a value | T |

## 6. Architecture and dependencies

| ✓ | Check | Scope |
|---|---|---|
| ⬜ | Cyclic dependencies between modules/targets | X |
| ⬜ | Layering rules (e.g. Core must not import CLI) | X. Could be a config-declared allowlist |
| ⬜ | Forbidden imports per path (custom allow/deny list) | F |
| ⬜ | Hub modules: a module everything depends on | X |
| ⬜ | Unused dependencies in the package manifest | X |
| ⬜ | Public API surface growth (new public symbols in a diff) | X + git |

## 7. Naming and readability

| ✓ | Check | Scope |
|---|---|---|
| ✅ | Naming convention (case style per language) | F |
| ⬜ | Identifier too short (`x`, `tmp`), except loop indices | F |
| ⬜ | Identifier too long | F |
| ⬜ | Boolean names without `is`/`has`/`should` | F |
| ⬜ | Negated booleans (`isNotEnabled`, `!notReady`) | F |
| ⬜ | Hungarian notation or type-in-name (`strName`, `userList`) | F |
| ⬜ | Abbreviations not in an allowlist | F |
| ✅ | Magic numbers (`magic-number`); Swift, TS, JS | F |
| ⬜ | Magic strings | F |
| ⬜ | Boolean parameters (flag arguments) | F |
| ⬜ | Inconsistent terminology (`fetch`/`get`/`load` mixed in one module) | X |
| ⬜ | Inconsistent file name vs. primary type name | F |

## 8. Documentation

| ✓ | Check | Scope |
|---|---|---|
| ✅ | Missing doc comment, by visibility scope | F |
| ⬜ | Doc doesn't list every parameter, return value, or throw | F |
| ⬜ | Stale doc: parameter names don't match the signature | F |
| ⬜ | Missing file/module header | F |
| ⬜ | Missing README per package or target | X |

## 9. Error handling and robustness

| ✓ | Check | Scope |
|---|---|---|
| ✅ | Python bare `except:` | F |
| ✅ | Java broad `catch (Exception)` | F |
| ✅ | Go `panic()` and discarded returns | F |
| ✅ | Empty catch block (`empty-catch`); Swift, TS, JS | F |
| ⬜ | Empty catch block in the remaining languages | F |
| ✅ | Swift `try!`, force-unwrap `!`, `as!`, implicitly unwrapped optionals (`force-try`, `force-unwrap`, `force-cast`, `implicitly-unwrapped-optional`) | F |
| ✅ | Swift `fatalError` (`swift-fatal-error`) | F |
| ⬜ | Swift `precondition`, and limiting either to library (non-app) code | F |
| ✅ | Swift `try?` that silently discards errors (`swift-discarded-try`) | F |
| ⬜ | Go `if err != nil { return err }` with no wrapping context | F |
| ⬜ | Returning `null`/`nil` where an empty collection would do | T |
| ⬜ | Error message without context | F |
| ⬜ | Resource leaks: file or handle opened with no `defer`/`with`/`using` | F/T |

## 10. Concurrency

| ✓ | Check | Scope |
|---|---|---|
| ✅ | Swift `@unchecked Sendable` and `nonisolated(unsafe)` (`swift-unchecked-sendable`) | F |
| ⬜ | `DispatchQueue.main.sync` and `semaphore.wait()` on async paths | F |
| ⬜ | Mutable shared state without a lock or actor | T |
| ⬜ | Fire-and-forget `Task {}` with no cancellation handling | F |
| ⬜ | Go goroutine without context or a `WaitGroup` | F |
| ⬜ | JS floating promise (missing `await`/`.catch`) | T |

## 11. Security

| ✓ | Check | Scope |
|---|---|---|
| ✅ | Secret-looking strings | F |
| ✅ | Shell `eval`; PowerShell `iex`; plaintext password conversion | F |
| ✅ | C `gets`, `strcpy`/`strcat`/`sprintf` | F |
| ✅ | SQL `UPDATE`/`DELETE` without `WHERE` | F |
| ⬜ | SQL built by string concatenation or interpolation (injection) | F |
| ⬜ | Shell command built from variables (`Process`, `subprocess(shell=True)`, `exec`) | F |
| ⬜ | Weak crypto (MD5, SHA1, DES, ECB, `Math.random` for tokens) | F |
| ⬜ | Hardcoded URLs or IPs; `http://` in non-local code | F |
| ⬜ | Disabled TLS verification | F |
| ⬜ | Path traversal: user input joined into a file path | T |
| ⬜ | Unsafe deserialization (`pickle.loads`, `yaml.load`) | F |
| ✅ | JS `eval`/`new Function` (`js-eval`) and `innerHTML`/`dangerouslySetInnerHTML` (`js-raw-html`) | F |
| ⬜ | Python `eval`/`exec` | F |
| ⬜ | Logging of secrets or PII | T |

## 12. Testing

| ✓ | Check | Scope |
|---|---|---|
| ✅ | Line coverage threshold | X (report) |
| ⬜ | Branch coverage threshold | X (report) |
| ⬜ | Coverage on changed lines only (diff coverage) | X + git |
| ⬜ | Source file with no matching test file | X |
| ⬜ | Test with no assertions | F |
| ⬜ | Disabled or skipped tests | F |
| ⬜ | Sleeps or real network or clock calls in tests (flakiness) | F |
| ⬜ | Test function too long or with too many assertions | F |
| ⬜ | Mutation score (would need an external tool) | X |

## 13. Formatting and hygiene

| ✓ | Check | Scope |
|---|---|---|
| ✅ | Trailing whitespace | F |
| ⬜ | Missing newline at end of file | F |
| ⬜ | Mixed tabs and spaces / inconsistent indent width | F |
| ⬜ | CRLF line endings | F |
| ⬜ | Multiple consecutive blank lines | F |
| ⬜ | Unsorted or duplicate imports | F |
| ✅ | Debug leftovers in Swift (`swift-debug-print`) and JS (`js-console-log`) | F |
| ⬜ | Debug leftovers in the remaining languages (`NSLog`, `fmt.Println`, Python `print`) | F |

## 14. Process and churn (git-aware)

| ✓ | Check | Scope |
|---|---|---|
| ⬜ | Hotspots: high churn × high complexity | X + git |
| ⬜ | Bus factor / single-author files | X + git |
| ⬜ | Change coupling: files that always change together | X + git |
| ⬜ | Oversized commits or diffs | git |
| ⬜ | Complexity or size increased vs. the base branch (ratchet) | X + git |

---

## Notes on the current implementation

- **Coverage gap:** `god-class` doesn't run on Go (no classes). The function-shape and single-location rules run only on Swift, TypeScript and JavaScript; Python and Go have parse trees, so extending them means writing a `TreeSitterQualitySpec` for each, with no new rule code.
- **Precision gap:** duplicate detection is exact-match and intra-file only, and coupling is an import count. Both are labelled as proxies in the docs.
- **Architecture constraint:** every ⬜ marked **X** needs a repo-wide analysis pass, because the rule engine sees only one file at a time. Adding that pass is the main structural change before the cross-file smells (clones, data clumps, cycles, DIT, shotgun surgery) become possible.
- **Easiest wins:** many remaining **F** items are a few lines of `LanguageProfiles` pattern data, such as weak crypto, missing EOF newline, and the remaining debug prints. Shared AST rules live once in `DeclarationFindings`: a new per-function metric is one `MetricRule` entry, and a new single-location smell is one `MarkerKind` case plus where each parser detects it. LCOM4 and boolean flag parameters fit this model next.
