/// Why each rule matters, read from the rule catalog's "Why each rule matters" section.
extension RuleCatalog {
    /// The header of the rationale table's column that names each row's rule.
    static let rationaleRuleHeader = "Rule"
    /// The header of the rationale table's column that says why the rule matters.
    static let rationaleHeader = "Why it matters"

    /// Each rule's rationale as plain text, keyed by rule ID, parsed once from the catalog's rationale table.
    private static let rationalesByRule: [String: String] = {
        let rows = RuleCatalogParser.rows(in: RuleCatalogText.markdown, keyedBy: rationaleRuleHeader)
        let pairs = rows.flatMap { row in
            row.cell(rationaleHeader).map { text in row.ruleIDs.map { ($0, MarkdownText.plain(text)) } } ?? []
        }
        return Dictionary(pairs) { first, _ in first }
    }()

    /// Explains why a rule's findings are worth fixing.
    ///
    /// - Parameter ruleID: The rule's ID, matched exactly.
    /// - Returns: A sentence or two on the harm the rule guards against, as plain text with the catalog's
    ///   Markdown (backticks included) stripped, or `nil` if the catalog has none.
    static func rationale(for ruleID: String) -> String? {
        rationalesByRule[ruleID]
    }

    /// Every rule ID the catalog's rationale table names, sorted, so tests can check it against `ruleIDs`.
    static var rationaleRuleIDs: [String] {
        rationalesByRule.keys.sorted()
    }
}
