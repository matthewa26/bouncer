import Foundation
import BouncerCore

/// An error handler on a security check: a `catch`/`@catch`/`except` clause, a promise `.catch`, or an
/// `if err != nil`/`if (err)` branch, with the code it guards and its own body.
struct FailureHandler {
    /// The 0-based line the handler opens on.
    let line: Int
    /// The guarded code: from the `try` (or the few lines above an error branch) through the handler's opening.
    let guarded: String
    /// The handler's code, with strings blanked and comment-only lines left out.
    let body: String
    /// The code of the line the handler opens on, such as `} catch let error as E where error == .missing {`.
    let opening: String
}

/// What a failure handler does, for the `unlogged-security-failure` and `fail-open` rules.
enum FailureOutcome {
    /// The handler lets the request through: `return true`, `next()`, an allow result, or `valid = true`.
    case failsOpen
    /// The handler neither logs, rethrows, returns, responds, nor passes the error on.
    case swallowed
    /// The handler is empty, which `empty-catch` reports, or it deals with the failure.
    case handled

    private static let securityCheck = TextMatching.regex(
        #"(?i)verif(?:y|ied|ication)|authenticat|authori[sz]|\blog_?in\b|\bsign_?in\b|signature|permission|"#
            + #"password|\bjwt\b|(?:access|auth|id|refresh|bearer|csrf|api|session)_?token"#
    )
    private static let opens = TextMatching.regex(
        #"\breturn\s+(?:true|True|YES)\b|\breturn\s+next\(\s*\)|(?:^|[;{\s])next\(\s*\)|"#
            + #"\breturn\s*\{[^}]*\b(?:valid|authorized|authenticated|allowed|verified|ok|success)\s*:\s*true\b|"#
            + #"\breturn\s+\.(?:allow|allowed|authorized|permit|granted)\b|"#
            + #"\b(?:is_?)?(?:[Vv]alid|[Aa]uthori[sz]ed|[Aa]uthenticated|[Aa]llowed|[Vv]erified)\s*=\s*(?:true|"#
            + #"True|YES)\b"#
    )
    private static let deals = TextMatching.regex(
        #"(?i)\b(?:console|logger|logging|log|slog|zap|os_log|nslog|syslog|sentry|bugsnag|rollbar|audit\w*|"#
            + #"report\w*|capture\w*|track\w*|alert\w*|log\w*|warn\w*|print|println|printf|eprintln|debugprint|"#
            + #"fmt\.f?print\w*|system\.(?:out|err))\s*[.(!]|\.(?:error|warn|warning|info|debug|exception|critical|"#
            + #"fatal|notice|errorf|warnf|infof)\(|\b(?:throw|raise|rethrow|panic|return|continue|break)\b|"#
            + #"\breject\(|\b(?:res|response|ctx|reply|w|c)\.(?:status|sendstatus|send|json|end|writehead|"#
            + #"abortwith\w*|string|redirect)\(|\bhttp\.error\(|\babort\(|\bnext\(\s*[^)\s]|\b(?:done|cb|callback|"#
            + #"completion\w*|handler|fail\w*|deny\w*|unauthori[sz]ed\w*|forbidden\w*)\(|\.failure\b|forbidden|"#
            + #"unauthori[sz]ed|\b(?:os\.|sys\.)?exit\(|=\s*(?:e|err|error|ex|exception)\b|\b\w*err(?:or)?\s*=(?!=)|"#
            + #"\bstd(?:err|out)\.write\(|\bhandle_?\w*err\w*\("#
    )
    private static let nothing = TextMatching.regex(#"^(?:\s|;|\bpass\b|\.\.\.)*$"#)
    /// A clause that catches only an expected miss: a Swift `where` filter, or a not-found or missing-key error.
    private static let expectedMiss = TextMatching.regex(
        #"\bcatch\b.*\bwhere\b|NotFound|DoesNotExist|ENOENT|\bKeyError\b|\bIndexError\b"#
    )

    /// Classifies a handler on a security check.
    ///
    /// - Parameter handler: The handler.
    /// - Returns: What it does, or `nil` if the code it guards isn't a security check or it catches only an
    ///   expected miss.
    static func of(_ handler: FailureHandler) -> FailureOutcome? {
        guard TextMatching.matches(securityCheck, handler.guarded),
              !TextMatching.matches(expectedMiss, handler.opening) else { return nil }
        if TextMatching.matches(nothing, handler.body) { return .handled }
        if TextMatching.matches(opens, handler.body) { return .failsOpen }
        return TextMatching.matches(deals, handler.body) ? .handled : .swallowed
    }
}

/// Flags error handlers on a security check that do a given wrong thing: `unlogged-security-failure` for one that
/// swallows the failure without a trace, and `fail-open` for one that lets the request through.
///
/// A handler is on a security check when the code it guards (the `try` body, or the call above an error branch)
/// mentions verifying, authenticating, authorizing, logging in, a signature, a permission, a password, a JWT, or
/// an access, auth, ID, refresh, bearer, CSRF, API, or session token. Clauses that catch only an expected miss (a
/// Swift `catch … where`, a not-found error, `KeyError`, `IndexError`) are skipped. A handler deals with the
/// failure when it logs, reports, prints, throws, returns anything, continues or breaks a loop, sends a response,
/// calls `next(err)`, `done`, a completion, or an error handler, writes to stderr, or stores the error. An empty
/// handler (only `pass`, `;`, or nothing) is left to `empty-catch`. Text-based: it reads Swift,
/// TypeScript/JavaScript, Python, Go, Java, and Objective-C, and skips test files.
public struct SecurityFailureRule: Rule {
    public let id: String
    private let outcome: FailureOutcome
    private let message: String
    private static let languages: [Language] = SecurityPatterns.web

    /// The rule for handlers that swallow a security failure without logging it.
    public static let unlogged = SecurityFailureRule(
        id: "unlogged-security-failure", outcome: .swallowed,
        message: "A failed security check is handled without logging, rethrowing, or returning an error, so an "
            + "attack goes unnoticed; log the failure."
    )

    /// The rule for handlers that let a request through when a security check fails.
    public static let failOpen = SecurityFailureRule(
        id: "fail-open", outcome: .failsOpen,
        message: "A failed security check lets the request through (fail-open); deny on error instead."
    )

    /// Creates the rule.
    ///
    /// - Parameters:
    ///   - id: The rule's identifier.
    ///   - outcome: The handler outcome it flags.
    ///   - message: The message for each flagged handler.
    private init(id: String, outcome: FailureOutcome, message: String) {
        (self.id, self.outcome, self.message) = (id, outcome, message)
    }

    /// Flags each security-check handler with this rule's outcome.
    ///
    /// - Parameters:
    ///   - file: The file to scan.
    ///   - context: Repo-wide state, including this rule's resolved settings.
    /// - Returns: One finding per flagged handler, at the line it opens on.
    public func evaluate(file: SourceFile, context: AnalysisContext) -> [Finding] {
        let settings = context.settings(for: id)
        guard settings.enabled, Self.languages.contains(file.language), !TextMatching.isTestPath(file.path)
        else { return [] }
        let flagged = Set(FailureHandlers.all(in: file).filter { FailureOutcome.of($0) == outcome }.map(\.line))
        return SourceText.flagCodeLines(id, settings, file) { flagged.contains($0) ? message : nil }
    }
}
