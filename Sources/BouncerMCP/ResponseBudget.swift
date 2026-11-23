import Foundation

/// A cap on how much text a tool response may hold, so one call can't flood the model's context.
///
/// A token budget is estimated at four characters a token. With no cap given the budget is 2,000 tokens;
/// given both a token and a character cap, the smaller one wins.
public struct ResponseBudget: Sendable, Equatable {
    /// The budget, in tokens, when the caller gives none.
    public static let defaultMaxTokens = 2_000
    /// How many characters one token is estimated to take.
    public static let charactersPerToken = 4

    /// The effective cap, in characters.
    public let maxChars: Int

    /// Creates a budget from optional caps.
    ///
    /// - Parameters:
    ///   - maxTokens: A cap in estimated tokens, or `nil` for none.
    ///   - maxChars: A cap in characters, or `nil` for none.
    public init(maxTokens: Int? = nil, maxChars: Int? = nil) {
        let caps = [maxTokens.map(Self.characters(forTokens:)), maxChars].compactMap { $0 }
        let cap = caps.min() ?? Self.defaultMaxTokens * Self.charactersPerToken
        self.maxChars = max(0, cap)
    }

    /// Creates a budget from a tool call's `max_tokens` and `max_chars` arguments, ignoring non-integers.
    ///
    /// - Parameter arguments: The tool call's arguments.
    public init(arguments: [String: JSONValue]) {
        self.init(maxTokens: arguments["max_tokens"]?.intValue, maxChars: arguments["max_chars"]?.intValue)
    }

    /// Converts a token cap to characters, saturating instead of overflowing.
    ///
    /// - Parameter tokens: The cap in estimated tokens.
    /// - Returns: The cap in characters.
    private static func characters(forTokens tokens: Int) -> Int {
        let (product, overflow) = tokens.multipliedReportingOverflow(by: charactersPerToken)
        guard overflow else { return product }
        return tokens < 0 ? Int.min : Int.max
    }

    /// Shortens text to fit the budget, cutting at the end of the last line that fits.
    ///
    /// A line that ends exactly at the budget is kept. When even the first line is too long, it's cut mid-line, so
    /// the result never exceeds the budget.
    ///
    /// - Parameters:
    ///   - text: The text to fit.
    ///   - reserved: Characters to leave free, for a note the caller appends after a cut.
    /// - Returns: The text, whole or cut, and whether it was cut.
    public func fit(_ text: String, reserving reserved: Int = 0) -> (text: String, truncated: Bool) {
        let limit = max(0, maxChars - max(0, reserved))
        guard text.count > limit else { return (text, false) }
        let head = text.prefix(limit)
        if text[head.endIndex] == "\n" { return (String(head), true) }
        guard let lastNewline = head.lastIndex(of: "\n") else { return (String(head), true) }
        return (String(head[..<lastNewline]), true)
    }
}
