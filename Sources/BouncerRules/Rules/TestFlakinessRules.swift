import Foundation
import BouncerCore

/// One kind of flaky call a test-only rule looks for.
struct FlakyCallCheck: Sendable {
    /// Matches the call on a line whose strings are blanked (or, with `matchesRawLine`, on the raw line).
    let call: NSRegularExpression?
    /// Whether `call` needs the raw line, because it looks inside a string (a URL).
    let matchesRawLine: Bool
    /// Matches file contents that make the call safe, such as fake timers or an HTTP mocking library.
    let fileExemption: NSRegularExpression?

    /// Creates a check.
    ///
    /// - Parameters:
    ///   - call: The call's pattern.
    ///   - matchesRawLine: Whether to match the raw line rather than its blanked code.
    ///   - fileExemption: A pattern that, found anywhere in the file, turns the check off, or `nil`.
    init(_ call: String, raw matchesRawLine: Bool = false, unless fileExemption: String? = nil) {
        self.call = TextMatching.regex(call)
        self.matchesRawLine = matchesRawLine
        self.fileExemption = fileExemption.flatMap(TextMatching.regex)
    }
}

/// Flags a call in a test file that makes the test slow or flaky: a real sleep (`test-sleep`), a real network call
/// (`test-network-call`), or a read of the real clock (`test-real-clock`, opt-in, since injecting a clock is a design
/// choice).
///
/// Only test files run it, by the same path check the security rules use to skip them (`test`/`tests`/`spec`
/// directories, `*.test.ts`, `test_*.py`, `*_test.go`, `*Tests.swift`, …). Comment lines are skipped, and calls are
/// matched with string contents blanked, except a network call's URL, which must be a literal non-local
/// `http(s)://` address. A file using fake timers skips `setTimeout` sleeps and clock reads; one using an HTTP mocking
/// library that intercepts requests (`nock`, `msw`, `fetch-mock`, `responses`, `requests_mock`, `respx`, `httpretty`,
/// `vcr`, `URLProtocol`, `gock`, `httpmock`) skips network checks; a local test server (`httptest`) doesn't, since
/// it doesn't stop a call to a remote URL.
public struct FlakyTestCallRule: Rule {
    public static let sleepID = "test-sleep"
    public static let networkID = "test-network-call"
    public static let clockID = "test-real-clock"
    public let id: String
    private let checks: [FlakyCallCheck]
    private let message: String
    private let isOptIn: Bool
    private static let fakeTimers = #"useFakeTimers|advanceTimers|fakeAsync|freeze_?time|freezegun|setSystemTime|"#
        + #"timecop|clock\.tick|FakeClock|TestClock|ImmediateClock"#
    private static let httpMocks = #"\bnock\b|\bmsw\b|setupServer|\bresponses\b|requests_mock|httpretty|\bvcr\b|"#
        + #"\brespx\b|fetch-?[mM]ock|URLProtocol|\bgock\b|httpmock"#
    private static let remoteURL = #"\s*f?["'`]https?://(?!localhost\b|127\.|0\.0\.0\.0|\[::1\])"#

    /// Builds the three rules.
    ///
    /// - Returns: `test-sleep`, `test-network-call`, and `test-real-clock`.
    public static func makeAll() -> [FlakyTestCallRule] {
        [
            FlakyTestCallRule(id: sleepID, checks: sleepChecks, isOptIn: false,
                              message: "Real sleep in a test makes it slow and timing-dependent; wait on a condition "
                                + "or use fake timers."),
            FlakyTestCallRule(id: networkID, checks: networkChecks, isOptIn: false,
                              message: "Test calls a real network service; stub it, or point it at a local server."),
            FlakyTestCallRule(id: clockID, checks: clockChecks, isOptIn: true,
                              message: "Test reads the real clock; inject a clock or freeze time so it's repeatable.")
        ]
    }

    private static let sleepChecks = [
        FlakyCallCheck(#"(?<![\w.])(?<!func )(?<!def )(?<!function )(?:u|nano)?sleep\(|\b(?:Thread|Task|time|"#
            + #"SystemClock|TimeUnit\.\w+)\.(?:s|S)leep\b|\bStart-Sleep\b|\basyncio\.sleep\(\s*(?!0(?:\.0*)?\s*\))"#,
            unless: #"(?i)(?:patch|mock|stub)\w*\(?[^\n]*sleep"#),
        FlakyCallCheck(#"\bsetTimeout\(.*,\s*[1-9][\d_]*\s*\)"#, unless: fakeTimers)
    ]
    private static let networkChecks = [
        FlakyCallCheck(#"\bURLSession\.shared\b"#, unless: httpMocks),
        FlakyCallCheck(#"(?:\bfetch|\baxios(?:\.\w+)?|\brequests\.\w+|\burlopen|\bhttpx\.\w+|\bhttp\.(?:Get|Post|Head|"#
            + #"PostForm))\("# + remoteURL, raw: true, unless: httpMocks)
    ]
    private static let clockChecks = [
        FlakyCallCheck(#"(?<![\w.])Date\(\)|\bDate\.now\b|\bnew Date\(\)|\btime\.Now\(\)|\bdatetime\.(?:now|utcnow|"#
            + #"today)\(|\btime\.time\(\)|\bdate\.today\(\)|\bSystem\.currentTimeMillis\(\)|\bInstant\.now\(\)|"#
            + #"\bLocalDateTime\.now\(\)|\bGet-Date\b|\bperformance\.now\(\)"#, unless: fakeTimers)
    ]

    /// Creates one flaky-call rule.
    ///
    /// - Parameters:
    ///   - id: The rule's identifier.
    ///   - checks: The calls it looks for.
    ///   - isOptIn: Whether it runs only when `.bouncer` enables it.
    ///   - message: The finding's message.
    private init(id: String, checks: [FlakyCallCheck], isOptIn: Bool, message: String) {
        self.id = id
        self.checks = checks
        self.isOptIn = isOptIn
        self.message = message
    }

    /// Flags each line of a test file that makes one of this rule's calls.
    ///
    /// - Parameters:
    ///   - file: The file to scan.
    ///   - context: Repo-wide state, including this rule's settings.
    /// - Returns: One finding per flagged line.
    public func evaluate(file: SourceFile, context: AnalysisContext) -> [Finding] {
        let settings = isOptIn ? SourceText.optInSettings(id, context) : context.settings(for: id)
        guard let settings, settings.enabled, TextMatching.isTestPath(file.path) else { return [] }
        let active = checks.filter { !TextMatching.matches($0.fileExemption, file.contents) }
        guard !active.isEmpty else { return [] }
        return SourceText.flagCodeLines(id, settings, file) { Self.calls(active, on: file.lines[$0]) ? message : nil }
    }

    /// Reports whether a line makes any of the given calls.
    ///
    /// - Parameters:
    ///   - checks: The calls to look for.
    ///   - line: The line to check.
    /// - Returns: Whether one of them matches.
    private static func calls(_ checks: [FlakyCallCheck], on line: Substring) -> Bool {
        let code = SourceText.code(of: line)
        return checks.contains { TextMatching.matches($0.call, $0.matchesRawLine ? String(line) : code) }
    }
}
