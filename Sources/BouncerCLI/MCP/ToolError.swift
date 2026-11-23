/// A tool call that can't be answered, with the one-line reason the agent sees.
struct ToolError: Error, Sendable {
    /// The reason.
    let message: String

    /// Creates an error.
    ///
    /// - Parameter message: The reason.
    init(_ message: String) {
        self.message = message
    }

    /// Runs work, turning any error it throws into a `ToolError` with a context.
    ///
    /// - Parameters:
    ///   - context: What was being done, such as `Can't load the config`.
    ///   - body: The work.
    /// - Returns: What `body` returned.
    /// - Throws: A `ToolError` naming the context and the error.
    static func wrapping<Value>(_ context: String, _ body: () throws -> Value) throws -> Value {
        do {
            return try body()
        } catch let error as ToolError {
            throw error
        } catch {
            throw ToolError("\(context): \(oneLine(error))")
        }
    }

    /// Describes an error on one line.
    ///
    /// - Parameter error: The error.
    /// - Returns: Its description, with newlines turned into spaces.
    static func oneLine(_ error: Error) -> String {
        "\(error)".split(whereSeparator: \.isNewline).joined(separator: " ")
    }
}
