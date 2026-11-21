import Foundation
import BouncerCore

/// Flags a secret compared with `==`, `===`, `!=`, or `!==`: `signature == expected`, `token !== process.env.TOKEN`,
/// `if hmac != computed`. Ordinary equality stops at the first differing byte, so its timing leaks how much of a
/// guess was right; `hmac.compare_digest`, `crypto.timingSafeEqual`, `subtle.ConstantTimeCompare`, or
/// `MessageDigest.isEqual` don't.
///
/// It's text-based. One side's last name must name a secret: a password, passphrase, secret, HMAC, signature, API
/// or secret key, or token (`token`, `apiToken`, `expected_signature`), not something describing one (`tokenType`,
/// `passwordLength`, `signatureCount`, `hasToken`). The other side must look like the value it's checked against:
/// it names a secret too, or it's an expected, stored, provided, computed, or known value, or one read from the
/// environment or a header (`process.env.API_TOKEN`, `expected`, `computedHMAC`). A literal, `nil`/`null`/`None`, an
/// enum case such as `.bearer`, or the same name on another object (`lhs.token == rhs.token`, as an `Equatable`
/// conformance writes) never counts. Form checks (`password != confirmPassword`, `newPassword == oldPassword`) are
/// skipped, and so are files that never mention authentication, HMACs, JWTs, webhooks, CSRF, API keys, passwords,
/// secrets, signatures, or crypto, lines that already use a constant-time comparison, and test files.
public struct TimingUnsafeComparisonRule: Rule {
    public static let ruleID = "timing-unsafe-comparison"
    public let id = TimingUnsafeComparisonRule.ruleID
    /// The patterns the rule reads lines with.
    private enum Pattern {
        /// Files that mention authentication or crypto at all.
        static let fileGate = TextMatching.regex(
            #"(?i)hmac|\bjwt\b|bearer|authori[sz]ation|authenticat|api[_-]?key|csrf|webhook|password|secret|"#
                + #"signature|crypto"#
        )
        /// A constant-time comparison already on the line.
        static let constantTime = TextMatching.regex(
            #"(?i)compare_digest|timingSafeEqual|ConstantTimeCompare|MessageDigest\.isEqual|secure_compare|"#
                + #"safeEqual|CRYPTO_memcmp|timingsafe_bcmp|constant_?time"#
        )
        /// An equality comparison: an optional `typeof`, the left operand, and the right operand.
        static let comparison = TextMatching.regex(
            #"(?<![\w$.])(typeof\s+)?([A-Za-z_$][\w$]*(?:[?!]?\.[A-Za-z_$][\w$]*|\(\)|\[[^\]]*\])*[!?]?)"#
                + #"\s*(?:===?|!==?)\s*([^\s)&|;,:]+)"#
        )
        /// A right operand that's a literal, `nil`-like, an enum case, or a tuple.
        static let literal = TextMatching.regex(
            #"^(?:["'`\d.\-\[{(]|(?:nil|null|None|undefined|true|false|True|False|NULL|Nil|YES|NO|nullptr)\b)"#
        )
    }

    private static let secretWords: Set = ["password", "passwd", "passphrase", "secret", "hmac", "signature", "token"]
    private static let referenceWords: Set = [
        "expected", "stored", "provided", "computed", "calculated", "valid", "env", "environ", "getenv", "header",
        "headers", "saved", "actual", "given", "supplied", "incoming", "received", "known", "correct", "digest",
        "mac", "hash", "sig"
    ]
    private static let formWords: Set = [
        "confirm", "confirmation", "repeat", "retype", "again", "new", "old", "current"
    ]

    /// The capture groups of `Pattern.comparison`, with the whole match as group 0.
    private enum Group {
        /// A `typeof ` keyword before the left operand, which makes the comparison a type check.
        static let typeofKeyword = 1
        /// The left operand.
        static let left = 2
        /// The right operand.
        static let right = 3
        /// How many groups a match has, the whole match included.
        static let count = 4
    }

    /// Creates the rule.
    public init() {}

