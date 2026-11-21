import Foundation
import BouncerCore

/// Where in a sink's first argument request input must appear for the sink to be flagged.
public enum ArgumentReach: Sendable {
    /// The argument must start with it (after a `URL(string:`-style wrapper), so a literal prefix such as
    /// `"https://api.example.com/" + id` or `"/login?next=" + next` fixes the host and clears the call.
    case leading
    /// Anywhere in the argument, including inside an f-string or template-literal interpolation.
    case anywhere
}

/// Declares a request-input-reaches-a-sink rule as data, for `RequestSinkRule`.
public struct RequestSinkSpec: Sendable {
    /// The rule's stable identifier.
    public let id: String
    /// The message shown for a flagged call.
    public let message: String
    /// The calls, per language, whose first argument starts right where each pattern's match ends.
    public let sinks: [SecurityPattern]
    /// Lines flagged whatever the argument's source: a sink handed a string built on the spot.
    public let direct: [SecurityPattern]
    /// Where the request input must appear in the argument.
    public let reach: ArgumentReach
    /// A check, such as an allowlist or `is_safe_url`, that clears the sink when it appears on its line or in the
    /// lines above it that the taint window covers.
    let validation: NSRegularExpression?

    /// Creates a specification.
    ///
    /// - Parameters:
    ///   - id: The rule's stable identifier.
    ///   - message: The message shown for a flagged call.
    ///   - calls: The sinks, per language, whose first argument follows each match, and the patterns flagged on
    ///     their own (none by default).
    ///   - reach: Where the request input must appear in the argument.
    ///   - validation: A pattern for a check that clears the sink, or `nil`.
    public init(id: String, message: String, calls: (sinks: [SecurityPattern], direct: [SecurityPattern]),
                reach: ArgumentReach, validation: String? = nil) {
        (self.id, self.message, sinks, direct, self.reach) = (id, message, calls.sinks, calls.direct, reach)
        self.validation = validation.flatMap(TextMatching.regex)
    }
}

/// Flags request input reaching an outbound request, a redirect, or a template engine, following it the way
/// `path-traversal` does: a request source (`req.query`, `request.args`, `r.URL.Query()`, `getParameter(`, …) in
/// the sink's first argument, or a variable assigned from one in the 10 lines above and not reassigned since. The
/// argument is the text after the sink up to its first top-level comma or closing bracket. Values passed through
/// `int(`, `parseInt`, `Atoi`, or a `sanitize…` call don't count, and test files are skipped.
public struct RequestSinkRule: Rule {
    public let id: String
    private let spec: RequestSinkSpec
    private static let window = 10
    private static let wrapper = TextMatching.regex(
        #"^(?:\s|new\s+URL\(|URL\(string:|URI\(string:|URI\.create\(|NSURL\s+URLWithString:|String\(|str\(|"#
            + #"encodeURI\()*$"#
    )

    /// Creates the rule.
    ///
    /// - Parameter spec: The rule's sinks and conditions.
    public init(spec: RequestSinkSpec) {
        (id, self.spec) = (spec.id, spec)
    }

    /// Flags each sink whose argument carries request input.
    ///
    /// - Parameters:
    ///   - file: The file to scan.
    ///   - context: Repo-wide state, including this rule's resolved settings.
    /// - Returns: One finding per flagged line.
    public func evaluate(file: SourceFile, context: AnalysisContext) -> [Finding] {
        let settings = context.settings(for: id)
        guard settings.enabled, applies(to: file) else { return [] }
        let mayHoldInput = RequestTaint.mayHoldRequestInput(file.contents)
        let flagged = file.lines.indices.filter { index in
            spec.direct.contains { $0.matches(at: index, in: file) } || mayHoldInput && reachesSink(at: index, in: file)
        }
        return SourceText.flagCodeLines(id, settings, file) { Set(flagged).contains($0) ? spec.message : nil }
    }

    /// Reports whether the rule reads a file: one in a language it has sinks for, outside the tests.
    ///
    /// - Parameter file: The file.
    /// - Returns: Whether a sink or direct pattern applies to its language and it isn't a test file.
    private func applies(to file: SourceFile) -> Bool {
        let patterns = spec.sinks + spec.direct
        return patterns.contains { $0.languages.contains(file.language) } && !TextMatching.isTestPath(file.path)
    }

