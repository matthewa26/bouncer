import Foundation
import BouncerCore

/// A saved run in the compact form `.bouncer-cache/last-run.json` holds, like the HTML report's data: each
/// path, rule, and message is written once in a table, and each finding is a few table indices in a flat array
/// of numbers, so millions of findings stay small on disk.
struct SavedRunDocument: Codable {
    /// The layout's version; a file in any other layout is ignored.
    static let currentFormat = 1
    /// The severity names; a finding's severity index points into this list.
    static let severityOrder: [Severity] = [.error, .warning, .info]
    /// How many numbers a file's finding takes: line, rule, severity, message.
    static let fileStride = 4
    /// How many numbers a later pass's finding takes: path, line, rule, severity, message.
    static let otherStride = 5

    /// The layout's version.
    let format: Int
    /// The key the run was saved under.
    let key: SavedRun.Key
    /// The severity names.
    let severities: [String]
    /// The rule IDs.
    let rules: [String]
    /// The distinct messages.
    let messages: [String]
    /// The repo-relative paths of every analyzed file and every file a later pass reported in.
    let paths: [String]
    /// Each analyzed file.
    let files: [FileEntry]
    /// The later passes' reported findings, `otherStride` numbers each.
    let other: [Int]

    /// One analyzed file; fields that are empty or unknown are left out.
    struct FileEntry: Codable {
        /// The file's index into `paths`.
        let path: Int
        /// Its size in bytes when read.
        let size: Int64?
        /// Its modification time when read, in nanoseconds since 1970.
        let modified: Int64?
        /// Its content hash, absent when its findings can't be reused.
        let hash: String?
        /// The per-file pass's findings, `fileStride` numbers each.
        let findings: [Int]?
        /// The indices of the findings that weren't reported.
        let hidden: [Int]?
        /// Whether a change to it can change other files' findings.
        let neighbors: Bool?
    }
}

extension SavedRunDocument {
    /// Encodes a saved run.
    ///
    /// - Parameter run: The run.
    init(_ run: SavedRun) {
        var tables = SavedRunTables()
        let files = run.files.map { tables.entry(for: $0) }
        let other = run.otherFindings.flatMap { [tables.paths.index(of: $0.path)] + tables.row($0.finding) }
        (format, key, severities) = (Self.currentFormat, run.key, Self.severityOrder.map(\.rawValue))
        (rules, messages, paths) = (tables.rules.values, tables.messages.values, tables.paths.values)
        (self.files, self.other) = (files, other)
    }

    /// Decodes the saved run, checking every index.
    ///
    /// - Returns: The saved run.
    /// - Throws: `SavedRunError.corrupt` if an index is out of range or a flat array is cut short.
    func savedRun() throws -> SavedRun {
        guard format == Self.currentFormat else { throw SavedRunError.unsupportedFormat(format) }
        let reader = try SavedRunReader(self)
        let files = try files.map { try reader.file($0) }
        return SavedRun(key: key, files: files, otherFindings: try reader.otherFindings(other))
    }
}

/// Why a saved run couldn't be read.
public enum SavedRunError: Error, Equatable, CustomStringConvertible {
    /// The file uses another layout version.
    case unsupportedFormat(Int)
    /// The file's contents don't add up.
    case corrupt(String)

    /// A short explanation, for the run log.
    public var description: String {
        switch self {
        case let .unsupportedFormat(format): return "it uses layout version \(format)"
        case let .corrupt(detail): return "it is damaged (\(detail))"
        }
    }
}

/// The tables a saved run's findings are written against, filled while encoding.
private struct SavedRunTables {
    /// The rule IDs.
    var rules = Interner()
    /// The distinct messages.
    var messages = Interner()
    /// The repo-relative paths.
    var paths = Interner()

    /// Encodes one file.
    ///
    /// - Parameter file: The file.
    /// - Returns: Its entry.
    mutating func entry(for file: SavedRun.File) -> SavedRunDocument.FileEntry {
        let path = paths.index(of: file.path)
        let findings = file.findings.flatMap { row($0) }
        return SavedRunDocument.FileEntry(
            path: path, size: file.stamp?.size, modified: file.stamp?.modified, hash: file.contentHash,
            findings: findings.isEmpty ? nil : findings, hidden: file.hidden.isEmpty ? nil : file.hidden,
            neighbors: file.affectsNeighbors ? true : nil
        )
    }

