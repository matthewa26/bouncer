/// A set of spans that are all copies of one block, and the longest shared length among them in tokens.
struct CloneClass {
    /// The copies, sorted by path and line, with overlapping spans in one file merged.
    let members: [CloneSpan]
    let tokens: Int
    /// The share estimated identical, as a whole percentage rounded down, of the least similar region in the
    /// class: 100 when every region is an exact or renamed copy.
    let percentIdentical: Int

    /// Whether any of the class's regions is a near-duplicate rather than an exact or renamed copy.
    var isNear: Bool { percentIdentical < Self.percent }
    static let percent = 100
}

/// Groups pairwise clone regions into clone classes, so a block copied into five files is one class of five
/// rather than ten pairs. Two regions join a class when they share a span, or when their spans in one file
/// overlap by at least half of the shorter span, or of the longer one when either comes from a near-duplicate, so a
/// long near-duplicate doesn't pull every short copy it happens to contain into its class.
enum CloneClasses {
    /// Groups regions into classes.
    ///
    /// - Parameter regions: The pairwise regions.
    /// - Returns: The classes, sorted by their first member.
    static func group(_ regions: [CloneRegion]) -> [CloneClass] {
        let spans = regions.flatMap { [$0.first, $0.second] }
        var sets = DisjointSets(count: spans.count)
        regions.indices.forEach { sets.union(2 * $0, 2 * $0 + 1) }
        overlappingPairs(spans, near: spans.indices.map { regions[$0 / 2].isNear }).forEach { sets.union($0.0, $0.1) }
        return Dictionary(grouping: spans.indices, by: { sets.find($0) }).values.map { indices in
            makeClass(spans: indices.map { spans[$0] }, regions: indices.map { regions[$0 / 2] })
        }.sorted { $0.members[0] < $1.members[0] }
    }

    /// Builds one class from its spans, measured by its longest region and its least similar one.
    ///
    /// - Parameters:
    ///   - spans: The class's spans.
    ///   - regions: The regions they come from.
    /// - Returns: The class.
    private static func makeClass(spans: [CloneSpan], regions: [CloneRegion]) -> CloneClass {
        let percent = regions.map { $0.matched * CloneClass.percent / max(1, $0.tokens) }.min() ?? CloneClass.percent
        return CloneClass(members: merged(spans), tokens: regions.map(\.tokens).max() ?? 0, percentIdentical: percent)
    }

    /// Lists pairs of spans in the same file that overlap enough to be the same copy.
    ///
    /// - Parameters:
    ///   - spans: Every span.
    ///   - near: Whether each span comes from a near-duplicate region.
    /// - Returns: The overlapping pairs, as indices into `spans`.
    private static func overlappingPairs(_ spans: [CloneSpan], near: [Bool]) -> [(Int, Int)] {
        let byFile = Dictionary(grouping: spans.indices, by: { spans[$0].path }).values
        return byFile.flatMap { indices -> [(Int, Int)] in
            let sorted = indices.sorted { spans[$0] < spans[$1] }
            return sorted.indices.flatMap { position in
                sorted[(position + 1)...].prefix { spans[$0].start <= spans[sorted[position]].end }
                    .filter { overlapsEnough(sorted[position], $0, spans: spans, near: near) }
                    .map { (sorted[position], $0) }
            }
        }
    }

    /// The span whose length an overlap is measured against.
    private enum OverlapBasis {
        case shorter, longer
    }

    /// Reports whether two spans in one file overlap enough to be the same copy, measured against the longer
    /// span when either is from a near-duplicate and the shorter otherwise.
    ///
    /// - Parameters:
    ///   - first: One span's index.
    ///   - second: Another's, in the same file.
    ///   - spans: Every span.
    ///   - near: Whether each span comes from a near-duplicate region.
    /// - Returns: Whether they're the same copy.
    private static func overlapsEnough(_ first: Int, _ second: Int, spans: [CloneSpan], near: [Bool]) -> Bool {
        overlapsEnough(spans[first], spans[second], basis: near[first] || near[second] ? .longer : .shorter)
    }

    /// Reports whether two spans in one file overlap by at least half of the shorter or the longer one.
    ///
    /// - Parameters:
    ///   - first: One span.
    ///   - second: Another, in the same file.
    ///   - basis: Which span's length half the overlap must reach.
    /// - Returns: Whether they're the same copy.
    private static func overlapsEnough(_ first: CloneSpan, _ second: CloneSpan, basis: OverlapBasis) -> Bool {
        let shared = min(first.end, second.end) - max(first.start, second.start) + 1
        let lengths = (first.lineCount, second.lineCount)
        return shared * 2 >= (basis == .longer ? max(lengths.0, lengths.1) : min(lengths.0, lengths.1))
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
