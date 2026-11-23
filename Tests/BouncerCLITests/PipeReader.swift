import Foundation

/// A failed end-to-end expectation, with a message that says what went wrong.
struct EndToEndFailure: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

/// Collects everything a pipe delivers on a background thread, so the writer never blocks on a full pipe and every
/// read waits with a deadline instead of forever.
final class PipeReader: @unchecked Sendable {
    private let condition = NSCondition()
    private var buffer = Data()
    private var finished = false

    /// Starts draining a pipe's read end.
    ///
    /// - Parameter handle: The read end; draining stops at end of file.
    init(_ handle: FileHandle) {
        Thread { self.drain(handle) }.start()
    }

    /// Everything read and not yet consumed, as text.
    var unread: String {
        condition.lock()
        defer { condition.unlock() }
        return String(decoding: buffer, as: UTF8.self)
    }

    /// Waits for the next complete line.
    ///
    /// - Parameter timeout: How long to wait, in seconds.
    /// - Returns: The line without its line ending.
    /// - Throws: `EndToEndFailure` when the deadline passes or the pipe closes first.
    func nextLine(within timeout: TimeInterval) throws -> String {
        let deadline = Date().addingTimeInterval(timeout)
        condition.lock()
        defer { condition.unlock() }
        while true {
            if let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                let line = String(decoding: buffer[buffer.startIndex..<newline], as: UTF8.self)
                buffer.removeSubrange(buffer.startIndex...newline)
                return line.hasSuffix("\r") ? String(line.dropLast()) : line
            }
            if finished { throw EndToEndFailure("the pipe closed before a full line; unread: \(unreadText)") }
            if !condition.wait(until: deadline) { throw EndToEndFailure("no line within \(Int(timeout))s") }
        }
    }

    /// Waits for end of file and returns everything not yet consumed.
    ///
    /// - Parameter timeout: How long to wait, in seconds.
    /// - Returns: The remaining text.
    /// - Throws: `EndToEndFailure` when the pipe is still open at the deadline.
    func remainder(within timeout: TimeInterval) throws -> String {
        let deadline = Date().addingTimeInterval(timeout)
        condition.lock()
        defer { condition.unlock() }
        while !finished {
            if !condition.wait(until: deadline) { throw EndToEndFailure("the pipe stayed open for \(Int(timeout))s") }
        }
        return unreadText
    }

    private var unreadText: String {
        String(decoding: buffer, as: UTF8.self)
    }

    /// Reads until end of file, waking any waiting reader after each chunk.
    private func drain(_ handle: FileHandle) {
        while true {
            let chunk = handle.availableData
            condition.lock()
            if chunk.isEmpty { finished = true } else { buffer.append(chunk) }
            condition.broadcast()
            condition.unlock()
            if chunk.isEmpty { return }
        }
    }
}
