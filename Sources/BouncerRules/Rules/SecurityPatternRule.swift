import Foundation
import BouncerCore

/// One regular expression a `SecurityPatternRule` looks for, the languages it applies to, and what else must hold.
public struct SecurityPattern: Sendable {
    /// What must hold, beyond the line matching, for a match to count.
    public enum Context: Sendable {
        /// The line or one of the `SecurityPattern.nearbyLines` above it must match this pattern.
        case nearby(String)
        /// The file's text must match this pattern somewhere.
        case file(String)
        /// The file's path must match this pattern.
        case path(String)
    }

    /// How many lines above a match a `.nearby` context is looked for.
    public static let nearbyLines = 8

    /// The languages the pattern applies to.
    public let languages: [Language]
    /// The compiled pattern a code line must match.
    let regex: NSRegularExpression?
    /// The compiled context pattern, and what it's matched against.
    let context: (kind: Context, regex: NSRegularExpression?)?

    /// Creates a pattern.
    ///
    /// - Parameters:
    ///   - languages: The languages it applies to.
    ///   - pattern: The regular expression a code line must match.
    ///   - context: What else must hold for a match to count, or `nil` for nothing.
    public init(_ languages: [Language], _ pattern: String, context: Context? = nil) {
        self.languages = languages
        regex = TextMatching.regex(pattern)
        self.context = context.map { ($0, TextMatching.regex(Self.contextPattern(of: $0))) }
    }

    /// Reads a context's pattern.
    ///
    /// - Parameter context: The context.
    /// - Returns: Its regular expression.
    private static func contextPattern(of context: Context) -> String {
        switch context {
        case .nearby(let pattern), .file(let pattern), .path(let pattern): pattern
        }
    }

    /// Reports whether a line matches the pattern and its context holds.
    ///
    /// - Parameters:
    ///   - index: The line's 0-based index.
    ///   - file: The file it's in.
    /// - Returns: Whether the line counts as a match.
    func matches(at index: Int, in file: SourceFile) -> Bool {
        guard languages.contains(file.language), TextMatching.matches(regex, file.lines[index]) else { return false }
        guard let (kind, contextRegex) = context else { return true }
        return holds(kind, contextRegex, at: index, in: file)
    }

    /// Reports whether a pattern's context holds for a matching line.
    ///
    /// - Parameters:
    ///   - kind: What the context pattern is matched against.
    ///   - contextRegex: The context pattern.
    ///   - index: The matching line's 0-based index.
    ///   - file: The file it's in.
    /// - Returns: Whether the context pattern matches nearby, in the file, or in its path.
    private func holds(_ kind: Context, _ contextRegex: NSRegularExpression?, at index: Int, in file: SourceFile)
        -> Bool {
        switch kind {
        case .nearby:
            file.lines[max(0, index - Self.nearbyLines)...index].contains { TextMatching.matches(contextRegex, $0) }
        case .file: TextMatching.matches(contextRegex, file.contents)
        case .path: TextMatching.matches(contextRegex, file.path.path)
        }
    }
}

/// Declares a security rule as data: its patterns per language, plus file- and line-level conditions.
public struct SecurityPatternSpec: Sendable {
    /// The rule's stable identifier.
    public let id: String
    /// The message shown for a match.
    public let message: String
    /// The patterns, any one of which flags a line.
    public let patterns: [SecurityPattern]
    /// A pattern the file must contain for the rule to run, or `nil`.
    let fileGate: NSRegularExpression?
    /// A pattern that, anywhere in the file, turns the rule off for it, or `nil`.
    let fileExclusion: NSRegularExpression?
    /// A pattern that, on a matching line, clears it, or `nil`.
    let lineExclusion: NSRegularExpression?

    /// Creates a specification.
    ///
    /// - Parameters:
    ///   - id: The rule's stable identifier.
    ///   - message: The message shown for a match.
    ///   - patterns: The patterns, any one of which flags a line.
    ///   - conditions: The file gate, file exclusion, and line exclusion patterns, each optional.
    public init(id: String, message: String, patterns: [SecurityPattern],
                conditions: (fileGate: String?, fileExclusion: String?, lineExclusion: String?) = (nil, nil, nil)) {
        (self.id, self.message, self.patterns) = (id, message, patterns)
        fileGate = conditions.fileGate.flatMap(TextMatching.regex)
        fileExclusion = conditions.fileExclusion.flatMap(TextMatching.regex)
        lineExclusion = conditions.lineExclusion.flatMap(TextMatching.regex)
    }

    /// Reports whether the rule should read a file at all.
    ///
    /// - Parameter file: The file.
    /// - Returns: Whether a pattern applies to its language, its gate matches, and nothing excludes it.
    func applies(to file: SourceFile) -> Bool {
        guard patterns.contains(where: { $0.languages.contains(file.language) }),
              !TextMatching.isTestPath(file.path) else { return false }
        return (fileGate.map { TextMatching.matches($0, file.contents) } ?? true)
            && !(fileExclusion.map { TextMatching.matches($0, file.contents) } ?? false)
    }
}

/// A security rule declared as `SecurityPatternSpec` data: it flags each code line (not a comment or the inside of
/// a multi-line string) that one of its patterns for the file's language matches. Test files are skipped, since
/// they set up insecure configurations on purpose.
public struct SecurityPatternRule: Rule {
    public let id: String
    private let spec: SecurityPatternSpec

    /// Creates the rule.
    ///
    /// - Parameter spec: The rule's patterns and conditions.
    public init(spec: SecurityPatternSpec) {
        self.spec = spec
        id = spec.id
    }

    /// Flags each code line one of the rule's patterns matches.
    ///
    /// - Parameters:
    ///   - file: The file to scan.
    ///   - context: Repo-wide state, including this rule's resolved settings.
    /// - Returns: One finding per flagged line.
    public func evaluate(file: SourceFile, context: AnalysisContext) -> [Finding] {
        let settings = context.settings(for: id)
        guard settings.enabled, spec.applies(to: file) else { return [] }
        return SourceText.flagCodeLines(id, settings, file) { index in
            guard spec.patterns.contains(where: { $0.matches(at: index, in: file) }),
                  !TextMatching.matches(spec.lineExclusion, file.lines[index]) else { return nil }
            return spec.message
        }
    }
}
