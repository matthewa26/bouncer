import BouncerCore

/// Picks a small, position-independent set of fingerprints from a token stream by k-gram hashing and
/// winnowing (Schleimer, Wilkerson and Aiken, "Winnowing: Local Algorithms for Document Fingerprinting").
///
/// Every k-gram of `gramLength` tokens is hashed; from each window of `window` consecutive k-gram hashes the
/// smallest is kept (the rightmost on a tie). Any run of at least `gramLength + window - 1` tokens shared by
/// two files therefore shares at least one fingerprint, while only about 2 / (`window` + 1) of positions are
/// stored. K-grams with fewer than `minDistinctTokens` distinct tokens, such as rows of a data table, are
/// never picked, so tables of literals don't read as duplicated code.
enum CloneFingerprinter {
    static let gramLength = 20
    static let window = 12
    static let minDistinctTokens = 6
    /// Hashes are kept to 53 bits so they survive a round trip through JSON numbers exactly.
    private static let mask: UInt64 = (1 << 53) - 1
    private static let base: UInt64 = 0x0000_0100_0000_01B3
    private static let unpickable = UInt64.max
    /// Spreads a repeated identifier's small back-distance across all 64 bits (the golden-ratio constant).
    private static let distanceSpread: UInt64 = 0x9E37_79B9_7F4A_7C15

    /// Names the tokenizer and parameters, so the cache recomputes fingerprints made any other way.
    ///
    /// - Parameter keepLiterals: Whether literals kept their values.
    /// - Returns: The scheme identifier.
    static func scheme(keepLiterals: Bool) -> String {
        "tokens3-k\(gramLength)-w\(window)-d\(minDistinctTokens)-" + (keepLiterals ? "values" : "literals")
    }

    /// Fingerprints a token stream.
    ///
    /// - Parameters:
    ///   - tokens: The file's normalized tokens.
    ///   - scheme: The scheme to record.
    /// - Returns: The winnowed fingerprints, in token order.
    static func fingerprints(of tokens: [CloneToken], scheme: String) -> CloneFacts {
        let hashes = gramHashes(tokens)
        let picked = winnow(hashes)
        let (codeLines, lineNumbers) = codeLineOrdinals(tokens)
        return CloneFacts(
            scheme: scheme, hashes: picked.map { Int(hashes[$0]) }, offsets: picked,
            lines: picked.map { codeLines[$0] }, endLines: picked.map { codeLines[$0 + gramLength - 1] },
            lineNumbers: lineNumbers
        )
    }

    /// Numbers the lines that hold tokens, so lengths can be measured in code lines rather than lines.
    ///
    /// - Parameter tokens: The tokens, in order.
    /// - Returns: Each token's code line, counted from 0, and each code line's line number.
    private static func codeLineOrdinals(_ tokens: [CloneToken]) -> (ordinals: [Int], lineNumbers: [Int]) {
        var lineNumbers: [Int] = []
        let ordinals = tokens.map { token in
            if lineNumbers.last != token.line { lineNumbers.append(token.line) }
            return lineNumbers.count - 1
        }
        return (ordinals, lineNumbers)
    }

    /// Hashes every k-gram, marking low-diversity ones unpickable.
    ///
    /// Identifiers are matched by consistent renaming (Baker's parameterized matching): within a k-gram, an
    /// identifier's first occurrence hashes as the bare placeholder and each repeat as its distance back to
    /// the previous occurrence. A copy that renames `count` to `total` everywhere hashes the same, but code
    /// that merely has the same shape with names used in a different pattern doesn't. The k-gram hash only
    /// depends on its own tokens, which is what winnowing needs.
    ///
    /// - Parameter tokens: The tokens.
    /// - Returns: One hash per k-gram start, or none for a stream shorter than one k-gram.
    static func gramHashes(_ tokens: [CloneToken]) -> [UInt64] {
        guard tokens.count >= gramLength else { return [] }
        let previous = previousOccurrences(tokens)
        let hashes = (0...(tokens.count - gramLength)).map { gramHash(at: $0, tokens: tokens, previous: previous) }
        return zip(hashes, diverseGrams(tokens)).map { $1 ? $0 & mask : unpickable }
    }

    /// Hashes one k-gram, encoding each repeated identifier by its distance to the previous occurrence.
    ///
    /// - Parameters:
    ///   - start: The k-gram's first token.
    ///   - tokens: The tokens.
    ///   - previous: Each token's previous same-named position.
    /// - Returns: The hash.
    private static func gramHash(at start: Int, tokens: [CloneToken], previous: [Int]) -> UInt64 {
        (start..<start + gramLength).reduce(UInt64(0)) { hash, position in
            let prior = previous[position]
            let distance = prior >= start ? UInt64(position - prior) &* distanceSpread : 0
            return hash &* base &+ (tokens[position].hash &+ distance)
        }
    }

    /// Finds, for each identifier token, the previous token with the same name.
    ///
    /// - Parameter tokens: The tokens.
    /// - Returns: Each token's previous same-named position, or -1 for none or a non-identifier.
    private static func previousOccurrences(_ tokens: [CloneToken]) -> [Int] {
        var last: [UInt64: Int] = [:]
        return tokens.indices.map { position in
            let name = tokens[position].name
            guard name != 0 else { return -1 }
            defer { last[name] = position }
            return last[name] ?? -1
        }
    }

    /// Reports, for each k-gram, whether it has enough distinct tokens to be picked.
    ///
    /// - Parameter tokens: The tokens, at least one k-gram long.
    /// - Returns: One flag per k-gram start.
    private static func diverseGrams(_ tokens: [CloneToken]) -> [Bool] {
        var counts: [UInt64: Int] = [:]
        tokens[0..<gramLength - 1].forEach { counts[$0.hash, default: 0] += 1 }
        return (0...(tokens.count - gramLength)).map { start in
            counts[tokens[start + gramLength - 1].hash, default: 0] += 1
            defer { remove(tokens[start].hash, from: &counts) }
            return counts.count >= minDistinctTokens
        }
    }

    /// Decrements one token's count in a window, dropping it once no occurrences remain.
    ///
    /// - Parameters:
    ///   - hash: The token leaving the window.
    ///   - counts: The window's token counts.
    private static func remove(_ hash: UInt64, from counts: inout [UInt64: Int]) {
        counts[hash] = counts[hash] == 1 ? nil : (counts[hash] ?? 1) - 1
    }

    /// Picks the minimum hash of each window, skipping unpickable k-grams and repeated picks.
    ///
    /// - Parameter hashes: The k-gram hashes.
    /// - Returns: The picked k-gram positions, ascending.
    static func winnow(_ hashes: [UInt64]) -> [Int] {
        guard !hashes.isEmpty else { return [] }
        var picked: [Int] = []
        for start in 0...max(0, hashes.count - window) {
            let positions = start..<min(start + window, hashes.count)
            let best = positions.min { hashes[$0] < hashes[$1] || (hashes[$0] == hashes[$1] && $0 > $1) }
            if let best, hashes[best] != unpickable, picked.last.map({ $0 < best }) ?? true { picked.append(best) }
        }
        return picked
    }
}
