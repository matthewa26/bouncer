import Foundation

/// Where `bouncer mcp` logs: standard error, and only under `--verbose`, since standard output is the protocol.
struct MCPLog: Sendable {
    /// Whether to write anything.
    let verbose: Bool

    /// Writes one line to standard error when verbose.
    ///
    /// - Parameter message: The line.
    func write(_ message: @autoclosure () -> String) {
        guard verbose else { return }
        FileHandle.standardError.write(Data("bouncer mcp: \(message())\n".utf8))
    }
}
