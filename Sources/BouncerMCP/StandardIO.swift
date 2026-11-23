import Foundation

/// The server's standard input and output, kept apart from the protocol so it can be tested without them.
enum StandardIO {
    /// Streams standard input's lines, read on a dedicated thread, until input ends.
    ///
    /// A blocking read on a concurrency thread would starve the tasks a tool runs, so the reads happen on a
    /// `Thread` of their own that feeds the stream.
    ///
    /// - Returns: The lines, without their line endings.
    static func inputLines() -> AsyncStream<String> {
        let (lines, continuation) = AsyncStream.makeStream(of: String.self)
        let reader = Thread {
            while let line = readLine(strippingNewline: true) { continuation.yield(line) }
            continuation.finish()
        }
        reader.name = "BouncerMCP stdin"
        reader.start()
        return lines
    }

    /// Writes one line to standard output, unbuffered so the client receives it at once.
    ///
    /// - Parameter line: The line, without a line ending.
    static func writeLine(_ line: String) {
        do {
            try FileHandle.standardOutput.write(contentsOf: Data((line + "\n").utf8))
        } catch {
            FileHandle.standardError.write(Data("BouncerMCP: couldn't write a response: \(error)\n".utf8))
        }
    }
}
