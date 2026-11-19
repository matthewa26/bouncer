/// A stretch two files share, by fingerprint entries and token offsets, before it's turned into line spans.
///
/// A run straight off one diagonal is an exact or renamed copy, so it matches every token it covers. A run
/// joined from several (see `CloneMerger`) also covers the edited tokens between them, so it matches fewer.
///
/// Winnowing leaves up to `window - 1` tokens unconfirmed at each edge of an edit (between the last picked
/// fingerprint and the edit), about `window - 1` in all on average; a join credits that many of a gap's tokens,
/// at most the smaller side of the gap, as identical. For an inserted or deleted line the estimate is then about
/// its own length short of the span, and for a changed line about the changed tokens, rather than counting
/// every unconfirmed token as different.
struct CloneRun {
    let firstFile: Int
    let secondFile: Int
    /// The first and last fingerprint entries in each file.
    let firstEntries: ClosedRange<Int>
    let secondEntries: ClosedRange<Int>
    /// The tokens covered in each file, as offsets into its token stream.
    let firstTokens: Range<Int>
    let secondTokens: Range<Int>
    /// The tokens estimated identical: all of them for an unjoined run; for a joined one, the tokens matching
    /// k-grams cover plus each gap's credit for unconfirmed edges.
    let matched: Int
    /// The longest unjoined run this one is made of.
    let longestPiece: Int

    /// The run's length in tokens: the longer of its two sides.
    var tokens: Int { max(firstTokens.count, secondTokens.count) }

    /// The share of the run estimated identical, from 0 to 1.
    var similarity: Double { Double(matched) / Double(max(1, tokens)) }

    /// Joins this run with a later one between the same two files, covering the gap between them.
    ///
    /// - Parameter later: A run that starts after this one ends, in both files.
    /// - Returns: The joined run.
    func joined(with later: CloneRun) -> CloneRun {
        CloneRun(
            firstFile: firstFile, secondFile: secondFile,
            firstEntries: firstEntries.lowerBound...later.firstEntries.upperBound,
            secondEntries: secondEntries.lowerBound...later.secondEntries.upperBound,
            firstTokens: firstTokens.lowerBound..<later.firstTokens.upperBound,
            secondTokens: secondTokens.lowerBound..<later.secondTokens.upperBound,
            matched: matched + later.matched + credit(before: later),
            longestPiece: max(longestPiece, later.longestPiece)
        )
    }

    /// Counts the gap tokens before a later run that a join credits as identical: the edges winnowing leaves
    /// unconfirmed, about `window - 1` tokens, but no more than the gap's smaller side, and always leaving at
    /// least one token of the gap different, since something there broke the copy.
    ///
    /// - Parameter later: A run that starts after this one ends, in both files.
    /// - Returns: The credited tokens.
    private func credit(before later: CloneRun) -> Int {
        let gaps = gaps(before: later)
        let edges = min(gaps.first, gaps.second, CloneFingerprinter.window - 1)
        return max(0, min(edges, max(gaps.first, gaps.second) - 1))
    }

    /// Measures the tokens between this run's end and a later run's start, in each file.
    ///
    /// - Parameter later: A run between the same two files.
    /// - Returns: The gap in each file; negative where the runs overlap or are out of order.
    func gaps(before later: CloneRun) -> (first: Int, second: Int) {
        (later.firstTokens.lowerBound - firstTokens.upperBound, later.secondTokens.lowerBound - secondTokens.upperBound)
    }
}

/// Joins exact or renamed runs that a small edit separates into one near-duplicate (Type-3) run.
///
/// An inserted, deleted, or changed line breaks a copy into runs on nearby diagonals, since every k-gram that
/// overlaps the edit differs. Runs between the same two files are taken in order through the first file, and
/// each joins the earlier chain that ends before it in both files with at most `maxGap` tokens between them
/// in either file, as long as matching k-grams still cover at least `minSimilarity` of the joined span; of
/// several such chains, the closest wins. The gaps include up to `window - 1` tokens on each side that
/// winnowing leaves unconfirmed, which `CloneRun.joined(with:)` credits back on average. A join also needs
/// one of its runs to be at least `minPiece` tokens long, the length winnowing is sure to find: shorter shared
/// pieces, such as runs of `self.name = name`, turn up by chance in similar-looking code.
struct CloneMerger {
    static let defaultMaxGap = 40
    static let defaultMinSimilarity = 80.0
    static let minPiece = CloneFingerprinter.gramLength + CloneFingerprinter.window - 1
    private static let percent = 100.0

