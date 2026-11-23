/// Suggests the names closest to a mistyped one, such as rule IDs for `explain_rule`.
public enum NameSuggestions {
    /// The fewest edits always allowed between a query and a suggestion.
    private static let minimumDistance = 2
    /// The share of a query's length, as a divisor, allowed as edits beyond that.
    private static let lengthDivisor = 3

    /// Picks the names closest to a query: names containing it, or within a few edits of it.
    ///
    /// - Parameters:
    ///   - query: The mistyped name.
    ///   - names: The known names.
    ///   - limit: How many suggestions to return at most.
    /// - Returns: The suggestions, closest first, ties broken alphabetically.
    public static func closest(to query: String, among names: [String], limit: Int = 5) -> [String] {
        let needle = query.lowercased()
        let allowed = max(minimumDistance, needle.count / lengthDivisor)
        let scored = names.map { (name: $0, score: score($0.lowercased(), needle)) }.filter { $0.score <= allowed }
        let ranked = scored.sorted { ($0.score, $0.name) < ($1.score, $1.name) }
        return ranked.prefix(limit).map(\.name)
    }

    /// Scores a name against a query: 0 when one contains the other, otherwise their edit distance.
    ///
    /// - Parameters:
    ///   - name: The known name, lowercased.
    ///   - query: The query, lowercased.
    /// - Returns: The score; lower is closer.
    private static func score(_ name: String, _ query: String) -> Int {
        guard !query.isEmpty else { return Int.max }
        if name.contains(query) || query.contains(name) { return 0 }
        return distance(Array(name), Array(query))
    }

    /// The Levenshtein distance between two strings.
    ///
    /// - Parameters:
    ///   - lhs: One string's characters.
    ///   - rhs: The other's.
    /// - Returns: How many single-character insertions, deletions, or substitutions turn one into the other.
    static func distance(_ lhs: [Character], _ rhs: [Character]) -> Int {
        var previous = Array(0...rhs.count)
        for (index, character) in lhs.enumerated() {
            previous = nextRow(previous, index: index, character: character, rhs)
        }
        return previous[rhs.count]
    }

    /// Computes one row of the edit-distance table.
    ///
    /// - Parameters:
    ///   - previous: The row before.
    ///   - index: The row's position in the first string.
    ///   - character: The first string's character at that position.
    ///   - rhs: The second string's characters.
    /// - Returns: The row.
    private static func nextRow(_ previous: [Int], index: Int, character: Character, _ rhs: [Character]) -> [Int] {
        var row = [index + 1]
        for (column, other) in rhs.enumerated() {
            let substitution = previous[column] + (character == other ? 0 : 1)
            row.append(min(previous[column + 1] + 1, row[column] + 1, substitution))
        }
        return row
    }
}
