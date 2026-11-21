/// A category of the OWASP Top 10:2025, the list of the most critical web application security risks.
///
/// Reports tag each security finding with the one category its rule is mapped to, so findings can be filtered
/// and counted by risk. A06 (Insecure Design) has no rules: no syntax pattern reveals a missing design control.
public enum OWASPCategory: String, CaseIterable, Sendable, Codable {
    case brokenAccessControl = "A01:2025"
    case securityMisconfiguration = "A02:2025"
    case softwareSupplyChainFailures = "A03:2025"
    case cryptographicFailures = "A04:2025"
    case injection = "A05:2025"
    case insecureDesign = "A06:2025"
    case authenticationFailures = "A07:2025"
    case softwareOrDataIntegrityFailures = "A08:2025"
    case securityLoggingAndAlertingFailures = "A09:2025"
    case mishandlingOfExceptionalConditions = "A10:2025"

    /// The category's title, as OWASP names it.
    public var title: String {
        Self.table.first { $0.category == self }?.title ?? rawValue
    }

    /// The category a rule's findings belong to.
    ///
    /// - Parameter ruleID: The rule's ID.
    /// - Returns: Its category, or `nil` for a rule that isn't about security.
    public static func category(forRule ruleID: String) -> OWASPCategory? {
        byRule[ruleID]
    }

    /// Every rule ID Bouncer maps to a category. Rules planned but not built yet are listed too, so a rule
    /// is tagged the moment it lands; an ID with no rule behind it is never looked up.
    static let byRule: [String: OWASPCategory] = Dictionary(
        uniqueKeysWithValues: table.flatMap { row in row.rules.map { ($0, row.category) } }
    )

    /// Each category's title and the rule IDs in it.
    private static let table: [(category: OWASPCategory, title: String, rules: [String])] = [
        (.brokenAccessControl, "Broken Access Control", [
            "path-traversal", "ssrf", "open-redirect", "cors-credentials-any-origin"
        ]),
        (.securityMisconfiguration, "Security Misconfiguration", [
            "insecure-http-url", "hardcoded-ip", "debug-mode-enabled", "permissive-cors", "insecure-cookie",
            "xml-external-entities"
        ]),
        (.softwareSupplyChainFailures, "Software Supply Chain Failures", [
            "unpinned-dependency", "missing-lockfile", "pipe-to-shell", "unpinned-ci-action"
        ]),
        (.cryptographicFailures, "Cryptographic Failures", [
            "secret-looking-pattern", "weak-crypto", "insecure-random", "disabled-tls-verification",
            "hardcoded-iv", "short-crypto-key"
        ]),
        (.injection, "Injection", [
            "sql-string-building", "sql-missing-where", "shell-eval-usage", "powershell-invoke-expression",
            "c-gets-usage", "c-unsafe-string-function", "python-shell-injection", "js-shell-injection",
            "go-shell-injection", "swift-shell-injection", "rust-shell-injection", "objc-shell-injection",
            "js-eval", "js-raw-html", "python-eval-exec", "template-injection", "nosql-injection"
        ]),
        (.insecureDesign, "Insecure Design", []),
        (.authenticationFailures, "Authentication Failures", [
            "powershell-plaintext-password", "jwt-verification-disabled", "timing-unsafe-comparison"
        ]),
        (.softwareOrDataIntegrityFailures, "Software or Data Integrity Failures", [
            "python-unsafe-deserialization", "unsafe-deserialization"
        ]),
        (.securityLoggingAndAlertingFailures, "Security Logging and Alerting Failures", [
            "logged-secret", "unlogged-security-failure"
        ]),
        (.mishandlingOfExceptionalConditions, "Mishandling of Exceptional Conditions", [
            "empty-catch", "swift-discarded-try", "python-bare-except", "java-generic-exception-catch",
            "rust-unwrap", "fail-open"
        ])
    ]
}
