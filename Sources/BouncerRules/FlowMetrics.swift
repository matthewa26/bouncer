import Foundation

/// A function's control-flow measurements beyond cyclomatic and cognitive complexity.
public struct FlowMetrics: Sendable, Equatable {
    /// Acyclic execution paths through the body (Nejmeh's NPath), saturating at `PathCount.cap`.
    public let npath: Int
    /// The longest pyramid of `if`s without `else`, each the last statement of the block holding it.
    public let arrowDepth: Int
    /// The most `break`/`continue` statements that leave or restart any one loop.
    public let maxLoopJumps: Int
    /// Whether the function calls itself with no branch, loop, or early exit anywhere in its body.
    public let recursesWithoutBaseCase: Bool

    /// Creates a function's flow measurements.
    ///
    /// - Parameters:
    ///   - npath: The NPath complexity, already saturated.
    ///   - arrowDepth: The deepest guard-clause-shaped `if` pyramid.
    ///   - maxLoopJumps: The most jumps targeting one loop.
    ///   - recursesWithoutBaseCase: Whether it recurses unconditionally.
    public init(npath: Int = 1, arrowDepth: Int = 0, maxLoopJumps: Int = 0, recursesWithoutBaseCase: Bool = false) {
        self.npath = npath
        self.arrowDepth = arrowDepth
        self.maxLoopJumps = maxLoopJumps
        self.recursesWithoutBaseCase = recursesWithoutBaseCase
    }
}

/// Saturating arithmetic for NPath, which grows exponentially with sequential branches.
public enum PathCount {
    /// The largest NPath value reported; anything bigger is clamped to it.
    public static let cap = 1_000_000_000

    /// Adds two path counts, clamping at `cap`.
    ///
    /// - Parameters:
    ///   - a: One count.
    ///   - b: Another count.
    /// - Returns: Their sum, at most `cap`.
    public static func add(_ a: Int, _ b: Int) -> Int {
        min(cap, a + b)
    }

    /// Multiplies two path counts, clamping at `cap`.
    ///
    /// - Parameters:
    ///   - a: One count, at most `cap`.
    ///   - b: Another count, at most `cap`.
    /// - Returns: Their product, at most `cap`.
    public static func multiply(_ a: Int, _ b: Int) -> Int {
        let (product, overflow) = a.multipliedReportingOverflow(by: b)
        return overflow ? cap : min(cap, product)
    }
}

/// A function's Halstead token counts, and the measures derived from them.
///
/// Operands are identifiers and literals; operators are every other token (keywords, punctuation,
/// and operator symbols), counting a bracket pair once by its opening bracket.
public struct HalsteadCounts: Sendable, Equatable {
    public let distinctOperators: Int
    public let distinctOperands: Int
    public let totalOperators: Int
    public let totalOperands: Int

    /// Creates a function's Halstead counts.
    ///
    /// - Parameters:
    ///   - distinctOperators: n1, the distinct operator tokens.
    ///   - distinctOperands: n2, the distinct operand tokens.
    ///   - totalOperators: N1, every operator token.
    ///   - totalOperands: N2, every operand token.
    public init(
        distinctOperators: Int = 0, distinctOperands: Int = 0, totalOperators: Int = 0, totalOperands: Int = 0
    ) {
        self.distinctOperators = distinctOperators
        self.distinctOperands = distinctOperands
        self.totalOperators = totalOperators
        self.totalOperands = totalOperands
    }

    /// Tallies operator and operand tokens into counts.
    ///
    /// - Parameters:
    ///   - operators: Every operator token's text, in any order.
    ///   - operands: Every operand token's text, in any order.
    /// - Returns: The counts.
    public static func tally(operators: [String], operands: [String]) -> HalsteadCounts {
        HalsteadCounts(
            distinctOperators: Set(operators).count, distinctOperands: Set(operands).count,
            totalOperators: operators.count, totalOperands: operands.count
        )
    }

    /// Volume, N × log2(n): the size of the implementation in bits.
    public var volume: Double {
        let vocabulary = distinctOperators + distinctOperands
        guard vocabulary > 1 else { return 0 }
        return Double(totalOperators + totalOperands) * log2(Double(vocabulary))
    }

    /// Difficulty, (n1 / 2) × (N2 / n2): how error-prone the code is to write or read.
    public var difficulty: Double {
        guard distinctOperands > 0 else { return 0 }
        return Double(distinctOperators) / 2 * Double(totalOperands) / Double(distinctOperands)
    }

    /// Effort, difficulty × volume: the mental effort to write or understand the code.
    public var effort: Double { difficulty * volume }
}