    /// Flags each line comparing a secret with ordinary equality.
    ///
    /// - Parameters:
    ///   - file: The file to scan.
    ///   - context: Repo-wide state, including this rule's resolved settings.
    /// - Returns: One finding per flagged line, naming the secret.
    public func evaluate(file: SourceFile, context: AnalysisContext) -> [Finding] {
        let settings = context.settings(for: id)
        guard settings.enabled, Self.applies(to: file) else { return [] }
        return SourceText.flagCodeLines(id, settings, file) { index in
            let line = file.lines[index]
            guard !TextMatching.matches(Pattern.constantTime, line) else { return nil }
            return Self.comparedSecret(in: SourceText.code(of: line)).map(Self.message)
        }
    }

    /// Describes a finding.
    ///
    /// - Parameter secret: The compared secret's name.
    /// - Returns: The finding's message.
    private static func message(_ secret: String) -> String {
        "'\(secret)' is compared with ordinary equality, which leaks timing; use a constant-time comparison."
    }

    /// Reports whether the rule reads a file: one in a supported language, outside the tests, that mentions
    /// authentication or crypto.
    ///
    /// - Parameter file: The file.
    /// - Returns: Whether to scan it.
    private static func applies(to file: SourceFile) -> Bool {
        SecurityPatterns.web.contains(file.language) && !TextMatching.isTestPath(file.path)
            && TextMatching.matches(Pattern.fileGate, file.contents)
    }

    /// Finds a secret compared with ordinary equality on a line.
    ///
    /// - Parameter code: The line's code, strings blanked.
    /// - Returns: The secret's name, or `nil`.
    static func comparedSecret(in code: String) -> String? {
        let comparisons = TextMatching.captures(Pattern.comparison, code).compactMap { match in
            match.count == Group.count && match[Group.typeofKeyword].isEmpty
                ? (match[Group.left], match[Group.right]) : nil
        }
        return comparisons.lazy.compactMap(secret(comparedBetween:)).first
    }

    /// Finds the secret in one comparison, if one side names a secret and the other its reference value.
    ///
    /// - Parameter operands: The left and right operands' text.
    /// - Returns: The secret's name, or `nil`.
    private static func secret(comparedBetween operands: (String, String)) -> String? {
        let (left, right) = (lastName(of: operands.0), lastName(of: operands.1))
        guard !TextMatching.matches(Pattern.literal, operands.1), left != right,
              !(SourceText.words(of: left) + SourceText.words(of: right)).contains(where: formWords.contains)
        else { return nil }
        if isSecret(left), isReference(operands.1) { return left }
        return isSecret(right) && isReference(operands.0) ? right : nil
    }

    /// Reads the last name in an operand: `token` in `req.headers.token`, `signature` in `self.signature()`,
    /// `computeHmac` in `computeHmac(body`.
    ///
    /// - Parameter operand: The operand's text.
    /// - Returns: Its last identifier.
    private static func lastName(of operand: String) -> String {
        let trimmed = operand.replacingOccurrences(of: #"\[[^\]]*\]|\(\)|[!?]|\(.*$"#, with: "",
                                                   options: .regularExpression)
        return trimmed.split(separator: ".").last.map(String.init) ?? trimmed
    }

    /// Reports whether an operand looks like a secret's reference value: it names a secret itself, or it's an
    /// expected, stored, provided, or computed value, or one read from the environment or a header.
    ///
    /// - Parameter operand: The operand's text.
    /// - Returns: Whether the operand's words include a secret or one of those cues.
    private static func isReference(_ operand: String) -> Bool {
        SourceText.words(of: operand.replacingOccurrences(of: ".", with: "_"))
            .contains { secretWords.contains($0) || referenceWords.contains($0) }
    }

    /// Reports whether a name names a secret rather than describing one.
    ///
    /// - Parameter name: The identifier.
    /// - Returns: Whether its words name a password, secret, HMAC, signature, key, or token.
    static func isSecret(_ name: String) -> Bool {
        let words = SourceText.words(of: name)
        guard let last = words.last, !words.contains(where: SecretNames.negatingWords.contains) else { return false }
        let pairs = zip(words, words.dropFirst()).map { $0 + $1 }
        let isKey = pairs.last == "apikey" || pairs.last == "secretkey"
        return isKey || words.contains(where: secretWords.contains) && !SecretNames.describingWords.contains(last)
    }
}
