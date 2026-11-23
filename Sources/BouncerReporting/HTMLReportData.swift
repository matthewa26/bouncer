import Foundation
import BouncerCore

/// The findings in the compact form the HTML report embeds: each file and rule is written once in a lookup
/// table, and each finding is a short array of indices into those tables, so a report with millions of findings
/// stays small enough for a browser to load. Source lines for the findings' previews are stored per file, and
/// rationales and examples per rule, so none of them is repeated per finding.
struct HTMLReportData: Encodable {
    /// Identifies the report's repository, so the page can remember settings, such as hidden rules, per repository.
    let key: String
    /// The measured line coverage, or `nil` (and left out of the JSON) if coverage wasn't measured.
    let coverage: Double?
    /// The severity names, most severe first; a row's severity index points into this list.
    let severities: [String]
    /// Each file's path relative to the repository root, as the table shows it.
    let files: [String]
    /// Each file's absolute path, in the same order as `files`, as `--format json` writes it.
    let filePaths: [String]
    /// The rule IDs; a row's rule index points into this list.
    let rules: [String]
    /// The findings in the table's first order: most severe first, then by path and line.
    let rows: [Row]
    /// Each rule's OWASP Top 10 category (`"A05:2025"`), or `null`, in the same order as `rules`; `nil`, and left
    /// out of the JSON, when no rule in the report is mapped, so the page hides its category filter.
    let owasp: [String?]?
    /// The title of each category in `owasp` (`"A05:2025": "Injection"`), for the filter's labels.
    let owaspTitles: [String: String]?
    /// Why each rule matters, or `null` where the catalog doesn't say, in the same order as `rules`.
    let why: [String?]
    /// Each rule's generic before-and-after example, or `null`, in the same order as `rules`.
    let examples: [Example?]
    /// The code previews, which `HTMLReporter` embeds in their own element so the page only parses them when a
    /// finding is first expanded; left out of this object's JSON.
    let source: Source

    /// The keys this object's JSON has: every property but `source`.
    private enum CodingKeys: String, CodingKey {
        case key, coverage, severities, files, filePaths, rules, rows, owasp, owaspTitles, why, examples
    }

    /// The code previews, as their own JSON object.
    struct Source: Encodable {
        /// Each file's runs of source lines around its findings, or `null` for a file that couldn't be read or
        /// whose code isn't shown, in the same order as `files`.
        let code: [[Chunk]?]
        /// How many lines of context the page shows above and below a finding's line, and around a quick fix.
        var context = HTMLSourceExcerpts.radius
    }

    /// One finding, encoded as `[fileIndex, line, ruleIndex, severityIndex, message]`, followed by its quick fix
    /// as a sixth element when it has one.
    struct Row: Encodable, Equatable {
        /// The finding's index into `files` and `filePaths`.
        let file: Int
        /// The finding's line.
        let line: Int
        /// The finding's index into `rules`.
        let rule: Int
        /// The finding's index into `severities`.
        let severity: Int
        /// The finding's message.
        let message: String
        /// The finding's quick fix, or `nil` (and left out of the JSON) if it has none.
        let fix: Fix?

        /// Writes the row as a JSON array.
        ///
        /// - Parameter encoder: The encoder.
        /// - Throws: Any error the encoder raises.
        func encode(to encoder: any Encoder) throws {
            var container = encoder.unkeyedContainer()
            try container.encode(file)
            try container.encode(line)
            try container.encode(rule)
            try container.encode(severity)
            try container.encode(message)
            if let fix { try container.encode(fix) }
        }
    }

    /// The severities in the order the page lists them.
    static let severityOrder: [Severity] = [.error, .warning, .info]

    /// Builds the compact data for a result, reading each file with findings once for the code previews.
    ///
    /// - Parameters:
    ///   - result: The analysis result.
    ///   - repoRoot: The repository root, which the table's paths are relative to.
    ///   - lookups: Where file text, rationales, examples, and quick fixes come from.
    init(result: AnalysisResult, repoRoot: URL, lookups: HTMLReportLookups = HTMLReportLookups()) {
        var files = FileTable(repoRoot: repoRoot), rules = Interner()
        let indices = result.findings.map { (file: files.index(of: $0.filePath), rule: rules.index(of: $0.ruleID)) }
        let excerpts = HTMLSourceExcerpts(findings: result.findings, fileIndices: indices.map(\.file),
                                          files: files.urls, lookups: lookups)
        rows = Self.displayOrder(Self.rows(result.findings, indices, fixes: excerpts.fixes), files: files.relative)
        (key, coverage, severities) = (repoRoot.path, result.coverage?.overallLineCoveragePercent, Self.names)
        (self.files, filePaths, self.rules) = (files.relative, files.absolute, rules.values)
        (owasp, owaspTitles) = Self.categories(of: rules.values)
        (why, examples, source) = Self.notes(on: rules.values, code: excerpts.code, lookups: lookups)
    }

