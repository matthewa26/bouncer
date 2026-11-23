import Foundation
import BouncerCore

/// One rule's example from `RuleExamples.md`, read straight from the article so an analyzer test can check that
/// the rule reports its `before` code and not its `after` code.
struct RuleExampleFixture {
    /// The fence's language, such as `typescript`.
    let language: String
    /// The code the rule should report, ending in a newline.
    let before: String
    /// The fixed code, ending in a newline.
    let after: String

    /// Every example in the article, keyed by rule ID.
    static func all() throws -> [String: RuleExampleFixture] {
        let article = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/BouncerCore/BouncerCore.docc/Articles/RuleExamples.md")
        var examples: [String: RuleExampleFixture] = [:], rule = "", blocks: [(info: String, lines: [String])] = []
        var open: (info: String, lines: [String])?
        for line in try String(contentsOf: article, encoding: .utf8).components(separatedBy: "\n") {
            if var block = open {
                if line == "```" { blocks.append(block); open = nil } else { block.lines.append(line); open = block }
            } else if line.hasPrefix("### ") {
                rule = line.dropFirst("### ".count).replacingOccurrences(of: "`", with: "")
                blocks = []
            } else if line.hasPrefix("```") {
                open = (String(line.dropFirst("```".count)), [])
            }
            guard blocks.count == 2 else { continue }
            examples[rule] = RuleExampleFixture(
                language: String(blocks[0].info.split(separator: " ")[0]),
                before: blocks[0].lines.joined(separator: "\n") + "\n", after: blocks[1].lines.joined(separator: "\n") + "\n"
            )
            blocks = []
        }
        return examples
    }

    /// The path a side's `// File:` or `# File:` first line names, if it names one.
    ///
    /// - Parameter code: One side of the example.
    /// - Returns: The path, or `nil`.
    static func path(in code: String) -> String? {
        guard let first = code.split(separator: "\n").first else { return nil }
        let comment = first.drop { $0 == "/" || $0 == "#" }.trimmingCharacters(in: .whitespaces)
        guard comment.hasPrefix("File: ") else { return nil }
        return comment.dropFirst("File: ".count).split(whereSeparator: { $0 == " " || $0 == "," }).first.map(String.init)
    }

    /// Settings that turn the rule on with its default parameters, so opt-in rules run too.
    ///
    /// - Parameter ruleID: The rule.
    /// - Returns: The settings.
    static func settings(enabling ruleID: String) -> [String: RuleSettings] {
        [ruleID: RuleSettings(enabled: true, severity: .warning, parameters: .empty)]
    }
}