    /// Reports whether a line hands request input to one of the rule's sinks, unchecked.
    ///
    /// - Parameters:
    ///   - index: The line's 0-based index.
    ///   - file: The file it's in.
    /// - Returns: Whether a sink's first argument carries request input and no validation clears it.
    private func reachesSink(at index: Int, in file: SourceFile) -> Bool {
        guard let argument = sinkArgument(at: index, in: file),
              !TextMatching.matches(PathTraversalRule.sanitizer, argument) else { return false }
        let window = file.lines[max(0, index - Self.window)...index]
        guard !window.contains(where: { TextMatching.matches(spec.validation, $0) }) else { return false }
        let tainted = RequestTaint.names(before: index, in: file, window: Self.window)
        return carriesInput(argument, tainted: tainted)
    }

    /// Reads the first argument of the first sink on a line: its code with string contents blanked, followed, for
    /// `.anywhere`, by the expressions interpolated into its strings.
    ///
    /// - Parameters:
    ///   - index: The line's 0-based index.
    ///   - file: The file it's in.
    /// - Returns: The argument's code, or `nil` if no sink for the file's language is on the line.
    private func sinkArgument(at index: Int, in file: SourceFile) -> String? {
        let raw = String(file.lines[index]), code = SourceText.code(of: raw)
        let ends = spec.sinks.filter { $0.languages.contains(file.language) }.compactMap { sink in
            SinkArguments.end(of: sink, in: raw, code: code)
        }
        guard let end = ends.min() else { return nil }
        let argument = SinkArguments.first(in: (code as NSString).substring(from: end))
        guard spec.reach == .anywhere else { return argument }
        let written = (raw as NSString).substring(with: NSRange(location: end, length: (argument as NSString).length))
        return argument + " " + LogArguments.interpolations(in: written)
    }

    /// Reports whether an argument carries request input where the rule's reach requires.
    ///
    /// - Parameters:
    ///   - argument: The argument's code, with interpolations appended.
    ///   - tainted: The names holding request input.
    /// - Returns: Whether a request source or tainted name appears, leading the argument for `.leading`.
    private func carriesInput(_ argument: String, tainted: Set<String>) -> Bool {
        let positions = SinkArguments.inputPositions(in: argument, tainted: tainted)
        switch spec.reach {
        case .anywhere: return !positions.isEmpty
        case .leading:
            return positions.contains { TextMatching.matches(Self.wrapper, (argument as NSString).substring(to: $0)) }
        }
    }
}

/// Reads sink arguments for `RequestSinkRule`.
enum SinkArguments {
    /// Finds where a sink's first argument starts on a line, if the sink is there in code rather than in a string.
    ///
    /// - Parameters:
    ///   - sink: The sink pattern; its match ends where the argument starts.
    ///   - raw: The line as written.
    ///   - code: The same line with strings blanked and any trailing comment cut.
    /// - Returns: The argument's UTF-16 offset, or `nil` if the sink isn't on the line's code.
    static func end(of sink: SecurityPattern, in raw: String, code: String) -> Int? {
        let range = NSRange(location: 0, length: (raw as NSString).length)
        guard let match = sink.regex?.firstMatch(in: raw, range: range),
              match.range.location < (code as NSString).length else { return nil }
        let first = (raw as NSString).substring(with: NSRange(location: match.range.location, length: 1))
        let inCode = (code as NSString).substring(with: NSRange(location: match.range.location, length: 1)) == first
        return inCode && NSMaxRange(match.range) <= (code as NSString).length ? NSMaxRange(match.range) : nil
    }

    /// Cuts an argument list down to its first argument: up to the first comma or closing bracket at depth zero.
    ///
    /// - Parameter text: The text after the sink.
    /// - Returns: The first argument's text.
    static func first(in text: String) -> String {
        var depth = 0
        let end = text.firstIndex { char in
            if "([{".contains(char) { depth += 1 } else if ")]}".contains(char) { depth -= 1 }
            return depth < 0 || (depth == 0 && char == ",")
        }
        return String(text[..<(end ?? text.endIndex)])
    }

    /// Lists where request input appears in an argument: each request source and each tainted name.
    ///
    /// - Parameters:
    ///   - argument: The argument's code.
    ///   - tainted: The names holding request input.
    /// - Returns: The UTF-16 offsets of each appearance, in order.
    static func inputPositions(in argument: String, tainted: Set<String>) -> [Int] {
        let range = NSRange(location: 0, length: (argument as NSString).length)
        let sources = PathTraversalRule.source?.matches(in: argument, range: range).map(\.range.location) ?? []
        let names = tainted.flatMap { name in
            let pattern = #"(?<![\w$.])"# + NSRegularExpression.escapedPattern(for: name) + #"(?![\w$])"#
            return TextMatching.regex(pattern)?.matches(in: argument, range: range).map(\.range.location) ?? []
        }
        return (sources + names).sorted()
    }
}
