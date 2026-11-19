import BouncerCore

/// The rules computed from a file's text alone, which every analyzer runs regardless of parser.
///
/// One list, so a new text-level rule reaches every language at once: the shared smell and hygiene
/// rules, the cross-language patterns in `UniversalPatterns`, and the language's own pattern rules.
public enum TextRules {
    /// Builds the text-level rules for one language.
    ///
    /// - Parameter profile: The language's profile, for comment syntax and its own pattern rules.
    /// - Returns: Every text-level rule, bound to `profile`.
    public static func make(profile: LanguageProfile) -> [Rule] {
        let shared: [Rule] = [
            FileLengthRule(profile: profile), LongLineRule(), TodoDensityRule(), DuplicateBlockRule(),
            TrailingWhitespaceRule(), SecretPatternRule(), DeepNestingRule(), MissingFinalNewlineRule(),
            CrlfLineEndingsRule(), MixedIndentationRule(), ConsecutiveBlankLinesRule()
        ]
        return shared + CustomRuleFactory.makeRules(from: UniversalPatterns.specs + profile.extraPatternRules)
    }
}

/// Pattern rules that apply in every language: risky crypto, TLS, and network and query construction.
public enum UniversalPatterns {
    public static let specs: [PatternRuleSpec] = [
        PatternRuleSpec(
            id: "weak-crypto",
            pattern: #"(?i)\b(md5|sha1)\b|\bInsecure\.(MD5|SHA1)\b|\bDES\b|\bECB\b"#,
            message: "Weak cryptography (MD5, SHA-1, DES, or ECB mode); use SHA-256+ or an AEAD cipher."
        ),
        PatternRuleSpec(
            id: "disabled-tls-verification",
            pattern: #"rejectUnauthorized\s*:\s*false|NODE_TLS_REJECT_UNAUTHORIZED\s*=\s*['"]?0|"#
                + #"\bverify\s*=\s*False\b|InsecureSkipVerify\s*:\s*true|\bcurl\b.*\s(-k|--insecure)\b"#,
            message: "TLS certificate verification is disabled."
        ),
        PatternRuleSpec(
            id: "insecure-http-url",
            pattern: #"http://(?!localhost\b|127\.0\.0\.1|0\.0\.0\.0|\[::1\]|www\.w3\.org|schemas\.|purl\.org|"#
                + #"ns\.adobe\.com|[^/\s"'`]*\.(local|localhost|test|example)(?=[:/"'`\s]|$))"#,
            message: "Plain http:// URL; use https://."
        ),
        PatternRuleSpec(
            id: "sql-string-building",
            pattern: #"(?i)(["'`]|f["'])\s*(SELECT|INSERT\s+INTO|UPDATE|DELETE\s+FROM)\b[^"'`]*"#
                + #"(["'`]\s*\+|\$\{|\\\(|\{[A-Za-z_])"#,
            message: "SQL built by concatenation or interpolation risks injection; use bound parameters."
        )
    ]
}
