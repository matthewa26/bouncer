/// Rust's profile: `//` comments, `fn` and `match` for the heuristic fallback, and the line patterns for Rust's
/// risky APIs that the cross-language rules match by text.
///
/// Rust's own smells that depend on context (test code, safety comments, call chains) are tree checks in the
/// tree-sitter analyzer's `RustSmells` instead.
extension LanguageProfiles {
    /// Rust's bundled profile.
    static let rust = LanguageProfile(
        lineCommentPrefixes: ["//"],
        functionStartPattern: #"^\s*(pub(\([^)]*\))?\s+)?((const|async|unsafe|extern\s+"[^"]*")\s+)*fn\s+\w+"#,
        switchStartPattern: #"^\s*match\b.*\{\s*$"#,
        switchBranchPattern: #"^\s*[^/].*=>"#,
        importLinePattern: #"^\s*(pub(\([^)]*\))?\s+)?use\s+"#,
        namingRules: rustNamingRules,
        extraPatternRules: rustPatterns
    )

    /// snake_case functions (a raw identifier's `r#` allowed) and CamelCase types, for the heuristic fallback.
    private static let rustNamingRules = [
        NamingRule(
            declarationPattern: #"\bfn\s+((?:r#)?[A-Za-z_]\w*)"#,
            expectedIdentifierPattern: #"^(r#)?_*[a-z][a-z0-9_]*$"#, kindLabel: "function"
        ),
        NamingRule(
            declarationPattern: #"\b(?:struct|enum|trait|union)\s+([A-Za-z_]\w*)"#,
            expectedIdentifierPattern: #"^_?[A-Z][A-Za-z0-9]*$"#, kindLabel: "type"
        )
    ]

    /// Rust spellings of the cross-language risks: disabling TLS checks in `reqwest` or `native-tls`, SQL built
    /// with `format!`, and an ignored test.
    private static let rustPatterns = [
        PatternRuleSpec(
            id: "disabled-tls-verification",
            pattern: #"\.danger_accept_invalid_(certs|hostnames)\s*\(\s*true\s*\)"#
                + #"|\bdangerous\(\)\s*\.set_certificate_verifier\("#,
            message: "TLS certificate verification is disabled."
        ),
        PatternRuleSpec(
            id: "sql-string-building",
            pattern: #"\bformat!\s*\(\s*"(?i:\s*(SELECT|INSERT\s+INTO|UPDATE|DELETE\s+FROM))\b[^"]*\{"#,
            message: "SQL built by concatenation or interpolation risks injection; use bound parameters."
        ),
        PatternRuleSpec(
            id: "skipped-test", pattern: #"^\s*#\[ignore\b"#, message: "Skipped test; fix it or delete it."
        )
    ]
}