    /// Encodes one finding as its line, rule, severity, and message indices.
    ///
    /// - Parameter finding: The finding.
    /// - Returns: The numbers.
    mutating func row(_ finding: SavedRun.SavedFinding) -> [Int] {
        let severity = SavedRunDocument.severityOrder.firstIndex(of: finding.severity) ?? 0
        return [finding.line, rules.index(of: finding.ruleID), severity, messages.index(of: finding.message)]
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
        let next = values.count
        let index = indices[value, default: next]
        if index == next {
            indices[value] = next
            values.append(value)
        }
        return index
    }
}

/// Turns a document's numbers back into findings, checking each index against its table.
private struct SavedRunReader {
    /// Where each part of a file's finding sits among its numbers.
    private enum Column {
        /// The line.
        static let line = 0
        /// The rule index.
        static let rule = 1
        /// The severity index.
        static let severity = 2
        /// The message index.
        static let message = 3
    }

    /// The document.
    let document: SavedRunDocument
    /// The severities, by index.
    let severities: [Severity]

    /// Prepares to read a document.
    ///
    /// - Parameter document: The document.
    /// - Throws: `SavedRunError.corrupt` if a severity name is unknown.
    init(_ document: SavedRunDocument) throws {
        self.document = document
        severities = try document.severities.map { name in
            guard let severity = Severity(rawValue: name) else { throw SavedRunError.corrupt("severity \(name)") }
            return severity
        }
    }

    /// Reads one file.
    ///
    /// - Parameter entry: The file's entry.
    /// - Returns: The file.
    /// - Throws: `SavedRunError.corrupt` if an index is out of range.
    func file(_ entry: SavedRunDocument.FileEntry) throws -> SavedRun.File {
        let findings = try rows(entry.findings ?? [], stride: SavedRunDocument.fileStride).map { try finding($0) }
        let hidden = entry.hidden ?? []
        guard hidden.allSatisfy(findings.indices.contains) else { throw SavedRunError.corrupt("hidden index") }
        let stamp = both(entry.size, entry.modified).map { FileStamp(size: $0, modified: $1) }
        return SavedRun.File(
            path: try lookup(document.paths, entry.path), stamp: stamp, contentHash: entry.hash, findings: findings,
            hidden: hidden, affectsNeighbors: entry.neighbors == true
        )
    }

    /// Reads the later passes' findings.
    ///
    /// - Parameter numbers: Their flat array.
    /// - Returns: The findings.
    /// - Throws: `SavedRunError.corrupt` if an index is out of range.
    func otherFindings(_ numbers: [Int]) throws -> [SavedRun.PlacedFinding] {
        try rows(numbers, stride: SavedRunDocument.otherStride).map { row in
            let path = try lookup(document.paths, row[row.startIndex])
            return SavedRun.PlacedFinding(path: path, finding: try finding(row.dropFirst()))
        }
    }

    /// Reads one finding from its line, rule, severity, and message numbers.
    ///
    /// - Parameter row: The numbers.
    /// - Returns: The finding.
    /// - Throws: `SavedRunError.corrupt` if an index is out of range.
    private func finding(_ row: ArraySlice<Int>) throws -> SavedRun.SavedFinding {
        let numbers = Array(row)
        guard numbers.count == SavedRunDocument.fileStride else { throw SavedRunError.corrupt("finding size") }
        return SavedRun.SavedFinding(
            ruleID: try lookup(document.rules, numbers[Column.rule]),
            severity: try lookup(severities, numbers[Column.severity]), line: numbers[Column.line],
            message: try lookup(document.messages, numbers[Column.message])
        )
    }

    /// Splits a flat array into rows.
    ///
    /// - Parameters:
    ///   - numbers: The flat array.
    ///   - stride: How many numbers make a row.
    /// - Returns: The rows.
    /// - Throws: `SavedRunError.corrupt` if the last row is cut short.
    private func rows(_ numbers: [Int], stride: Int) throws -> [ArraySlice<Int>] {
        guard numbers.count % stride == 0 else { throw SavedRunError.corrupt("a finding is cut short") }
        return Swift.stride(from: 0, to: numbers.count, by: stride).map { numbers[$0..<$0 + stride] }
    }

    /// Looks up a table entry.
    ///
    /// - Parameters:
    ///   - table: The table.
    ///   - index: The index.
    /// - Returns: The entry.
    /// - Throws: `SavedRunError.corrupt` if the index is out of range.
    private func lookup<Value>(_ table: [Value], _ index: Int) throws -> Value {
        guard table.indices.contains(index) else { throw SavedRunError.corrupt("index \(index) out of range") }
        return table[index]
    }
}

/// Pairs two optionals.
///
/// - Parameters:
///   - first: The first value.
///   - second: The second value.
/// - Returns: Both, or `nil` if either is missing.
private func both<First, Second>(_ first: First?, _ second: Second?) -> (First, Second)? {
    guard let first, let second else { return nil }
    return (first, second)
}
