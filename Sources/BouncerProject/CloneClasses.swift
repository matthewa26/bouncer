/// A set of spans that are all copies of one block, and the longest shared length among them in tokens.
struct CloneClass {
    /// The copies, sorted by path and line, with overlapping spans in one file merged.
    let members: [CloneSpan]
    let tokens: Int
}

/// Groups pairwise clone regions into clone classes, so a block copied into five files is one class of five
/// rather than ten pairs. Two regions join a class when they share a span, or when their spans in one file
/// overlap by at least half of the shorter span.
enum CloneClasses {
    /// Groups regions into classes.
    ///
    /// - Parameter regions: The pairwise regions.
    /// - Returns: The classes, sorted by their first member.
    static func group(_ regions: [CloneRegion]) -> [CloneClass] {
        let spans = regions.flatMap { [$0.first, $0.second] }
        var sets = DisjointSets(count: spans.count)
        regions.indices.forEach { sets.union(2 * $0, 2 * $0 + 1) }
        overlappingPairs(spans).forEach { sets.union($0.0, $0.1) }
        return Dictionary(grouping: spans.indices, by: { sets.find($0) }).values.map { indices in
            let tokens = indices.map { regions[$0 / 2].tokens }.max() ?? 0
            return CloneClass(members: merged(indices.map { spans[$0] }), tokens: tokens)
        }.sorted { $0.members[0] < $1.members[0] }
    }

    /// Lists pairs of spans in the same file that overlap by at least half of the shorter one.
    ///
    /// - Parameter spans: Every span.
    /// - Returns: The overlapping pairs, as indices into `spans`.
    private static func overlappingPairs(_ spans: [CloneSpan]) -> [(Int, Int)] {
        let byFile = Dictionary(grouping: spans.indices, by: { spans[$0].path }).values
        return byFile.flatMap { indices -> [(Int, Int)] in
            let sorted = indices.sorted { spans[$0] < spans[$1] }
            return sorted.indices.flatMap { position in
                sorted[(position + 1)...].prefix { spans[$0].start <= spans[sorted[position]].end }
                    .filter { overlapsEnough(spans[sorted[position]], spans[$0]) }.map { (sorted[position], $0) }
            }
        }
    }

    /// Reports whether two spans in one file overlap by at least half of the shorter.
    ///
    /// - Parameters:
    ///   - first: One span.
    ///   - second: Another, in the same file.
    /// - Returns: Whether they're the same copy.
    private static func overlapsEnough(_ first: CloneSpan, _ second: CloneSpan) -> Bool {
        let shared = min(first.end, second.end) - max(first.start, second.start) + 1
        return shared * 2 >= min(first.lineCount, second.lineCount)
    }

    /// Sorts a class's spans and merges overlapping spans in the same file.
    ///
    /// - Parameter spans: The class's spans.
    /// - Returns: Its members.
    private static func merged(_ spans: [CloneSpan]) -> [CloneSpan] {
        spans.sorted().reduce(into: [CloneSpan]()) { members, span in
            guard let last = members.last, last.path == span.path, span.start <= last.end else {
                return members.append(span)
            }
            members[members.count - 1] = last.extended(by: span)
        }
    }
}

/// Union-find over integer elements, with path halving.
struct DisjointSets {
    private var parents: [Int]

    /// Creates `count` singleton sets.
    ///
    /// - Parameter count: The number of elements.
    init(count: Int) {
        parents = Array(0..<count)
    }

    /// Finds an element's set representative.
    ///
    /// - Parameter element: The element.
    /// - Returns: Its representative.
    mutating func find(_ element: Int) -> Int {
        var current = element
        while parents[current] != current {
            parents[current] = parents[parents[current]]
            current = parents[current]
        }
        return current
    }

    /// Merges two elements' sets.
    ///
    /// - Parameters:
    ///   - first: One element.
    ///   - second: Another.
    mutating func union(_ first: Int, _ second: Int) {
        let (rootA, rootB) = (find(first), find(second))
        if rootA != rootB { parents[max(rootA, rootB)] = min(rootA, rootB) }
    }
}
