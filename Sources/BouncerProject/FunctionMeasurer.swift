import Foundation
import BouncerCore

/// One function's complexity and size, as its language's analyzer measures them.
public struct FunctionMeasure: Sendable, Equatable {
    /// The declared name, or `nil` where the analyzer doesn't report one (heuristic languages).
    public let name: String?
    public let line: Int
    /// Cyclomatic complexity: decision points plus one.
    public let complexity: Int
    /// Logical lines, or `nil` if not measured.
    public let logicalLines: Int?

    /// Creates a measurement.
    ///
    /// - Parameters:
    ///   - name: The function's name, if known.
    ///   - line: The 1-indexed line it starts on.
    ///   - complexity: Its cyclomatic complexity.
    ///   - logicalLines: Its logical line count, if measured.
    public init(name: String?, line: Int, complexity: Int, logicalLines: Int? = nil) {
        self.name = name
        self.line = line
        self.complexity = complexity
        self.logicalLines = logicalLines
    }
}

/// Measures every function in a file, for the rules that weigh complexity against history.
public protocol FunctionMeasuring: Sendable {
    /// Measures a file's functions.
    ///
    /// - Parameter file: The file.
    /// - Returns: Its functions, or `nil` for a language that isn't measured.
    func functions(in file: SourceFile) -> [FunctionMeasure]?
}

/// Measures functions through the language analyzers' own `cyclomatic-complexity` and `long-function` rules.
///
/// The project layer can't reach the analyzers' declaration summaries, so it runs each analyzer with both
/// limits at 0, which makes every function report its measurement, and reads the numbers back from the
/// findings. Only languages with a dedicated analyzer are measured; plain text, Markdown, and config files
/// aren't.
public struct AnalyzerFunctionMeasurer: FunctionMeasuring {
    private let analyzers: [Language: LanguageAnalyzer]
    static let complexityRule = "cyclomatic-complexity"
    static let lengthRule = "long-function"

    /// Creates a measurer.
    ///
    /// - Parameter analyzers: The analyzer for each measured language.
    public init(analyzers: [Language: LanguageAnalyzer]) {
        self.analyzers = analyzers
    }

    /// Measures a file's functions by analyzing it with the probe settings.
    ///
    /// - Parameter file: The file.
    /// - Returns: Its functions in line order, or `nil` for an unmeasured language or a parse failure.
    public func functions(in file: SourceFile) -> [FunctionMeasure]? {
        guard let analyzer = analyzers[file.language] else { return nil }
        let context = AnalysisContext(repoRoot: file.path.deletingLastPathComponent(), ruleSettings: Self.probe)
        guard let findings = try? analyzer.analyze(file: file, context: context) else { return nil }
        return Self.measures(from: findings)
    }

    /// Settings that make both measuring rules report every function, and switch off the text-level rules
    /// every analyzer runs, which only cost time here. A rule left out of this list still runs; its findings
    /// are ignored, so the list is purely a speed-up.
    static let probe: [String: RuleSettings] = Dictionary(uniqueKeysWithValues: textRules.map { ($0, off) })
        .merging([complexityRule: zeroLimit("max"), lengthRule: zeroLimit("maxLines")]) { $1 }

    /// The text-level rules `TextRules` gives every language, by ID.
    static let textRules = [
        "file-length", "long-lines", "todo-density", "duplicate-block", "trailing-whitespace",
        "secret-looking-pattern", "deep-nesting", "missing-final-newline", "crlf-line-endings",
        "mixed-indentation", "consecutive-blank-lines", "commented-out-code", "redundant-comment", "weak-crypto",
        "disabled-tls-verification", "insecure-http-url", "sql-string-building"
    ]

    /// Settings that switch a rule off.
    private static let off = RuleSettings(enabled: false, severity: .info, parameters: .empty)

    /// Builds settings that enable a rule with one limit at 0.
    ///
    /// - Parameter parameter: The limit's parameter name.
    /// - Returns: The settings.
    private static func zeroLimit(_ parameter: String) -> RuleSettings {
        RuleSettings(enabled: true, severity: .info, parameters: RuleParameters(values: [parameter: .int(0)]))
    }

    /// Combines the two rules' findings into one measurement per function, matched by line.
    ///
    /// - Parameter findings: The probe run's findings.
    /// - Returns: A measurement per function with a complexity finding, in line order.
    static func measures(from findings: [Finding]) -> [FunctionMeasure] {
        let lengths = lengthsByLine(findings)
        return findings.filter { $0.ruleID == complexityRule }.compactMap { finding in
            number(before: ", over the", in: finding.message).map {
                FunctionMeasure(name: name(in: finding.message), line: finding.line, complexity: $0,
                                logicalLines: lengths[finding.line])
            }
        }.sorted { $0.line < $1.line }
    }

    /// Reads each function's logical line count from the `long-function` findings.
    ///
    /// - Parameter findings: The probe run's findings.
    /// - Returns: Each function's length, keyed by its line.
    private static func lengthsByLine(_ findings: [Finding]) -> [Int: Int] {
        let pairs = findings.filter { $0.ruleID == lengthRule }.compactMap { finding in
            number(before: " logical lines", in: finding.message).map { (finding.line, $0) }
        }
        return Dictionary(pairs) { first, _ in first }
    }

    /// Reads the function name from a message that starts `Function "name"`.
    ///
    /// - Parameter message: The finding's message.
    /// - Returns: The name, or `nil` if the message doesn't name one.
    static func name(in message: String) -> String? {
        let prefix = "Function \""
        guard message.hasPrefix(prefix) else { return nil }
        let rest = message.dropFirst(prefix.count)
        return rest.firstIndex(of: "\"").map { String(rest[..<$0]) }
    }

    /// Reads the whole number written immediately before a marker.
    ///
    /// - Parameters:
    ///   - marker: The text that follows the number, such as `", over the"`.
    ///   - message: The finding's message.
    /// - Returns: The number, or `nil` if the marker isn't preceded by digits.
    static func number(before marker: String, in message: String) -> Int? {
        guard let range = message.range(of: marker) else { return nil }
        let digits = message[..<range.lowerBound].reversed().prefix { $0.isNumber }
        return Int(String(digits.reversed()))
    }
}
