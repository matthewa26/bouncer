import Foundation

/// One function's complexity and size, as its language's analyzer measures them.
public struct FunctionMeasure: Sendable, Equatable {
    /// The declared name, or `nil` where the analyzer doesn't report one (heuristic languages).
    public let name: String?
    public let line: Int
    /// Cyclomatic complexity: decision points plus one.
    public let complexity: Int
    /// Logical lines, or `nil` if not measured.
    public let logicalLines: Int?

    /// Creates a measurement.
    ///
    /// - Parameters:
    ///   - name: The function's name, if known.
    ///   - line: The 1-indexed line it starts on.
    ///   - complexity: Its cyclomatic complexity.
    ///   - logicalLines: Its logical line count, if measured.
    public init(name: String?, line: Int, complexity: Int, logicalLines: Int? = nil) {
        self.name = name
        self.line = line
        self.complexity = complexity
        self.logicalLines = logicalLines
    }
}
