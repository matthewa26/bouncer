import Foundation

/// Runs blocking work, such as an analysis, on a Dispatch queue, so it never holds a Swift concurrency thread
/// the server needs to keep answering calls.
enum BlockingWork {
    /// Runs a closure off the cooperative thread pool and waits for it.
    ///
    /// - Parameter body: The work.
    /// - Returns: What it returned, or the error it threw.
    static func run<Value: Sendable>(_ body: @escaping @Sendable () throws -> Value) async -> Result<Value, Error> {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: Result { try body() })
            }
        }
    }
}
