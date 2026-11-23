import Foundation
import BouncerCore

/// Writes a rule's explanation from the catalog rows that document it.
///
/// The text is plain and compact, one fact per line: the rule and its catalog section, each documenting row
/// (language, what it checks, default severity, parameters), the OWASP category, how to configure it in
/// `.bouncer`, and how to suppress one finding inline.
struct RuleExplanationWriter {
    /// Headers whose cells name a row's languages.
    private static let languageHeaders: Set<String> = ["Language", "Languages"]
    /// Headers left out of a row's sentences: the ID is in the first line, the OWASP category gets its own, and
    /// the languages lead the row.
    private static let skippedHeaders = languageHeaders.union([RuleCatalogParser.ruleIDHeader, "Category"])
    /// How each known column is labeled in a row's line; `Checks` needs no label.
    private static let labels = ["Checks": "", "Default severity": "Default: ", "Parameters": "Parameters: "]
    /// Phrases in a row that mean the rule does nothing until a `.bouncer` turns it on.
    private static let offPhrases = ["off unless configured", "until configured", "so off"]

    /// The rule's ID.
    let ruleID: String
    /// The catalog rows that document it, in article order.
    let rows: [CatalogRow]

    /// The whole explanation.
    var text: String {
        ([heading] + rows.map(line(for:)) + [owasp, configuration, suppression].compactMap { $0 })
            .joined(separator: "\n")
    }

    /// The first line: the rule and the catalog sections it's in.
    private var heading: String {
        var seen = Set<String>()
        let sections = rows.map(\.section).filter { seen.insert($0).inserted }
        return "\(ruleID) (rule catalog: \(sections.joined(separator: "; ")))"
    }

    /// One row's line: its languages, then each remaining cell.
    ///
    /// - Parameter row: The row.
    /// - Returns: A line such as `- [Swift] A force unwrap, x!. Default: warning. Parameters: none.`
    private func line(for row: CatalogRow) -> String {
        let languages = Self.languages(of: row)
        let prefix = languages.isEmpty ? "- " : "- [\(languages)] "
        let kept = row.cells.filter { !Self.skippedHeaders.contains($0.header) }
        return prefix + kept.map(Self.sentence).joined(separator: " ")
    }

    /// The languages a row names: its `Language`/`Languages` cell, or the note after the IDs in its `Rule ID` cell.
    ///
    /// - Parameter row: The row.
    /// - Returns: The languages as plain text, or an empty string when the row names none.
    private static func languages(of row: CatalogRow) -> String {
        let languageCell = row.cells.first { languageHeaders.contains($0.header) }
        if let languageCell { return MarkdownText.plain(languageCell.text) }
        let note = row.ruleIDs.reduce(row.cell(RuleCatalogParser.ruleIDHeader) ?? "") {
            $0.replacingOccurrences(of: "`\($1)`", with: "")
        }
        return MarkdownText.plain(note.trimmingCharacters(in: CharacterSet(charactersIn: " ,()")))
    }

    /// One cell as a labeled sentence.
    ///
    /// - Parameter cell: The cell.
    /// - Returns: Its plain text, labeled by its column and ending in a period.
    private static func sentence(_ cell: CatalogCell) -> String {
        let text = (labels[cell.header] ?? "\(cell.header): ") + MarkdownText.plain(cell.text)
        return text.hasSuffix(".") ? text : text + "."
    }

    /// The rule's OWASP Top 10:2025 category, when it's a security rule.
    private var owasp: String? {
        OWASPCategory.category(forRule: ruleID).map { "OWASP: \($0.rawValue) \($0.title)." }
    }

    /// How to turn the rule off or on, change its severity, and set a parameter in `.bouncer`.
    private var configuration: String {
        let offByDefault = rows.contains { row in
            row.cells.contains { cell in Self.offPhrases.contains { cell.text.contains($0) } }
        }
        let toggle = "{\"\(ruleID)\": {\"enabled\": \(offByDefault)}} turns it \(offByDefault ? "on" : "off")"
        let parameter = rows.lazy.compactMap { ParameterExample.first(in: $0.cell("Parameters") ?? "") }.first
        let tuning = parameter.map { "; \"params\": {\($0)} tunes it" } ?? ""
        return "Configure in .bouncer \"rules\": \(toggle); \"severity\": \"error\" sets its level\(tuning)."
    }

    /// How to silence one finding with a comment.
    private var suppression: String {
        "Suppress one finding: // bouncer:disable-line \(ruleID) -- reason (on its line; disable-next-line "
            + "for the line below; any comment marker: //, #, --)."
    }
}

/// Finds a `.bouncer` example for a rule's parameter in a catalog `Parameters` cell.
enum ParameterExample {
    /// A parameter written as `` `name` (default) ``, the catalog's form.
    private static let pattern = #"`[A-Za-z][A-Za-z0-9]*` \([^)]*\)"#

    /// The first parameter whose default is a number, a boolean, or a backticked word, as a JSON pair.
    ///
    /// - Parameter cell: The `Parameters` cell's Markdown, such as `` `maxLines` (40) ``.
    /// - Returns: A pair such as `"maxLines": 40`, or `nil` when no parameter has a usable default.
    static func first(in cell: String) -> String? {
        var searchStart = cell.startIndex
        while let match = cell.range(of: pattern, options: .regularExpression, range: searchStart..<cell.endIndex) {
            if let pair = pair(from: String(cell[match])) { return pair }
            searchStart = match.upperBound
        }
        return nil
    }

    /// Converts one `` `name` (default) `` match into a JSON pair.
    ///
    /// - Parameter match: The matched text.
    /// - Returns: The pair, or `nil` when the default isn't a literal value.
    private static func pair(from match: String) -> String? {
        let parts = match.components(separatedBy: "`")
        guard parts.count > 1, let open = match.firstIndex(of: "(") else { return nil }
        let value = match[match.index(after: open)...].dropLast()
        return json(for: String(value)).map { "\"\(parts[1])\": \($0)" }
    }

    /// Writes a catalog default as a JSON value.
    ///
    /// - Parameter value: The text between the parentheses, such as `40`, `true`, or `` `lcom4` ``.
    /// - Returns: The JSON value, or `nil` for prose such as `none` or `see below`.
    private static func json(for value: String) -> String? {
        if Double(value) != nil || value == "true" || value == "false" { return value }
        let word = value.trimmingCharacters(in: CharacterSet(charactersIn: "`"))
        let isWord = value.hasPrefix("`") && !word.isEmpty && !word.contains(" ") && !word.contains("`")
        return isWord ? "\"\(word)\"" : nil
    }
}
