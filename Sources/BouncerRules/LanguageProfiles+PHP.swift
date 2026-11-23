/// PHP's profile: `//` and `#` comments, `function`, `switch`, and `match` for the heuristic fallback, and the line
/// patterns for PHP's risky APIs that the cross-language rules match by text.
///
/// `unserialize` on input and `display_errors` switched on are `SecurityPatterns` rows. PHP's own smells that depend
/// on context (test code, superglobals, what a comparison compares) are tree checks in the tree-sitter analyzer.
extension LanguageProfiles {
    /// PHP's bundled profile.
    static let php = LanguageProfile(
        lineCommentPrefixes: ["//", "#"],
        functionStartPattern: #"^\s*((abstract|final|public|protected|private|static)\s+)*function\s+&?\w+\s*\("#,
        switchStartPattern: #"^\s*switch\s*\(|\bmatch\s*\(.*\{\s*$"#,
        switchBranchPattern: #"^\s*(case\b.*[:;]\s*$|default\s*[:;]|[^/#*\s][^=]*=>)"#,
        importLinePattern: #"^use\s+(function\s+|const\s+)?\\?[A-Za-z_]"#,
        namingRules: phpNamingRules,
        extraPatternRules: phpPatterns
    )

    /// camelCase functions and methods (a magic method's leading `__` allowed) and PascalCase classes, interfaces,
    /// traits, and enums, for the heuristic fallback.
    private static let phpNamingRules = [
        NamingRule(
            declarationPattern: #"\bfunction\s+&?([A-Za-z_]\w*)\s*\("#,
            expectedIdentifierPattern: #"^_{0,2}[a-z][A-Za-z0-9]*$"#, kindLabel: "function"
        ),
        NamingRule(
            declarationPattern: #"^\s*(?:(?:abstract|final|readonly)\s+)*(?:class|interface|trait|enum)\s+"#
                + #"([A-Za-z_]\w*)"#,
            expectedIdentifierPattern: #"^[A-Z][A-Za-z0-9]*$"#, kindLabel: "type"
        )
    ]

    /// Starts a pattern so it skips a comment line (`//`, `#` but not a `#[…]` attribute, `/*`, or a docblock's `*`).
    private static let phpCode = #"^(?!\s*(//|#(?!\[)|/?\*))"#

    /// A double-quoted SQL string that interpolates a variable (`"… WHERE id = $id"`, `"{$row['id']}"`).
    private static let phpInterpolatedSQL = #""(?=[^"]*(\$\w|\{\$))(?i:\s*(SELECT\b[^"]*\bFROM|INSERT\s+INTO|"#
        + #"UPDATE\s+\S+\s+SET|DELETE\s+FROM)\b)"#

    /// A quoted SQL string concatenated with a variable (`'SELECT … id = ' . $id`), unless the variable is quoted
    /// by the driver first.
    private static let phpConcatenatedSQL = #"["'](?i:\s*(SELECT\b[^"']*\bFROM|INSERT\s+INTO|UPDATE\s+\S+\s+SET|"#
        + #"DELETE\s+FROM)\b)[^"']*["']\s*\.\s*\$(?![\w>-]*quote\()"#

    /// A query call handed an interpolated or concatenated string, or a superglobal, as its SQL.
    private static let phpQueryCall = #"(\bmysqli_query\s*\(\s*[^,]+,|\bpg_query\s*\(([^,()"']+,)?|->(query|exec)"#
        + #"\s*\()\s*("[^"]*(\$\w|\{\$)|["'][^"']*["']\s*\.\s*\$|\$_(GET|POST|REQUEST|COOKIE)\b)"#

    /// A shell function whose first argument holds a variable, unless `escapeshellarg` quotes it.
    private static let phpShellCall = #"(?<![\w$>:\\])(?<!function\s)\\?(exec|shell_exec|system|passthru|proc_open|"#
        + #"popen)\s*\((?![^;]*escapeshellarg\()[^,;)]*\$"#

    /// A backtick command holding a variable, outside any quoted string on the line.
    private static let phpBacktick = #"[^"'`#]*([=(,]|\breturn|\becho|\bprint)\s*`[^`]*\$"#

    /// MD5 or SHA-1 applied to a password: `md5($password)`, `sha1($_POST['passwd'])`, `hash('md5', $password)`, or
    /// `$passwordHash = md5(…)`. `weak-crypto` skips these lines so each is reported once, with the PHP-specific fix.
    static let phpWeakPasswordHash = #"(?i:\b(?:md5|sha1)\s*\([^;)]*\$[^;)]*passw(?:or)?d|\bhash\s*\(\s*['"]"#
        + #"(?:md5|sha1)['"]\s*,[^;)]*\$[^;)]*passw(?:or)?d|\$\w*passw(?:or)?d\w*\s*=\s*(?:(?:md5|sha1)\s*\(|"#
        + #"hash\s*\(\s*['"](?:md5|sha1)['"]))"#

    /// PHP spellings of the cross-language risks: SQL built from variables, shell commands built from variables,
    /// files included by a variable path, MD5 or SHA-1 on a password, and TLS checks switched off in cURL, Guzzle, or
/// a stream context.
    private static let phpPatterns = [
        PatternRuleSpec(
            id: "sql-string-building",
            pattern: phpCode + #".*?("# + phpInterpolatedSQL + "|" + phpConcatenatedSQL + "|" + phpQueryCall + ")",
            message: "SQL built by concatenation or interpolation risks injection; use a prepared statement with "
                + "bound parameters."
        ),
        PatternRuleSpec(
            id: "php-shell-injection",
            pattern: phpCode + #"(.*?"# + phpShellCall + "|" + phpBacktick + ")",
            message: "Shell command built from a variable risks injection; quote each argument with "
                + "escapeshellarg, or avoid the shell."
        ),
        PatternRuleSpec(
            id: "path-traversal",
            pattern: phpCode + #"(\s*|.*?([=(;@]\s*|\breturn\s+))(include|require)(_once)?\b[^;]*\$"#,
            message: "File included by a variable path can load any file a caller names; include a fixed path, "
                + "or map the input to one."
        ),
        PatternRuleSpec(
            id: "php-weak-password-hash",
            pattern: phpCode + ".*?" + phpWeakPasswordHash,
            message: "MD5 and SHA-1 are fast hashes a stolen password table can be brute-forced from; use "
                + "password_hash and password_verify."
        ),
        PatternRuleSpec(
            id: "disabled-tls-verification",
            pattern: phpCode + #"(?i).*?(\bCURLOPT_SSL_VERIFY(PEER|HOST)\s*(=>|,)\s*(false|0)\b|"#
                + #"['"]verify(_peer(_name)?|_host)?['"]\s*=>\s*false\b)"#,
            message: "TLS certificate verification is disabled."
        )
    ]
}