    /// The most tokens a joined gap may span in either file; 0 turns joining off.
    let maxGap: Int
    /// The least share of a joined run, as a percentage, that matching k-grams must cover.
    let minSimilarity: Double

    /// Joins runs separated by small edits.
    ///
    /// - Parameter runs: Every run, as the matcher found them.
    /// - Returns: The runs, unchanged when joining is off; otherwise sorted by file pair and position, with
    ///   joined chains in place of the runs they absorbed.
    func merged(_ runs: [CloneRun]) -> [CloneRun] {
        guard maxGap > 0 else { return runs }
        var chains: [CloneRun] = [], open: [Int] = []
        Self.ordered(runs).forEach { add($0, to: &chains, open: &open) }
        return chains
    }

    /// Adds the next run: it joins the closest open chain it can, or starts a chain of its own.
    ///
    /// - Parameters:
    ///   - run: The next run, in order.
    ///   - chains: The chains so far, updated.
    ///   - open: The indices of chains that a later run could still join, updated.
    private func add(_ run: CloneRun, to chains: inout [CloneRun], open: inout [Int]) {
        open.removeAll { !isReachable(chains[$0], from: run) }
        guard let index = closestChain(for: run, among: open, in: chains) else {
            open.append(chains.count)
            return chains.append(run)
        }
        chains[index] = chains[index].joined(with: run)
    }

    /// Sorts runs by file pair, then by where they start in the first file and then the second.
    ///
    /// - Parameter runs: The runs.
    /// - Returns: The sorted runs.
    private static func ordered(_ runs: [CloneRun]) -> [CloneRun] {
        runs.sorted {
            ($0.firstFile, $0.secondFile, $0.firstTokens.lowerBound, $0.secondTokens.lowerBound)
                < ($1.firstFile, $1.secondFile, $1.firstTokens.lowerBound, $1.secondTokens.lowerBound)
        }
    }

    /// Reports whether a chain could still be joined by a run or any later one: it's between the same files
    /// and ends at most `maxGap` tokens before the run starts in the first file. Runs come in order of their
    /// start, and a chain only grows by joining, so a chain left behind stays behind.
    ///
    /// - Parameters:
    ///   - chain: An open chain.
    ///   - run: The next run.
    /// - Returns: Whether the chain stays open.
    private func isReachable(_ chain: CloneRun, from run: CloneRun) -> Bool {
        chain.firstFile == run.firstFile && chain.secondFile == run.secondFile
            && chain.firstTokens.upperBound >= run.firstTokens.lowerBound - maxGap
    }

    /// Picks the chain a run should join: an open one that it follows closely enough.
    ///
    /// - Parameters:
    ///   - run: The next run.
    ///   - open: The indices of the chains still open for the run's file pair.
    ///   - chains: Every chain so far.
    /// - Returns: The index of the chain with the smallest gap, or `nil` if none qualifies.
    private func closestChain(for run: CloneRun, among open: [Int], in chains: [CloneRun]) -> Int? {
        open.filter { canJoin(chains[$0], run) }.min { gap(chains[$0], run) < gap(chains[$1], run) }
    }

    /// Reports whether a run can extend a chain: it follows within `maxGap` tokens in both files, one of them
    /// has a long enough piece, and the joined run is still similar enough.
    ///
    /// - Parameters:
    ///   - chain: The earlier chain.
    ///   - run: The later run.
    /// - Returns: Whether they join.
    private func canJoin(_ chain: CloneRun, _ run: CloneRun) -> Bool {
        let gaps = chain.gaps(before: run)
        guard min(gaps.first, gaps.second) >= 0, max(gaps.first, gaps.second) <= maxGap else { return false }
        let joined = chain.joined(with: run)
        return joined.longestPiece >= Self.minPiece && joined.similarity * Self.percent >= minSimilarity
    }

    /// Measures how far a run is from a chain: the larger of its two gaps.
    ///
    /// - Parameters:
    ///   - chain: The earlier chain.
    ///   - run: The later run.
    /// - Returns: The gap in tokens.
    private func gap(_ chain: CloneRun, _ run: CloneRun) -> Int {
        let gaps = chain.gaps(before: run)
        return max(gaps.first, gaps.second)
    }
}