    /// Looks up each rule's rationale and example, and wraps the code previews.
    ///
    /// - Parameters:
    ///   - rules: The report's rule IDs.
    ///   - code: Each file's runs of source lines.
    ///   - lookups: Where rationales and examples come from.
    /// - Returns: Each rule's rationale and example, or `nil`, in the order of `rules`, and the previews.
    private static func notes(on rules: [String], code: [[Chunk]?],
                              lookups: HTMLReportLookups) -> ([String?], [Example?], Source) {
        (rules.map(lookups.rationale), rules.map { lookups.example($0).map(Example.init) }, Source(code: code))
    }

    /// Encodes the findings as rows, in the result's order.
    ///
    /// - Parameters:
    ///   - findings: The findings.
    ///   - indices: Each finding's file and rule index.
    ///   - fixes: Each finding's quick fix, if it has one.
    /// - Returns: The rows.
    private static func rows(_ findings: [Finding], _ indices: [(file: Int, rule: Int)], fixes: [Fix?]) -> [Row] {
        findings.indices.map { row(findings[$0], file: indices[$0].file, rule: indices[$0].rule, fix: fixes[$0]) }
    }

    /// Encodes one finding as a row.
    ///
    /// - Parameters:
    ///   - finding: The finding.
    ///   - file: Its index into `files`.
    ///   - rule: Its index into `rules`.
    ///   - fix: Its quick fix, if it has one.
    /// - Returns: The row.
    private static func row(_ finding: Finding, file: Int, rule: Int, fix: Fix?) -> Row {
        Row(file: file, line: finding.line, rule: rule,
            severity: severityOrder.firstIndex(of: finding.severity) ?? 0, message: finding.message, fix: fix)
    }

    /// Looks up each rule's OWASP category, for the page's category filter and the JSON it builds.
    ///
    /// - Parameter rules: The report's rule IDs.
    /// - Returns: Each rule's category ID (or `nil`) and the titles of those used, both `nil` if none is mapped.
    private static func categories(of rules: [String]) -> ([String?]?, [String: String]?) {
        let mapped = rules.map { OWASPCategory.category(forRule: $0) }
        guard mapped.contains(where: { $0 != nil }) else { return (nil, nil) }
        let titles = Dictionary(mapped.compactMap { $0 }.map { ($0.rawValue, $0.title) }) { first, _ in first }
        return (mapped.map { $0?.rawValue }, titles)
    }

    /// The severity names, most severe first.
    private static var names: [String] { severityOrder.map(\.rawValue) }

    /// Sorts rows the way the table first shows them, so the page never has to: most severe first, then by
    /// relative path and line, keeping the result's order among equal rows. Each file's path is ranked once, so
    /// sorting millions of rows compares only integers.
    ///
    /// - Parameters:
    ///   - rows: The rows, in the result's order.
    ///   - files: The relative paths the rows' file indices point into.
    /// - Returns: The sorted rows.
    private static func displayOrder(_ rows: [Row], files: [String]) -> [Row] {
        var fileRank = [Int](repeating: 0, count: files.count)
        for (rank, index) in files.indices.sorted(by: { files[$0] < files[$1] }).enumerated() { fileRank[index] = rank }
        let key = { (index: Int) in (rows[index].severity, fileRank[rows[index].file], rows[index].line, index) }
        let order = rows.indices.sorted { key($0) < key($1) }
        return order.map { rows[$0] }
    }
}

/// Gives each distinct file a stable index, in the order the files are first seen, and works out its relative
/// path only once, however many findings it has.
private struct FileTable {
    /// The repository root, which `relative` paths are relative to.
    let repoRoot: URL
    /// Each file's path relative to the repository root.
    private(set) var relative: [String] = []
    /// Each file's absolute path.
    private(set) var absolute: [String] = []
    /// Each file's URL, as the findings name it.
    private(set) var urls: [URL] = []
    /// Each file's index in `relative` and `absolute`.
    private var indices: [URL: Int] = [:]

    /// Creates an empty table.
    ///
    /// - Parameter repoRoot: The repository root.
    init(repoRoot: URL) {
        self.repoRoot = repoRoot
    }

    /// Returns a file's index, adding it to the table if it's new.
    ///
    /// - Parameter file: The file.
    /// - Returns: Its index in `relative` and `absolute`.
    mutating func index(of file: URL) -> Int {
        if let existing = indices[file] { return existing }
        indices[file] = relative.count
        relative.append(RepoPath.relative(file, to: repoRoot))
        absolute.append(file.path)
        urls.append(file)
        return relative.count - 1
    }
}

/// Gives each distinct string a stable index, in the order the strings are first seen.
private struct Interner {
    /// The distinct strings, in first-seen order.
    private(set) var values: [String] = []
    /// Each string's index in `values`.
    private var indices: [String: Int] = [:]

    /// Returns a string's index, adding it to the table if it's new.
    ///
    /// - Parameter value: The string.
    /// - Returns: Its index in `values`.
    mutating func index(of value: String) -> Int {
        if let existing = indices[value] { return existing }
        indices[value] = values.count
        values.append(value)
        return values.count - 1
    }
}
