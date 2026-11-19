import Foundation
import BouncerCore

/// Small regex and path helpers shared by the security and import text rules.
enum TextMatching {
    /// Compiles a pattern the rules ship with; one that doesn't compile is a programming error, which an assertion
    /// catches in debug builds and tests.
    ///
    /// - Parameter pattern: The regular expression.
    /// - Returns: The compiled expression, or `nil` if it doesn't compile.
    static func regex(_ pattern: String) -> NSRegularExpression? {
        do {
            return try NSRegularExpression(pattern: pattern)
        } catch {
            assertionFailure("Invalid built-in pattern \(pattern): \(error)")
            return nil
        }
    }

    /// Reports whether a regex matches anywhere in some text.
    ///
    /// - Parameters:
    ///   - regex: The expression to match, or `nil`, which never matches.
    ///   - text: The text to search.
    /// - Returns: Whether there's a match.
    static func matches(_ regex: NSRegularExpression?, _ text: some StringProtocol) -> Bool {
        let string = String(text)
        return regex?.firstMatch(in: string, range: NSRange(string.startIndex..., in: string)) != nil
    }

    /// Collects every match's capture groups.
    ///
    /// - Parameters:
    ///   - regex: The expression to match, or `nil`, which never matches.
    ///   - text: The text to search.
    /// - Returns: One array per match holding each group's text (empty for a group that didn't take part).
    static func captures(_ regex: NSRegularExpression?, _ text: some StringProtocol) -> [[String]] {
        let string = String(text)
        let matches = regex?.matches(in: string, range: NSRange(string.startIndex..., in: string)) ?? []
        return matches.map { match in
            (0..<match.numberOfRanges).map { Range(match.range(at: $0), in: string).map { String(string[$0]) } ?? "" }
        }
    }

    /// Reports whether a path looks like a test, fixture, or mock file, where literal addresses and throwaway
    /// random values are expected.
    ///
    /// - Parameter path: The file's location.
    /// - Returns: Whether a directory or the file name marks it as test code.
    static func isTestPath(_ path: URL) -> Bool {
        let directories = path.deletingLastPathComponent().pathComponents.map { $0.lowercased() }
        let testDirectories: Set = ["test", "tests", "__tests__", "spec", "specs", "testdata", "fixtures", "mocks"]
        guard directories.allSatisfy({ !testDirectories.contains($0) && !$0.hasSuffix("tests") }) else { return true }
        return matches(testFileName, path.lastPathComponent)
    }

    private static let testFileName = regex(
        #"(?i)([._-](test|spec)s?\.\w+$)|(^test_.*\.py$)|(_test\.(go|py)$)|(Tests?\.swift$)|(\.(mock|fixture)\.\w+$)"#
    )
}
