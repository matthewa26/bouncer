import ArgumentParser
import Foundation
import BouncerReporting

/// Lists the built-in rules, or explains one, from the rule catalog embedded in the binary.
struct RulesCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "rules", abstract: "List the built-in rules, or explain one.",
        discussion: """
            With no rule ID, prints every rule grouped by catalog section, with its default severity. With an ID, \
            prints what the rule checks, why it matters, its parameters, and how to configure or suppress it: the \
            same text the MCP server's explain_rule tool returns.
            """
    )

    @Argument(help: "A rule ID to explain, such as long-function.")
    var id: String?

    /// Prints the list or the explanation.
    ///
    /// - Throws: `ValidationError` for an unknown rule ID, suggesting close ones.
    func run() throws {
        guard let id else { return print(Self.listing(RuleCatalog.summaries)) }
        guard let explanation = RuleCatalog.explain(id) else { throw ValidationError(RuleExplainer.unknown(id)) }
        print(explanation.text)
    }

    /// The list's last line, pointing at the per-rule explanation.
    private static let footer = "Run bouncer rules <id> for what a rule checks and how to fix, configure, or suppress it."

    /// Writes the rule list: each section's title, then one indented `id  severity` line per rule.
    ///
    /// - Parameter summaries: The rules, in catalog order.
    /// - Returns: The list, ending with a pointer to the per-rule explanation.
    static func listing(_ summaries: [RuleSummary]) -> String {
        let width = summaries.map(\.id.count).max() ?? 0
        var lines: [String] = []
        for (index, summary) in summaries.enumerated() {
            if index == 0 || summaries[index - 1].section != summary.section {
                lines += (lines.isEmpty ? [] : [""]) + [summary.section]
            }
            lines.append(line(for: summary, width: width))
        }
        return (lines + ["", footer]).joined(separator: "\n")
    }

    /// Writes one rule's line.
    ///
    /// - Parameters:
    ///   - summary: The rule.
    ///   - width: The longest rule ID's length, which the IDs are padded to so the severities line up.
    /// - Returns: The ID, then the default severity when the catalog gives one.
    private static func line(for summary: RuleSummary, width: Int) -> String {
        let padded = summary.id.padding(toLength: width, withPad: " ", startingAt: 0)
        return "  " + (summary.severity.map { "\(padded)  \($0)" } ?? summary.id)
    }
}
