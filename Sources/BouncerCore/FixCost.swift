/// How much work fixing a rule's finding takes, which decides where an agent's work order puts it.
public enum FixCost: String, CaseIterable, Sendable, Codable {
    /// A local fix that doesn't change structure, such as a force unwrap or a missing doc comment.
    case mechanical
    /// The code has to be restructured, such as a long function or a duplicated block.
    case refactor

    /// What the cost means, in a few words, such as `a local fix`.
    public var summary: String {
        switch self {
        case .mechanical: "a local fix"
        case .refactor: "needs restructuring"
        }
    }

    /// Rule IDs Bouncer reports that the rule catalog doesn't document, so a test can tell them from typos.
    static let uncataloguedRuleIDs: Set<String> = ["coverage-threshold"]

    /// The fix cost of a rule's findings.
    ///
    /// - Parameter ruleID: The rule's ID.
    /// - Returns: Its cost, or `nil` for an ID with no tag.
    public static func cost(forRule ruleID: String) -> FixCost? {
        byRule[ruleID]
    }

    /// Every rule ID with a tag, sorted.
    public static var taggedRuleIDs: [String] {
        byRule.keys.sorted()
    }

    /// Each tagged rule's cost. An ID listed twice keeps its first cost; a test fails on any such ID.
    static let byRule: [String: FixCost] = Dictionary(
        table.flatMap { row in row.rules.map { ($0, row.cost) } }, uniquingKeysWith: { first, _ in first }
    )

    /// The rule IDs at each cost, sorted within each.
    static let table: [(cost: FixCost, rules: [String])] = [
        (.mechanical, [
            "abbreviation", "boolean-name-prefix", "c-debug-print", "c-gets-usage", "c-unsafe-string-function",
            "commented-out-code", "consecutive-blank-lines", "cors-credentials-any-origin", "cpp-debug-print",
            "cpp-raw-new-delete", "cpp-using-namespace-std", "crlf-line-endings", "debug-mode-enabled",
            "disabled-tls-verification", "duplicate-import", "duplicated-string-literal", "else-after-return",
            "empty-catch", "explicit-any", "fail-open", "file-name-mismatch", "force-cast", "force-try", "force-unwrap",
            "generic-error-message", "go-debug-print", "go-discarded-return-value", "go-panic-usage",
            "go-shell-injection", "go-unwrapped-error", "hardcoded-ip", "hardcoded-iv", "hungarian-notation",
            "implicitly-unwrapped-optional", "incomplete-documentation", "inconsistent-indent",
            "inconsistent-terminology", "insecure-cookie", "insecure-http-url", "insecure-random",
            "java-generic-exception-catch", "java-print-stack-trace", "java-system-out", "js-console-log", "js-eval",
            "js-loose-equality", "js-raw-html", "js-shell-injection", "js-var", "jwt-verification-disabled",
            "logged-secret", "long-boolean-expression", "long-identifier", "long-lines", "magic-number",
            "missing-documentation", "missing-file-header", "missing-final-newline", "missing-lockfile",
            "missing-readme", "mixed-indentation", "naming-convention", "negated-boolean-name", "nested-ternary",
            "non-null-assertion", "nosql-injection", "null-collection-return", "objc-debug-log", "objc-shell-injection",
            "open-redirect", "path-traversal", "permissive-cors", "php-debug-output", "php-error-suppression",
            "php-eval", "php-extract", "php-loose-comparison", "php-shell-injection", "php-weak-password-hash",
            "pipe-to-shell", "powershell-debug-leftover", "powershell-invoke-expression",
            "powershell-plaintext-password", "public-api-growth", "python-bare-except", "python-debug-print",
            "python-eval-exec", "python-mutable-default-arg", "python-shell-injection", "python-unsafe-deserialization",
            "recursion-without-base-case", "redundant-comment", "resource-leak", "rust-debug-print", "rust-panic",
            "rust-shell-injection", "rust-todo-macro", "rust-unsafe-without-safety-comment", "rust-unwrap",
            "secret-looking-pattern", "shell-debug-trace", "shell-eval-usage", "shell-unquoted-variable",
            "short-crypto-key", "short-identifier", "skipped-test", "sql-missing-where", "sql-select-star",
            "sql-string-building", "ssrf", "stale-documentation", "swift-debug-print", "swift-discarded-try",
            "swift-fatal-error", "swift-precondition", "swift-shell-injection", "template-injection", "test-sleep",
            "test-without-assertions", "timing-unsafe-comparison", "todo-density", "trailing-whitespace",
            "ts-double-cast", "ts-ignore-without-reason", "ts-prefer-union-type", "type-in-name",
            "unlogged-security-failure", "unpinned-ci-action", "unpinned-dependency", "unreachable-code",
            "unsafe-deserialization", "unsorted-imports", "unused-dependency", "unused-export", "unused-import",
            "unused-parameter", "unused-private-symbol", "unused-public-symbol", "weak-crypto", "xml-external-entities"
        ]),
        (.refactor, [
            "alternative-interfaces", "arrow-code", "boolean-parameter", "change-coupling", "class-cohesion",
            "cognitive-complexity", "command-query-separation", "complexity-ratchet", "coupling-between-objects",
            "coverage-threshold", "cyclomatic-complexity", "data-class", "data-clump", "deep-inheritance",
            "deep-nesting", "dependency-inversion", "divergent-change", "duplicate-block", "duplicate-code",
            "feature-envy", "file-length", "fire-and-forget-task", "forbidden-import", "global-mutable-state",
            "go-unmanaged-goroutine", "god-class", "halstead-complexity", "high-coupling", "high-fan-out", "hotspot",
            "hub-module", "import-cycle", "inappropriate-intimacy", "interface-segregation", "lack-of-cohesion",
            "large-type", "law-of-demeter", "layer-violation", "lazy-class", "liskov-substitution", "long-closure",
            "long-function", "long-message-chain", "long-parameter-list", "main-sequence-distance",
            "maintainability-index", "many-subclasses", "middle-man", "missing-test-file", "nesting-depth",
            "npath-complexity", "oversized-change", "oversized-test", "parallel-inheritance", "primitive-obsession",
            "refused-bequest", "repeated-switch", "response-for-class", "shared-mutable-state", "shotgun-surgery",
            "single-author-file", "single-implementation-interface", "single-override-subclass", "swift-main-sync",
            "swift-semaphore-wait", "swift-unchecked-sendable", "switch-on-type-smell", "tell-dont-ask",
            "temporary-field", "test-network-call", "test-real-clock", "too-many-fields", "too-many-generic-parameters",
            "too-many-locals", "too-many-loop-jumps", "too-many-methods", "too-many-returns", "too-many-types",
            "type-check-chain", "unstable-dependency", "weighted-methods"
        ])
    ]
}
