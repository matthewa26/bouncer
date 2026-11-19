import BouncerCore

/// A line range in one file that's part of a clone.
struct CloneSpan: Hashable, Comparable {
    let path: String
    let start: Int
    let end: Int
    /// The number of lines in the range that hold code, leaving out blank and comment-only lines.
    let codeLines: Int

    /// The number of lines it covers.
    var lineCount: Int { end - start + 1 }

    /// Widens this span to also cover an overlapping span in the same file.
    ///
    /// - Parameter other: The other span.
    /// - Returns: The combined span.
    func extended(by other: CloneSpan) -> CloneSpan {
        CloneSpan(
            path: path, start: min(start, other.start), end: max(end, other.end),
            codeLines: max(codeLines, other.codeLines)
        )
    }

    /// Orders spans by path, then start line, then end line.
    ///
    /// - Parameters:
    ///   - lhs: One span.
    ///   - rhs: Another.
    /// - Returns: Whether `lhs` comes first.
    static func < (lhs: CloneSpan, rhs: CloneSpan) -> Bool {
        (lhs.path, lhs.start, lhs.end) < (rhs.path, rhs.start, rhs.end)
    }
}

/// A stretch of normalized tokens that two different files share, exactly or nearly.
struct CloneRegion {
    let first: CloneSpan
    let second: CloneSpan
    /// The region's length in tokens, on its longer side.
    let tokens: Int
    /// The tokens estimated identical: all of them for an exact or renamed copy, fewer for a near-duplicate.
    let matched: Int

    /// Whether the region joins copies separated by small edits, rather than being one unbroken copy.
    var isNear: Bool { matched < tokens }
}

/// Finds maximal runs shared by pairs of files from their winnowed fingerprints.
///
/// Matching fingerprints are grouped by file pair and diagonal (the difference of their token offsets), since
/// an exact or renamed copy keeps every token at the same distance from its counterpart. Along a diagonal,
/// consecutive matches no more than `gramLength` tokens apart are merged into one run: their k-grams then
/// overlap or abut, so every token in between is covered by a matching k-gram, which verifies the run
/// token by token (up to 53-bit hash collisions) without re-reading either file. Edges are conservative: a
/// run can start and end up to `window - 1` tokens inside the true copy. `CloneMerger` then joins runs
/// that a small edit separates.
struct CloneMatcher {
    /// Fingerprints shared by more places than this are boilerplate, and are left out to bound the work.
    static let maxOccurrences = 50

    /// One fingerprint: a file and an index into its fingerprint arrays.
    private struct Ref {
        let file: Int
        let entry: Int
    }

    /// A file pair and token-offset difference that matches line up along.
    private struct Diagonal: Hashable, Comparable {
        let first: Int
        let second: Int
        let delta: Int

        /// Orders diagonals by file pair, then offset difference.
        ///
        /// - Parameters:
        ///   - lhs: One diagonal.
        ///   - rhs: Another.
        /// - Returns: Whether `lhs` comes first.
        static func < (lhs: Diagonal, rhs: Diagonal) -> Bool {
            (lhs.first, lhs.second, lhs.delta) < (rhs.first, rhs.second, rhs.delta)
        }
    }

    private let paths: [String]
    private let clones: [CloneFacts]

    /// Creates a matcher over files that have fingerprints.
    ///
    /// - Parameter files: The files, in a stable order.
    init(files: [FileFacts]) {
        let fingerprinted = files.compactMap { file in file.clones.map { (file.path, $0) } }
        paths = fingerprinted.map(\.0)
        clones = fingerprinted.map(\.1)
    }

    /// Finds every run shared by two different files, in a stable order.
    ///
    /// - Returns: The runs, one per file pair and diagonal run.
    func runs() -> [CloneRun] {
        let diagonals = matches()
        return diagonals.keys.sorted().flatMap { diagonal in
            runs(diagonals[diagonal] ?? [], in: diagonal).map { run($0, in: diagonal) }
        }
    }

    /// Pairs up matching fingerprints in different files, grouped by diagonal.
    ///
    /// - Returns: Each diagonal's matches, as pairs of fingerprint entries.
    private func matches() -> [Diagonal: [(Int, Int)]] {
        var diagonals: [Diagonal: [(Int, Int)]] = [:]
        for refs in occurrences().values where refs.count > 1 && refs.count <= Self.maxOccurrences {
            pair(refs, into: &diagonals)
        }
        return diagonals
    }

