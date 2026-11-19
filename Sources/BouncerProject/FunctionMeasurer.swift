import Foundation
import BouncerCore

/// Measures every function in a file, for the rules that weigh complexity against history.
public protocol FunctionMeasuring: Sendable {
    /// Measures a file's functions.
    ///
    /// - Parameter file: The file.
    /// - Returns: Its functions, or `nil` for a language that isn't measured.
    func functions(in file: SourceFile) -> [FunctionMeasure]?
}

/// Measures functions through each language's analyzer, which reports the same complexity and logical line
/// counts its `cyclomatic-complexity` and `long-function` rules use. Languages without an analyzer, such as
/// plain text, Markdown, and config files, aren't measured.
public struct AnalyzerFunctionMeasurer: FunctionMeasuring {
    private let analyzers: [Language: LanguageAnalyzer]

    /// Creates a measurer.
    ///
    /// - Parameter analyzers: The analyzer for each measured language.
    public init(analyzers: [Language: LanguageAnalyzer]) {
        self.analyzers = analyzers
    }

    /// Measures a file's functions with its language's analyzer.
    ///
    /// - Parameter file: The file.
    /// - Returns: Its functions in line order, or `nil` for an unmeasured language or a parse failure.
    public func functions(in file: SourceFile) -> [FunctionMeasure]? {
        guard let analyzer = analyzers[file.language] else { return nil }
        return (try? analyzer.measureFunctions(file: file))?.flatMap { $0 }?.sorted { $0.line < $1.line }
    }
}
