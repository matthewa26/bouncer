import Foundation

/// One fenced code block in the rule examples article: its language, its role, and its lines.
struct ExampleFence: Sendable, Equatable {
    /// The language the fence names, such as `swift`.
    let language: String
    /// The role the fence names: `before`, `after`, or empty for an untagged fence.
    let role: String
    /// The block's lines, without the fence lines, indentation kept.
    var lines: [String] = []

    /// The block's code, its lines joined by newlines.
    var code: String {
        lines.joined(separator: "\n")
    }
}

/// Reads the examples out of the rule examples article's Markdown.
///
/// An example is a `###` heading naming a rule ID, then a fenced block tagged `<language> before` and one tagged
/// `<language> after` in the same language. Anything else, such as prose or a `##` section heading, is skipped.
struct RuleExampleParser {
    /// The line that opens and closes a fenced code block.
    static let fenceMarker = "```"

    /// The examples read so far, keyed by rule ID.
    private var examples: [String: RuleExample] = [:]
    /// The rule ID the current `###` heading names.
    private var ruleID: String?
    /// The fenced block being read, or `nil` outside one.
    private var fence: ExampleFence?
    /// The current rule's `before` block, once read.
    private var before: ExampleFence?

    /// Reads every example from the article.
    ///
    /// - Parameter markdown: The article's Markdown.
    /// - Returns: The examples, keyed by rule ID.
    static func examples(in markdown: String) -> [String: RuleExample] {
        var parser = RuleExampleParser()
        let lines = markdown.replacingOccurrences(of: "\r", with: "").components(separatedBy: "\n")
        lines.forEach { parser.read($0) }
        return parser.examples
    }

    /// Reads one line: a fence's code or closing line, a rule heading, or a fence's opening line.
    ///
    /// - Parameter line: The line, without its newline.
    private mutating func read(_ line: String) {
        if fence != nil { readInFence(line); return }
        if line.hasPrefix("### ") {
            ruleID = Self.ruleID(inHeading: line)
            before = nil
        } else if line.hasPrefix(Self.fenceMarker) {
            fence = Self.opening(line)
        }
    }

    /// Reads a line inside a fenced block: a code line, or the line that closes the block.
    ///
    /// - Parameter line: The line.
    private mutating func readInFence(_ line: String) {
        guard line == Self.fenceMarker, let closed = fence else { fence?.lines.append(line); return }
        fence = nil
        if closed.role == "before" { before = closed }
        if closed.role == "after" { record(after: closed) }
    }

    /// Records the current rule's example from its `before` block and the `after` block just read.
    ///
    /// - Parameter after: The `after` block.
    private mutating func record(after: ExampleFence) {
        guard let ruleID, let before, before.language == after.language else { return }
        examples[ruleID] = RuleExample(language: before.language, before: before.code, after: after.code)
        self.before = nil
    }

    /// Reads the rule ID out of a `###` heading, such as ``### `trailing-whitespace` ``.
    ///
    /// - Parameter line: The heading line.
    /// - Returns: The rule ID, without backticks.
    static func ruleID(inHeading line: String) -> String {
        line.dropFirst("### ".count).replacingOccurrences(of: "`", with: "").trimmingCharacters(in: .whitespaces)
    }

    /// Reads a fence's opening line, such as ` ```swift before `.
    ///
    /// - Parameter line: The opening line.
    /// - Returns: The empty block, with the language and role the line names (empty when it names none).
    static func opening(_ line: String) -> ExampleFence {
        let words = line.dropFirst(fenceMarker.count).split(separator: " ").map(String.init)
        guard words.count == 2 else { return ExampleFence(language: words.first ?? "", role: "") }
        return ExampleFence(language: words[0], role: words[1])
    }
}
