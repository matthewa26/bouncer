import BouncerCore

/// The data behind the security rules that are one pattern per line: misconfigured servers and parsers (OWASP
/// A01 and A02), weak keys and fixed IVs (A04), injection into shells and NoSQL queries (A05), disabled JWT checks
/// (A07), and unsafe deserialization (A08). Every pattern is conservative: it needs the insecure value written out,
/// not merely possible.
public enum SecurityPatterns {
    static let scripts: [Language] = [.typescript, .javascript]
    static let web: [Language] = scripts + [.python, .go, .java, .swift, .objc]

    /// Every pattern-based security rule, one per spec.
    public static let specs: [SecurityPatternSpec] = [
        debugMode, permissiveCORS, credentialedCORS, insecureCookie, xmlExternalEntities, hardcodedIV,
        shortCryptoKey, objcShellInjection, nosqlInjection, jwtVerificationDisabled, unsafeDeserialization
    ]

    static let debugMode = SecurityPatternSpec(
        id: "debug-mode-enabled",
        message: "Debug mode is switched on in code; it exposes stack traces and debug consoles in production.",
        patterns: [
            SecurityPattern([.python], #"\b\w+\.run\([^)]*\bdebug\s*=\s*True\b"#),
            SecurityPattern([.python], #"^\s*DEBUG\s*=\s*True\b"#, context: .path(#"/settings(?:/[^/]+|[^/]*)\.py$"#)),
            SecurityPattern([.python], #"\bapp\.debug\s*=\s*True\b|\bapp\.config\[\s*['"]DEBUG['"]\s*\]\s*=\s*True\b"#),
            SecurityPattern(scripts, #"\bapp\.set\(\s*['"]env['"]\s*,\s*['"]development['"]|\bapp\.debug\s*=\s*true\b"#)
        ]
    )

    /// CORS settings that let any origin call: the header set to `*`, `cors()` with no options, `origin: '*'` or
    /// `origin: true`, `CORS(app)`, allow-all flags, and Spring's bare `@CrossOrigin`.
    static let anyOrigin: [SecurityPattern] = [
        SecurityPattern(web, #"['"](?i:access-control-allow-origin)['"]\s*\]?\s*[,:=]\s*@?['"]\*['"]"#),
        SecurityPattern([.swift, .objc], #"@?"\*"\s*,?\s*forHTTPHeaderField:\s*@?"(?i:access-control-allow-origin)""#),
        SecurityPattern(scripts, #"\bcors\(\s*\)|\bcors\(\s*\{[^}]*\borigin\s*:\s*(?:['"`]\*['"`]|true\b)"#),
        SecurityPattern(scripts, #"^\s*origin\s*:\s*(?:['"`]\*['"`]|true\b)"#, context: .nearby(#"\bcors\b|CORS"#)),
        SecurityPattern([.python], #"\bCORS\(\s*\w+\s*\)|\bCORS\([^)]*\borigins\s*=\s*['"]\*['"]"#),
        SecurityPattern([.python], #"\bCORS_(?:ORIGIN_ALLOW_ALL|ALLOW_ALL_ORIGINS)\s*=\s*True\b"#),
        SecurityPattern([.python], #"\ballow_origins\s*=\s*\[\s*['"]\*['"]\s*\]"#),
        SecurityPattern([.go], #"\bAllow(?:ed)?Origins\s*:\s*\[\]string\{\s*"\*"\s*\}|\bAllowAllOrigins\s*:\s*true\b"#),
        SecurityPattern([.go], #"\bcors\.AllowAll\(\)"#),
        SecurityPattern([.java], #"^\s*@CrossOrigin\s*$|@CrossOrigin\(\s*(?:(?:origins|value)\s*=\s*)?"\*"\s*\)"#),
        SecurityPattern([.java], #"\.(?:allowedOrigins|addAllowedOrigin|allowedOriginPatterns)\(\s*"\*"\s*\)"#),
        SecurityPattern([.swift], #"\ballowedOrigin:\s*\.(?:all|originBased)\b"#)
    ]

    /// CORS settings that send credentials (cookies, auth headers) cross-origin.
    static let credentials = #"\bcredentials\s*:\s*true\b|(?i:access-control-allow-credentials)['"]\s*\]?\s*"#
        + #"[,:=]\s*@?['"]true|\bsupports_credentials\s*=\s*True\b|\bCORS_ALLOW_CREDENTIALS\s*=\s*True\b|"#
        + #"\ballow_credentials\s*=\s*True\b|\bAllowCredentials\s*:\s*true\b|\ballowCredentials\s*=\s*"true"|"#
        + #"\.allowCredentials\(\s*true\s*\)|\bsetAllowCredentials\(\s*true\s*\)|\ballowCredentials:\s*true\b"#
        + #"|@?"true"\s*,?\s*forHTTPHeaderField:\s*@?"(?i:access-control-allow-credentials)""#

    static let permissiveCORS = SecurityPatternSpec(
        id: "permissive-cors",
        message: "CORS lets every origin call this server; list the origins that may.",
        patterns: anyOrigin, conditions: (fileGate: nil, fileExclusion: credentials, lineExclusion: nil)
    )

    static let credentialedCORS = SecurityPatternSpec(
        id: "cors-credentials-any-origin",
        message: "CORS lets any origin call with credentials, so any site can act as a signed-in user; list the "
            + "allowed origins.",
        patterns: anyOrigin, conditions: (fileGate: credentials, fileExclusion: nil, lineExclusion: nil)
    )

    static let insecureCookie = SecurityPatternSpec(
        id: "insecure-cookie",
        message: "Cookie set without Secure or HttpOnly; session cookies need both.",
        patterns: [
            SecurityPattern(scripts, #"\bhttpOnly\s*:\s*false\b"#, context: .nearby(#"(?i)cookie|session"#)),
            SecurityPattern(scripts, #"\bsecure\s*:\s*false\b"#, context: .nearby(#"(?i)cookie"#)),
            SecurityPattern([.python], #"\bset_cookie\([^)]*\b(?:secure|httponly)\s*=\s*False\b"#),
            SecurityPattern([.python], #"^\s*(?:secure|httponly)\s*=\s*False\b"#, context: .nearby(#"\bset_cookie\("#)),
            SecurityPattern([.python], #"\b(?:SESSION|CSRF|REMEMBER)_COOKIE_(?:SECURE|"#
                + #"HTTPONLY)['"]?\s*\]?\s*=\s*False\b"#),
            SecurityPattern([.go], #"\b(?:Secure|HttpOnly)\s*:\s*false\b"#, context: .nearby(#"\bhttp\.Cookie\b"#)),
            SecurityPattern([.java], #"\.set(?:Secure|HttpOnly)\(\s*false\s*\)"#, context: .nearby(#"(?i)cookie"#)),
            SecurityPattern([.swift], #"\bis(?:Secure|HTTPOnly)\s*:\s*false\b"#, context: .nearby(#"Cookie"#))
        ]
    )

    static let xmlExternalEntities = SecurityPatternSpec(
        id: "xml-external-entities",
        message: "XML parser resolves external entities, which lets a document read local files or reach internal "
            + "hosts (XXE); turn entity resolution off.",
        patterns: [
            SecurityPattern(scripts, #"\bnoent\s*:\s*true\b"#),
            SecurityPattern([.python], #"\bresolve_entities\s*=\s*True\b"#),
            SecurityPattern([.java], #"IS_SUPPORTING_EXTERNAL_ENTITIES\s*,\s*(?:true|Boolean\.TRUE)\b"#),
            SecurityPattern([.java], #"\.setExpandEntityReferences\(\s*true\s*\)"#),
            SecurityPattern([.java], #"/external-(?:general|parameter)-entities"\s*,\s*true\b"#),
            SecurityPattern([.java], #"/disallow-doctype-decl"\s*,\s*false\b"#),
            SecurityPattern([.swift, .objc], #"\bshouldResolveExternalEntities\s*=\s*(?:true|YES)\b"#),
            SecurityPattern([.objc], #"\bsetShouldResolveExternalEntities:\s*YES\b"#)
        ]
    )
}

/// The security rules mapped to the OWASP Top 10 that aren't per-language profile patterns: the pattern rules,
/// the request-input sink rules, and the comparison and error-handler rules.
public enum SecurityRules {
    /// Every one of them, ready to evaluate.
    public static let all: [Rule] = SecurityPatterns.specs.map(SecurityPatternRule.init)
        + RequestSinks.specs.map(RequestSinkRule.init)
        + [TimingUnsafeComparisonRule(), SecurityFailureRule.unlogged, SecurityFailureRule.failOpen]
}
