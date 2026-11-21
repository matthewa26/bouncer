import Foundation
import BouncerCore

/// The findings in the compact form the HTML report embeds: each file and rule is written once in a lookup
/// table, and each finding is a short array of indices into those tables, so a report with millions of findings
/// stays small enough for a browser to load.
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

    /// One finding, encoded as `[fileIndex, line, ruleIndex, severityIndex, message]`.
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
        }
    }

    /// The severities in the order the page lists them.
    static let severityOrder: [Severity] = [.error, .warning, .info]

    /// Builds the compact data for a result.
    ///
    /// - Parameters:
    ///   - result: The analysis result.
    ///   - repoRoot: The repository root, which the table's paths are relative to.
    init(result: AnalysisResult, repoRoot: URL) {
        var files = FileTable(repoRoot: repoRoot), rules = Interner()
        let unsorted = result.findings.map { finding in
            Row(file: files.index(of: finding.filePath), line: finding.line, rule: rules.index(of: finding.ruleID),
                severity: Self.severityOrder.firstIndex(of: finding.severity) ?? 0, message: finding.message)
        }
        rows = Self.displayOrder(unsorted, files: files.relative)
        (key, coverage, severities) = (repoRoot.path, result.coverage?.overallLineCoveragePercent, Self.names)
        (self.files, filePaths, self.rules) = (files.relative, files.absolute, rules.values)
        (owasp, owaspTitles) = Self.categories(of: rules.values)
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
