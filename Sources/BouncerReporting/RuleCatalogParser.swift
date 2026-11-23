import Foundation

/// One cell of a catalog table row, under its column's header.
struct CatalogCell: Sendable, Equatable {
    /// The column's header, such as `Checks` or `Default severity`.
    let header: String
    /// The cell's Markdown, trimmed.
    let text: String
}

/// One row of a rule catalog table that documents one or more rules.
struct CatalogRow: Sendable, Equatable {
    /// The plain-text title of the `##` section the table sits in.
    let section: String
    /// The row's cells, in column order.
    let cells: [CatalogCell]
    /// The rule IDs the row's `Rule ID` cell names.
    let ruleIDs: [String]

    /// The text of the cell under a header.
    ///
    /// - Parameter header: The column's header.
    /// - Returns: The cell's Markdown, or `nil` if the row has no such column.
    func cell(_ header: String) -> String? {
        cells.first { $0.header == header }?.text
    }
}

/// Reads the rule tables out of the rule catalog article's Markdown.
///
/// A table is a run of lines starting with `|`: a header row, a separator row, then data rows. A data row is
/// kept when its key cell (`Rule ID` by default) names at least one backticked rule ID; tables without that
/// column are skipped.
struct RuleCatalogParser {
    /// The header of the column that names a row's rules in the rule tables.
    static let ruleIDHeader = "Rule ID"

    /// The header of the column whose cell names each kept row's rules.
    private let keyHeader: String
    /// The rows read so far.
    private var rows: [CatalogRow] = []
    /// The current `##` section's plain title.
    private var section = ""
    /// The current table's headers, or `nil` outside a table.
    private var headers: [String]?

    /// Reads every rule row from the article.
    ///
    /// - Parameters:
    ///   - markdown: The article's Markdown.
    ///   - keyHeader: The header of the column that names each row's rules; tables without it are skipped.
    /// - Returns: The rows that name rules, in article order.
    static func rows(in markdown: String, keyedBy keyHeader: String = ruleIDHeader) -> [CatalogRow] {
        var parser = RuleCatalogParser(keyHeader: keyHeader)
        let lines = markdown.replacingOccurrences(of: "\r", with: "").components(separatedBy: "\n")
        lines.forEach { parser.read($0) }
        return parser.rows
    }

    /// Reads one line: a section heading, a table line, or anything else, which ends a table.
    ///
    /// - Parameter line: The line, without its newline.
    private mutating func read(_ line: String) {
        if line.hasPrefix("## ") { section = MarkdownText.plain(String(line.dropFirst("## ".count))) }
        guard line.hasPrefix("|") else { headers = nil; return }
        let cells = Self.cells(of: line)
        guard let headers else { self.headers = cells; return }
        guard !Self.isSeparator(cells) else { return }
        append(cells, under: headers)
    }

    /// Records a data row if it names any rules.
    ///
    /// - Parameters:
    ///   - values: The row's cells.
    ///   - headers: The table's headers.
    private mutating func append(_ values: [String], under headers: [String]) {
        let cells = zip(headers, values).map { CatalogCell(header: $0, text: $1) }
        let ids = Self.ruleIDs(in: cells.first { $0.header == keyHeader }?.text ?? "")
        guard !ids.isEmpty else { return }
        rows.append(CatalogRow(section: section, cells: cells, ruleIDs: ids))
    }

    /// Splits a table line into trimmed cells, keeping an escaped `\|` inside its cell.
    ///
    /// - Parameter line: A line starting and ending with `|`.
    /// - Returns: The cells between the pipes.
    static func cells(of line: String) -> [String] {
        let pieces = line.dropFirst().components(separatedBy: "|")
        let cells = pieces.reduce(into: [String]()) { cells, piece in
            if let last = cells.last, last.hasSuffix("\\") {
                cells[cells.count - 1] = last + "|" + piece
            } else {
                cells.append(piece)
            }
        }
        return cells.dropLast().map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// Checks whether a row is a table's `|---|---|` separator.
    ///
    /// - Parameter cells: The row's cells.
    /// - Returns: Whether every cell holds only dashes and colons.
    static func isSeparator(_ cells: [String]) -> Bool {
        cells.allSatisfy { cell in !cell.isEmpty && cell.allSatisfy { $0 == "-" || $0 == ":" } }
    }

    /// The backticked rule IDs that open a `Rule ID` cell, such as both IDs in `` `a-rule`, `b-rule` (Swift) ``.
    ///
    /// Code after the first other text, such as a parameter named in a language note, isn't a rule ID.
    ///
    /// - Parameter cell: The cell's Markdown.
    /// - Returns: The IDs, in order.
    static func ruleIDs(in cell: String) -> [String] {
        let pieces = cell.components(separatedBy: "`")
        guard pieces.first?.trimmingCharacters(in: .whitespaces).isEmpty == true else { return [] }
        let separators = stride(from: 0, to: pieces.count, by: 2).map { pieces[$0] }
        let leading = separators.dropFirst().prefix { $0.allSatisfy { $0 == "," || $0 == " " } }.count
        let code = stride(from: 1, to: pieces.count, by: 2).map { pieces[$0] }
        return Array(code.prefix(leading + 1)).filter(isRuleID)
    }

    /// Checks whether text has a rule ID's shape: lowercase letters, digits, and dashes.
    ///
    /// - Parameter text: The candidate.
    /// - Returns: Whether it could be a rule ID.
    static func isRuleID(_ text: String) -> Bool {
        !text.isEmpty && text.allSatisfy { $0.isLowercase || $0.isNumber || $0 == "-" } && text.first != "-"
    }
}

/// Turns catalog Markdown into plain text.
enum MarkdownText {
    /// Strips Markdown: backticks, emphasis, `[text](link)` links, `<doc:Name>` references, and `\|` escapes.
    ///
    /// - Parameter markdown: The Markdown.
    /// - Returns: The plain text.
    static func plain(_ markdown: String) -> String {
        markdown
            .replacingOccurrences(of: #"\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"<doc:([^>]*)>"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "\\|", with: "|")
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "`", with: "")
    }
}
