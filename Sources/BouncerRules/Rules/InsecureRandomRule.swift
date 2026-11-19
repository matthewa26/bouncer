import Foundation
import BouncerCore

/// Flags a non-cryptographic random number used for a token, ID, secret, password, nonce, salt, or session value:
/// `Math.random()` in TypeScript/JavaScript, the `random` module in Python, and `math/rand` in Go.
///
/// The random call alone isn't enough: the value must be assigned to (or keyed by) a security- or ID-like name, be
/// built into a base-36 string (`Math.random().toString(36)`), or sit in a function with such a name a few lines up.
/// Test files are skipped, and so are games, animations, and jitter, since their names don't match.
public struct InsecureRandomRule: Rule {
    public static let ruleID = "insecure-random"
    public let id = InsecureRandomRule.ruleID
    private static let sensitiveWords: Set = [
        "token", "tokens", "secret", "secrets", "password", "passwd", "pwd", "nonce", "salt", "csrf", "xsrf", "otp",
        "session", "sessionid", "apikey", "uuid", "guid", "uid", "id", "ids", "credential", "credentials", "verifier"
    ]
    /// A timer or sleep call, whose returned handle (`const id = setTimeout(…, Math.random() * 1000)`) isn't the
    /// random value.
    private static let timerCall = TextMatching.regex(#"\b(setTimeout|setInterval|sleep|delay|wait)\s*\("#)
    private static let base36 = TextMatching.regex(#"Math\.random\(\).*\.toString\(\s*36\s*\)"#)
    private static let assignedName = TextMatching.regex(
        #"([A-Za-z_$][\w$]*)\s*(?:\??:\s*[\w$.<>\[\]| ]+?\s*)?(?:\+=|:=|=(?!=)|:(?!:))"#
    )
    private static let functionName = TextMatching.regex(
        #"\b(?:function\*?|def|func)\s+(?:\([^)]*\)\s*)?([A-Za-z_$][\w$]*)|\b(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*"#
            + #"=\s*(?:async\s*)?(?:function\b|\()|^\s*(?:(?:public|private|protected|static|async)\s+)*"#
            + #"([A-Za-z_$][\w$]*)\s*\([^)]*\)\s*(?::\s*[\w<>\[\]| ]+)?\s*\{"#
    )
    private static let camelBoundary = TextMatching.regex(#"([a-z0-9])([A-Z])|([A-Z])([A-Z][a-z])"#)
    private static let functionLookback = 8

    /// Creates the rule.
    public init() {}

    /// Flags each insecure random call that feeds a token-, secret-, or ID-like value.
    ///
    /// - Parameters:
    ///   - file: The file to scan.
    ///   - context: Repo-wide state, including this rule's resolved settings.
    /// - Returns: One finding per flagged line.
    public func evaluate(file: SourceFile, context: AnalysisContext) -> [Finding] {
        let settings = context.settings(for: id)
        guard settings.enabled, let source = InsecureRandomSource(file: file), !TextMatching.isTestPath(file.path)
        else { return [] }
        let message = "\(source.name) isn't cryptographically secure; use \(source.replacement) for tokens and IDs."
        return file.lines.indices.filter { index in
            source.callStart(in: file.lines[index]).map { Self.feedsSensitiveValue(at: index, before: $0, in: file) }
                ?? false
        }.map { Finding(ruleID: id, severity: settings.severity, filePath: file.path, line: $0 + 1, message: message) }
    }

    /// Reports whether the random value on the line at `index` is used for a token, secret, or ID.
    ///
    /// - Parameters:
    ///   - index: The line's 0-based index.
    ///   - call: Where the random call starts on the line.
    ///   - file: The file it's in.
    /// - Returns: Whether the line builds a base-36 ID, assigns to a sensitive name, or sits in a sensitive function.
    private static func feedsSensitiveValue(at index: Int, before call: String.Index, in file: SourceFile) -> Bool {
        let line = file.lines[index]
        if TextMatching.matches(base36, line) { return true }
        let prefix = line[..<call]
        let assigned = TextMatching.matches(timerCall, prefix) ? nil : TextMatching.captures(assignedName, prefix).last
        if let assigned, isSensitive(assigned[1]) { return true }
        let start = max(0, index - functionLookback)
        let enclosing = file.lines[start...index].reversed().lazy.compactMap(declaredFunctionName).first
        return enclosing.map(isSensitive) ?? false
    }

    /// Reads the function a line declares, if it declares one.
    ///
    /// - Parameter line: The line to read.
    /// - Returns: The function's name, or `nil`.
    private static func declaredFunctionName(_ line: Substring) -> String? {
        TextMatching.captures(functionName, line).first?.dropFirst().first { !$0.isEmpty }
    }

    /// Reports whether an identifier names a token, secret, or ID, by its camelCase and snake_case words.
    ///
    /// - Parameter name: An identifier such as `sessionToken` or `request_id`.
    /// - Returns: Whether any of its words, or the whole name, is security- or ID-like.
    static func isSensitive(_ name: String) -> Bool {
        let range = NSRange(name.startIndex..., in: name)
        let spaced = camelBoundary?.stringByReplacingMatches(in: name, range: range, withTemplate: "$1$3_$2$4") ?? name
        let words = spaced.split(separator: "_").map { $0.lowercased() } + [name.lowercased()]
        return words.contains { sensitiveWords.contains($0) } || name.lowercased().hasSuffix("apikey")
    }
}

/// The non-cryptographic random API a file uses, and how to spot a call to it.
struct InsecureRandomSource {
    /// The API's name, for messages.
    let name: String
    /// The secure API to use instead, for messages.
    let replacement: String
    private let call: NSRegularExpression?
    private static let pythonImport = TextMatching.regex(#"(?m)^\s*(import\s+random\b|from\s+random\s+import\b)"#)
    private static let goMathRand = TextMatching.regex(#""math/rand(/v2)?""#)

    /// Picks the random API for a file's language, if the file uses one.
    ///
    /// Python needs an `import random`; Go needs a `math/rand` import and no `crypto/rand` one, which would make
    /// `rand.` ambiguous.
    ///
    /// - Parameter file: The file to inspect.
    init?(file: SourceFile) {
        guard let (name, replacement, call) = Self.api(for: file) else { return nil }
        self.init(name, replacement, call)
    }

    /// Looks up the random API a file's language offers, if the file uses it.
    ///
    /// - Parameter file: The file to inspect.
    /// - Returns: The API's name, its secure replacement, and a regex matching a call, or `nil`.
    private static func api(for file: SourceFile) -> (String, String, String)? {
        switch file.language {
        case .typescript, .javascript: return script
        case .python: return TextMatching.matches(pythonImport, file.contents) ? python : nil
        case .go:
            return TextMatching.matches(goMathRand, file.contents) && !file.contents.contains(cryptoRand) ? go : nil
        default: return nil
        }
    }

    private static let script = (
        "Math.random()", "crypto.randomUUID() or crypto.getRandomValues()", #"\bMath\.random\(\)"#
    )
    private static let python = (
        "The random module", "the secrets module",
        #"\brandom\.(random|randint|randrange|choices?|sample|getrandbits|uniform|randbytes)\("#
    )
    private static let go = ("math/rand", "crypto/rand", #"\brand\.(Int\d*n?|Uint\d+|Read|Float\d+|N)\("#)
    private static let cryptoRand = "\"crypto/rand\""

    /// Creates a source from its names and call pattern.
    ///
    /// - Parameters:
    ///   - name: The API's name.
    ///   - replacement: The secure API to use instead.
    ///   - call: A regex matching a call to the API.
    private init(_ name: String, _ replacement: String, _ call: String) {
        self.name = name
        self.replacement = replacement
        self.call = TextMatching.regex(call)
    }

    /// Finds a call to this random API on a line, outside a comment.
    ///
    /// - Parameter line: The line to check.
    /// - Returns: Where the first call starts, or `nil` if the line's code doesn't call the API.
    func callStart(in line: Substring) -> String.Index? {
        let trimmed = line.drop(while: \.isWhitespace)
        guard !trimmed.hasPrefix("//"), !trimmed.hasPrefix("#"), !trimmed.hasPrefix("*") else { return nil }
        let text = String(line)
        guard let match = call?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text) else { return nil }
        return line.index(line.startIndex, offsetBy: text.distance(from: text.startIndex, to: range.lowerBound))
    }
}