    /// Indexes every fingerprint by hash.
    ///
    /// - Returns: Each hash's occurrences, in file order.
    private func occurrences() -> [Int: [Ref]] {
        var byHash: [Int: [Ref]] = [:]
        for (file, facts) in clones.enumerated() {
            for (entry, hash) in facts.hashes.enumerated() {
                byHash[hash, default: []].append(Ref(file: file, entry: entry))
            }
        }
        return byHash
    }

    /// Adds every cross-file pair among one hash's occurrences to its diagonal.
    ///
    /// - Parameters:
    ///   - refs: The occurrences, in file order.
    ///   - diagonals: The matches so far, by diagonal.
    private func pair(_ refs: [Ref], into diagonals: inout [Diagonal: [(Int, Int)]]) {
        for (index, first) in refs.enumerated() {
            for second in refs[(index + 1)...] where second.file != first.file {
                let delta = clones[first.file].offsets[first.entry] - clones[second.file].offsets[second.entry]
                diagonals[Diagonal(first: first.file, second: second.file, delta: delta), default: []]
                    .append((first.entry, second.entry))
            }
        }
    }

    /// Splits one diagonal's matches into runs whose k-grams overlap or abut.
    ///
    /// - Parameters:
    ///   - matches: The diagonal's matching entries.
    ///   - diagonal: The diagonal, for its first file's offsets.
    /// - Returns: The runs, each a list of matches in token order.
    private func runs(_ matches: [(Int, Int)], in diagonal: Diagonal) -> [[(Int, Int)]] {
        let offsets = clones[diagonal.first].offsets
        return matches.sorted { $0.0 < $1.0 }.reduce(into: [[(Int, Int)]]()) { runs, match in
            if let last = runs.last?.last, offsets[match.0] - offsets[last.0] <= CloneFingerprinter.gramLength {
                runs[runs.count - 1].append(match)
            } else {
                runs.append([match])
            }
        }
    }

    /// Describes one diagonal run by its fingerprint entries and token offsets.
    ///
    /// - Parameters:
    ///   - matches: The run's matches, in token order; never empty.
    ///   - diagonal: The diagonal it lies on.
    /// - Returns: The run.
    private func run(_ matches: [(Int, Int)], in diagonal: Diagonal) -> CloneRun {
        let (head, tail) = (matches[0], matches[matches.count - 1])
        let firstTokens = tokens(diagonal.first, from: head.0, to: tail.0)
        return CloneRun(
            firstFile: diagonal.first, secondFile: diagonal.second, firstEntries: head.0...tail.0,
            secondEntries: head.1...tail.1, firstTokens: firstTokens,
            secondTokens: tokens(diagonal.second, from: head.1, to: tail.1), matched: firstTokens.count,
            longestPiece: firstTokens.count
        )
    }

    /// Finds the tokens from one fingerprint's k-gram to another's.
    ///
    /// - Parameters:
    ///   - file: The file.
    ///   - head: The first fingerprint's entry.
    ///   - tail: The last fingerprint's entry.
    /// - Returns: The token offsets covered.
    private func tokens(_ file: Int, from head: Int, to tail: Int) -> Range<Int> {
        let offsets = clones[file].offsets
        return offsets[head]..<(offsets[tail] + CloneFingerprinter.gramLength)
    }

    /// Describes a run as a region: its lines in each file, its length, and how much of it matches.
    ///
    /// - Parameter run: A run from `runs()`, joined or not.
    /// - Returns: The region.
    func region(_ run: CloneRun) -> CloneRegion {
        CloneRegion(
            first: span(run.firstFile, from: run.firstEntries.lowerBound, to: run.firstEntries.upperBound),
            second: span(run.secondFile, from: run.secondEntries.lowerBound, to: run.secondEntries.upperBound),
            tokens: run.tokens, matched: run.matched
        )
    }

    /// Builds the line span from one fingerprint's first line to another's last.
    ///
    /// - Parameters:
    ///   - file: The file.
    ///   - head: The first fingerprint's entry.
    ///   - tail: The last fingerprint's entry.
    /// - Returns: The span.
    private func span(_ file: Int, from head: Int, to tail: Int) -> CloneSpan {
        let facts = clones[file], first = facts.lines[head], last = facts.endLines[tail]
        return CloneSpan(
            path: paths[file], start: facts.lineNumbers[first], end: facts.lineNumbers[last],
            codeLines: last - first + 1
        )
    }
}
