# ``BouncerCore``

A configurable, multi-language coding-standards and code-smell checker.

## Overview

Bouncer works on codebases in any language. It analyzes Swift with a real syntax tree (via SwiftSyntax) and
TypeScript (including TSX), JavaScript (including JSX), Objective-C, Rust, PHP, Python, and Go with real parse trees
(via tree-sitter). zsh, bash, PowerShell, C, C++, Java, and SQL get dedicated heuristics, and anything unrecognized
still gets a best-effort pass rather than being skipped outright. All of it runs
through the same dependency-injected rule engine, whether you're calling it from a Husky
pre-commit hook, running an ad-hoc audit of an unfamiliar codebase, or having a coding agent
check its own edits before committing them.

`BouncerCore` is the module every other part of Bouncer builds on: the `Rule` and
`LanguageAnalyzer` protocols an analyzer implements, the `Finding` and `Severity` types a rule
reports, and the `AnalysisEngine` that ties a file provider, a set of analyzers, a baseline, and
optional coverage checking into one run. If you're extending Bouncer with a new rule or a new
language, this is the module whose types you'll be working with.

For everyday usage (the `bouncer` command itself), see the articles below rather than the
symbol reference: `BouncerCore` documents the engine's extensibility surface, not the CLI.

## Topics

### Using Bouncer

- <doc:GettingStarted>
- <doc:Configuration>
- <doc:Profiles>
- <doc:XcodeAndSwiftPackages>
- <doc:RuleCatalog>
- <doc:RuleExamples>
- <doc:KirbyMode>
- <doc:Security>
- <doc:Hooks>
- <doc:Agents>

### The Analysis Engine

- ``AnalysisEngine``
- ``AnalysisContext``
- ``AnalysisResult``
- ``SourceFile``
- ``Language``

### Writing a Rule

- ``Rule``
- ``RuleRegistry``
- ``RuleSettings``
- ``RuleParameters``
- ``RuleParameterValue``

### Writing a Language Analyzer

- ``LanguageAnalyzer``
- ``TargetFileProvider``
- ``FileContentsProvider``
- ``RecursiveFileWalker``
- ``HiddenCIFiles``
- ``ExplicitFileListProvider``

### Findings and Severity

- ``Finding``
- ``Severity``

### Coverage

- ``CoverageProvider``
- ``CoverageReport``
- ``CoverageThresholdChecker``

### Baseline

- ``Baseline``
- ``BaselineStore``
- ``FindingFingerprint``

### Reporting

- ``Reporter``
- ``OutputVerbosity``
