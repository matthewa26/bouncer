import Foundation
import BouncerCore

/// Flags a log or print call that writes out a password, secret, token, API key, private key, SSN, or card number:
/// `console.log("login", password)`, `logger.info(f"token={access_token}")`, `log.Printf("key %s", apiKey)`,
/// `print("\(user.password)")`.
///
/// It's text-based. A log call (`console.*`, `logger.*`, `log.*`, `logging.*`, `print`, `println`, `printf`,
/// `fmt.Print*`/`Fprint*`, `os_log`, `NSLog`, `Logger(…).*`, `System.out.print*`, `Log.d`, `Write-Host`/`Output`/
/// `Verbose`/`Debug`, `echo`, `puts`, Rust's `println!`/`info!`/…) is read to the end of its line. Identifiers
/// outside string literals count, and so do interpolations inside them (`${x}`, `\(x)`, `{x}`, `$x`); words inside
/// a string never do, so `print("Enter password:")` is fine. An identifier is sensitive when its words name the
/// secret itself (`password`, `passwd`, `passphrase`, `secret`, `apiKey`, `privateKey`, `ssn`, `cvv`, `creditCard`,
/// `cardNumber`, or a token qualified as `access`, `auth`, `refresh`, `bearer`, `session`, `id`, `api`, `csrf`,
/// `oauth`, `client`, or `jwt`), and not when it describes it (`passwordField`, `tokenCount`, `secretName`,
/// `hashedPassword`, `hasToken`), is a call (`validatePassword(…)`), an object key (`{ password: "…" }`), or only
/// its length or presence is used (`token.count`, `len(password)`, `secret != nil`). A line mentioning `redact`,
/// `mask`, `scrub`, `obfuscate`, `sanitize`, or `***` is skipped, and so are test files.
public struct LoggedSecretRule: Rule {
    public static let ruleID = "logged-secret"
    public let id = LoggedSecretRule.ruleID
    private static let logCall = TextMatching.regex(
        #"\bconsole\.(?:log|info|warn|error|debug|trace)\(|\b(?:self\.|this\.)?(?:logger|log|logging|LOGGER|LOG|"#
            + #"Logger(?:\([^)]*\))?)\.\w+\(|(?<![.\w])(?:print|println|printf|debugPrint|puts|NSLog|os_log)!?\(|"#
            + #"(?<![.\w])(?:info|debug|warn|error|trace|eprintln)!\(|"#
            + #"\bfmt\.(?:Print|Fprint)\w*\(|\bSystem\.(?:out|err)\.print\w*\(|\bLog\.[diwev]\(|"#
            + #"\bWrite-(?:Host|Output|Verbose|Debug|Information)\b|^\s*echo\b"#
    )
    /// A quick check that a file mentions a secret-like word at all before it's read line by line.
    private static let mention = TextMatching.regex(#"(?i)pass|secret|token|api_?key|private_?key|ssn|cvv|card|jwt"#)
    private static let redaction = TextMatching.regex(#"(?i)redact|mask|scrub|obfuscat|sanitiz|\*\*\*"#)

    /// Creates the rule.
    public init() {}

    /// Flags each log call that writes a sensitive value.
    ///
    /// - Parameters:
    ///   - file: The file to scan.
    ///   - context: Repo-wide state, including this rule's resolved settings.
    /// - Returns: One finding per flagged line, naming the value.
    public func evaluate(file: SourceFile, context: AnalysisContext) -> [Finding] {
        let settings = context.settings(for: id)
        guard settings.enabled, !TextMatching.isTestPath(file.path), TextMatching.matches(Self.mention, file.contents)
        else { return [] }
        return SourceText.flagCodeLines(id, settings, file) { index in
            Self.loggedSecret(on: file.lines[index]).map {
                "'\($0)' looks like a secret and is written to a log; leave it out, or redact it."
            }
        }
    }

    /// Finds a sensitive value written by a log call on a line.
    ///
    /// - Parameter line: The line to check.
    /// - Returns: The sensitive identifier, or `nil`.
    static func loggedSecret(on line: Substring) -> String? {
        guard let arguments = logArguments(on: String(line)) else { return nil }
        let visible = SourceText.blankingStrings(arguments) + " " + LogArguments.interpolations(in: arguments)
        return LogArguments.identifiers(in: visible).first { name, position in
            SecretNames.isSensitive(name) && !LogArguments.isMetadataUse(of: name, at: position, in: visible)
        }?.0
    }

    /// Reads the text after a line's log call, unless the line redacts what it logs.
    ///
    /// - Parameter text: The line.
    /// - Returns: The text after the call's opening, or `nil` if the line has no log call or redacts.
    private static func logArguments(on text: String) -> String? {
        guard !TextMatching.matches(redaction, text),
              let match = logCall?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text) else { return nil }
        return String(text[range.upperBound...])
    }
}

/// Reads what a log call's arguments write out, for `LoggedSecretRule`.
enum LogArguments {
    private static let interpolation = TextMatching.regex(
        #"\$\{([^}]*)\}|\\\(([^)]*)\)|\$([A-Za-z_]\w*)|\{([A-Za-z_][\w.]*)(?:![rsa])?(?::[^}]*)?\}"#
    )
    private static let identifier = TextMatching.regex(#"(?<![\w$])[A-Za-z_]\w*"#)
    private static let metadataSuffix = TextMatching.regex(
        #"^\s*(?:\(|:(?!:)|\.(?:count|length|isEmpty|size|len|Length|Count|IsEmpty)\b|[!=]==?\s*(?:nil|null|None|"#
            + #"undefined)|\s+is\s+(?:not\s+)?None\b)"#
    )
    private static let metadataPrefix = TextMatching.regex(
        #"(?:\blen|\bbool|\bBoolean|!!|\btypeof\s)\(?\s*(?:[\w$]+\??\.)*$"#
    )

    /// Collects the expressions interpolated into a call's string literals.
    ///
    /// - Parameter arguments: The call's argument text.
    /// - Returns: The interpolated expressions, space-separated.
    static func interpolations(in arguments: String) -> String {
        SourceText.stringLiterals(in: arguments).flatMap { literal in
            TextMatching.captures(interpolation, literal).flatMap { $0.dropFirst().filter { !$0.isEmpty } }
        }.joined(separator: " ")
    }

    /// Lists the identifiers in some code with their offsets.
    ///
    /// - Parameter code: The code, with string contents blanked.
    /// - Returns: Each identifier and where it starts, in order.
    static func identifiers(in code: String) -> [(String, Int)] {
        let ns = code as NSString
        return (identifier?.matches(in: code, range: NSRange(location: 0, length: ns.length)) ?? []).map {
            (ns.substring(with: $0.range), $0.range.location)
        }
    }

    /// Reports whether an identifier is only called, used as a key, or checked for length or presence.
    ///
    /// - Parameters:
    ///   - name: The identifier.
    ///   - position: Its offset in `code`.
    ///   - code: The surrounding code.
    /// - Returns: Whether the use doesn't write out the value.
    static func isMetadataUse(of name: String, at position: Int, in code: String) -> Bool {
        let ns = code as NSString
        let after = ns.substring(from: position + (name as NSString).length)
        let before = ns.substring(to: position)
        return TextMatching.matches(metadataSuffix, after) || TextMatching.matches(metadataPrefix, before)
    }
}

/// Decides whether an identifier names a secret, by its words.
enum SecretNames {
    private static let secretWords: Set = ["password", "passwd", "passphrase", "secret", "secrets", "ssn", "cvv"]
    private static let secretPairs: Set = ["apikey", "privatekey", "creditcard", "cardnumber", "secretkey"]
    private static let tokenQualifiers: Set = [
        "access", "auth", "refresh", "bearer", "session", "id", "api", "csrf", "oauth", "client", "jwt"
    ]
    private static let describingWords: Set = [
        "field", "fields", "label", "prompt", "placeholder", "hint", "policy", "length", "len", "count", "required",
        "valid", "invalid", "expired", "expiry", "expires", "expiration", "changed", "file", "path", "env", "name",
        "type", "kind", "id", "ids", "arn", "url", "uri", "header", "manager", "store", "provider", "service", "dir",
        "rotation", "version", "ttl", "set", "present", "exists", "enabled", "error", "status", "input", "view",
        "button", "strength", "regex", "pattern", "rules", "format", "prefix", "suffix", "size", "ref", "key", "keys",
        "location", "endpoint", "source", "param", "flag", "option", "mode", "hash", "digest", "fingerprint"
    ]
    private static let negatingWords: Set = [
        "hash", "hashed", "masked", "redacted", "has", "is", "should", "show", "needs", "validate", "check", "verify",
        "require", "min", "max", "no", "without", "missing", "empty"
    ]

    /// Reports whether an identifier names a secret value rather than describing one.
    ///
    /// - Parameter name: The identifier.
    /// - Returns: Whether its words name a password, secret, key, token, or card or social-security number.
    static func isSensitive(_ name: String) -> Bool {
        let words = SourceText.words(of: name)
        guard let last = words.last, !words.contains(where: negatingWords.contains) else { return false }
        let pairs = zip(words, words.dropFirst()).map { $0 + $1 }
        let isQualifiedToken = words.contains("token") && words.contains(where: tokenQualifiers.contains)
        let namesSecret = words.contains(where: secretWords.contains) || pairs.contains(where: secretPairs.contains)
            || isQualifiedToken || words == ["jwt"]
        // A describing last word (`passwordField`, `tokenId`) is metadata, unless it completes the secret (`apiKey`).
        return namesSecret && (!describingWords.contains(last) || secretPairs.contains(pairs.last ?? ""))
    }
}
